import CoreMotion
import Foundation
import WatchKit

/// Device-motion sampling + strike / live-direction classification at 100Hz.
/// Motion callbacks run on a private queue; UI callbacks always hop to the main actor.
final class MotionMonitor: @unchecked Sendable {
    /// Peak user-acceleration threshold in g.
    var spikeThresholdG: Double {
        get { lock.withLock { strikeGate.spikeThresholdG } }
        set { lock.withLock { strikeGate.spikeThresholdG = newValue } }
    }

    var refractorySeconds: Double {
        get { lock.withLock { strikeGate.refractorySeconds } }
        set { lock.withLock { strikeGate.refractorySeconds = newValue } }
    }

    var calibrationDurationSeconds: Double = 10.0

    private let motion: CMMotionManager
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var strikeGate = StrikeGate()

    private var classifier: HorizontalOctantClassifier?
    private var calibGravitySum = (x: 0.0, y: 0.0, z: 0.0)
    private var calibAttitudeForwardSum = (x: 0.0, z: 0.0)
    private var calibSampleCount = 0
    private var calibrationDeadline: TimeInterval?
    private var calibrating = false
    private var calibrated = false
    private var running = false
    private var streamingLiveDirection = false
    private var streamingMotionEnergy = false
    private var energySumSquares = 0.0
    private var energySampleCount = 0
    private var lastEnergySendUptime: TimeInterval = 0
    private let motionEnergyMinInterval: TimeInterval = 1.0
    private var lastLiveOctantSent: Int?
    private var lastLiveSendUptime: TimeInterval = 0
    private let liveDirectionMinInterval: TimeInterval = 0.1

    /// Optional override for tests (`nil` → query `WKInterfaceDevice`).
    var mirrorLateralOverride: Bool?

    /// `(watchTime, peakG, detectedOctant?)`
    var onStrike: (@MainActor (WatchTime, Double, Int?) -> Void)?
    var onLiveDirection: (@MainActor (Int) -> Void)?
    /// Normalized motion energy ~0…1 (RMS of user accel over 1s window).
    var onMotionEnergy: (@MainActor (Double) -> Void)?
    /// Fired when calibration window closes (success or failure).
    var onCalibrationFinished: (@MainActor (Bool) -> Void)?

    var isRunning: Bool { lock.withLock { running } }
    var isCalibrating: Bool { lock.withLock { calibrating } }
    var isCalibrated: Bool { lock.withLock { calibrated } }
    private(set) var lastDetectedOctant: Int?

    var isStreamingLiveDirection: Bool {
        get { lock.withLock { streamingLiveDirection } }
        set { lock.withLock { streamingLiveDirection = newValue } }
    }

    var isStreamingMotionEnergy: Bool {
        get { lock.withLock { streamingMotionEnergy } }
        set {
            lock.withLock {
                streamingMotionEnergy = newValue
                if !newValue {
                    energySumSquares = 0
                    energySampleCount = 0
                }
            }
        }
    }

    init(motionManager: CMMotionManager = CMMotionManager()) {
        self.motion = motionManager
        queue.name = "synapse.motion"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        lock.withLock { running = true }
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handleDeviceMotion(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        lock.withLock {
            running = false
            calibrating = false
            streamingLiveDirection = false
            streamingMotionEnergy = false
            energySumSquares = 0
            energySampleCount = 0
            lastLiveOctantSent = nil
            calibrationDeadline = nil
        }
    }

    /// Capture gravity / attitude reference while athlete faces phone, arms neutral.
    func startCalibration(durationSeconds: Double? = nil) {
        let duration = durationSeconds ?? calibrationDurationSeconds
        lock.withLock {
            calibGravitySum = (0, 0, 0)
            calibAttitudeForwardSum = (0, 0)
            calibSampleCount = 0
            classifier = nil
            calibrated = false
            calibrating = true
            calibrationDeadline = ProcessInfo.processInfo.systemUptime + duration
        }
        if !isRunning { start() }
    }

    func stopCalibration() {
        finishCalibrationIfNeeded(force: true)
    }

    // MARK: - Motion queue

    private func handleDeviceMotion(_ data: CMDeviceMotion) {
        let sampleTime = data.timestamp
        let g = data.gravity
        let ua = data.userAcceleration

        var shouldFinishCalibration = false
        lock.lock()
        if calibrating {
            calibGravitySum.x += g.x
            calibGravitySum.y += g.y
            calibGravitySum.z += g.z
            let rm = data.attitude.rotationMatrix
            calibAttitudeForwardSum.x += -rm.m13
            calibAttitudeForwardSum.z += -rm.m33
            calibSampleCount += 1
            if let deadline = calibrationDeadline,
               ProcessInfo.processInfo.systemUptime >= deadline {
                shouldFinishCalibration = true
            }
        }
        let streaming = streamingLiveDirection
        let streamingEnergy = streamingMotionEnergy
        let isCalib = calibrated
        let cls = classifier
        let mirror = mirrorLateralOverride ?? (WKInterfaceDevice.current().wristLocation == .left)
        lock.unlock()

        if shouldFinishCalibration {
            finishCalibrationIfNeeded(force: true)
        }

        if streamingEnergy {
            let mag = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
            var energyToSend: Double?
            lock.lock()
            energySumSquares += mag * mag
            energySampleCount += 1
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastEnergySendUptime >= motionEnergyMinInterval, energySampleCount > 0 {
                let rms = sqrt(energySumSquares / Double(energySampleCount))
                // ~0.05g quiet desk → ~0; ~0.4g fidgeting → ~1
                energyToSend = min(1.0, max(0.0, (rms - 0.02) / 0.35))
                energySumSquares = 0
                energySampleCount = 0
                lastEnergySendUptime = now
            }
            lock.unlock()
            if let energyToSend {
                Task { @MainActor in
                    self.onMotionEnergy?(energyToSend)
                }
            }
        }

        if streaming, isCalib, let cls {
            if let live = cls.octant(
                vectorX: -data.attitude.rotationMatrix.m13,
                vectorY: -data.attitude.rotationMatrix.m23,
                vectorZ: -data.attitude.rotationMatrix.m33,
                gravityX: g.x,
                gravityY: g.y,
                gravityZ: g.z,
                mirrorLateral: mirror,
                minHorizontal: 0.15
            ) {
                let now = ProcessInfo.processInfo.systemUptime
                var shouldSend = false
                lock.lock()
                if live != lastLiveOctantSent || now - lastLiveSendUptime >= liveDirectionMinInterval {
                    lastLiveOctantSent = live
                    lastLiveSendUptime = now
                    lastDetectedOctant = live
                    shouldSend = true
                }
                lock.unlock()
                if shouldSend {
                    Task { @MainActor in
                        self.onLiveDirection?(live)
                    }
                }
            }
        }

        // No strike scoring while gathering calibration samples or streaming Focus energy.
        let skipStrikes = lock.withLock { calibrating || streamingMotionEnergy }
        guard !skipStrikes else { return }

        let peakG = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
        let fire: Bool = lock.withLock {
            strikeGate.shouldFire(peakG: peakG, at: sampleTime)
        }
        guard fire else { return }

        let octant: Int? = {
            guard let cls else { return nil }
            return cls.octant(
                vectorX: ua.x,
                vectorY: ua.y,
                vectorZ: ua.z,
                gravityX: g.x,
                gravityY: g.y,
                gravityZ: g.z,
                mirrorLateral: mirror
            )
        }()
        lastDetectedOctant = octant
        let watchTime = WatchTime(seconds: sampleTime)
        Task { @MainActor in
            self.onStrike?(watchTime, peakG, octant)
        }
    }

    private func finishCalibrationIfNeeded(force: Bool) {
        lock.lock()
        guard calibrating else {
            lock.unlock()
            return
        }
        if !force, let deadline = calibrationDeadline,
           ProcessInfo.processInfo.systemUptime < deadline {
            lock.unlock()
            return
        }
        calibrating = false
        calibrationDeadline = nil
        let built = HorizontalOctantClassifier.fromCalibration(
            gravitySumX: calibGravitySum.x,
            gravitySumY: calibGravitySum.y,
            gravitySumZ: calibGravitySum.z,
            forwardSumX: calibAttitudeForwardSum.x,
            forwardSumZ: calibAttitudeForwardSum.z,
            sampleCount: calibSampleCount
        )
        classifier = built
        calibrated = built != nil
        let success = calibrated
        lock.unlock()

        Task { @MainActor in
            self.onCalibrationFinished?(success)
        }
    }
}
