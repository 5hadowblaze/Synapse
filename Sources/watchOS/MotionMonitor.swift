import CoreMotion
import Foundation
import WatchKit

/// 100Hz `CMDeviceMotion` strike detector with gravity-plane octant classification.
@MainActor
final class MotionMonitor {
    /// Peak user-acceleration threshold in g.
    var spikeThresholdG: Double = 3.5
    /// Refractory period to avoid double-fires on one punch.
    var refractorySeconds: Double = 0.35
    /// Calibration window length.
    var calibrationDurationSeconds: Double = 10.0

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var lastStrikeWatchTime: Double = 0

    /// Unit forward in the horizontal plane (toward phone at calibrate).
    private var forwardXZ: (x: Double, z: Double)?
    /// Accumulator during calibration.
    private var calibGravitySum = (x: 0.0, y: 0.0, z: 0.0)
    private var calibAttitudeForwardSum = (x: 0.0, z: 0.0)
    private var calibSampleCount = 0
    private var calibrationDeadline: TimeInterval?
    private(set) var isCalibrating = false
    private(set) var isCalibrated = false

    /// `(watchTime, peakG, detectedOctant?)`
    var onStrike: ((WatchTime, Double, Int?) -> Void)?
    /// Continuous pointing octant while `isStreamingLiveDirection` (throttled by caller).
    var onLiveDirection: ((Int) -> Void)?
    private(set) var isRunning = false
    private(set) var lastDetectedOctant: Int?
    /// When true, classify attitude each sample (not only peak strikes).
    var isStreamingLiveDirection = false
    private var lastLiveOctantSent: Int?
    private var lastLiveSendUptime: TimeInterval = 0
    /// ~10 Hz ceiling for WC live direction.
    private let liveDirectionMinInterval: TimeInterval = 0.1

    init() {
        queue.name = "synapse.motion"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        isRunning = true
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.handleDeviceMotion(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isRunning = false
        isCalibrating = false
        isStreamingLiveDirection = false
        lastLiveOctantSent = nil
        calibrationDeadline = nil
    }

    /// Capture gravity / attitude reference while athlete faces phone, arms neutral.
    func startCalibration(durationSeconds: Double? = nil) {
        let duration = durationSeconds ?? calibrationDurationSeconds
        calibGravitySum = (0, 0, 0)
        calibAttitudeForwardSum = (0, 0)
        calibSampleCount = 0
        forwardXZ = nil
        isCalibrated = false
        isCalibrating = true
        calibrationDeadline = ProcessInfo.processInfo.systemUptime + duration
        if !isRunning { start() }
    }

    func stopCalibration() {
        finishCalibrationIfNeeded(force: true)
    }

    private func handleDeviceMotion(_ data: CMDeviceMotion) {
        let sampleTime = data.timestamp
        let g = data.gravity
        let ua = data.userAcceleration

        if isCalibrating {
            calibGravitySum.x += g.x
            calibGravitySum.y += g.y
            calibGravitySum.z += g.z
            // Device -Z is roughly "out of crown / forward" in xArbitraryZVertical; project later.
            let attitude = data.attitude
            // Use gravity-removed sense of "watch facing": project device -Z into world via rotation matrix.
            let rm = attitude.rotationMatrix
            // Column 2 of rotation matrix maps device Z into reference frame.
            let worldZx = rm.m13
            let worldZz = rm.m33
            calibAttitudeForwardSum.x += -worldZx
            calibAttitudeForwardSum.z += -worldZz
            calibSampleCount += 1

            if let deadline = calibrationDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
                finishCalibrationIfNeeded(force: true)
            }
        }

        if isStreamingLiveDirection, isCalibrated {
            if let live = classifyPointingOctant(attitude: data.attitude, gravity: g) {
                let now = ProcessInfo.processInfo.systemUptime
                if live != lastLiveOctantSent || now - lastLiveSendUptime >= liveDirectionMinInterval {
                    lastLiveOctantSent = live
                    lastLiveSendUptime = now
                    lastDetectedOctant = live
                    Task { @MainActor in
                        self.onLiveDirection?(live)
                    }
                }
            }
        }

        let peakG = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
        guard peakG >= spikeThresholdG else { return }
        guard sampleTime - lastStrikeWatchTime >= refractorySeconds else { return }
        lastStrikeWatchTime = sampleTime

        let octant = classifyOctant(userAcceleration: ua, gravity: g)
        lastDetectedOctant = octant
        let watchTime = WatchTime(seconds: sampleTime)
        Task { @MainActor in
            self.onStrike?(watchTime, peakG, octant)
        }
    }

    private func finishCalibrationIfNeeded(force: Bool) {
        guard isCalibrating else { return }
        if !force, let deadline = calibrationDeadline,
           ProcessInfo.processInfo.systemUptime < deadline {
            return
        }
        isCalibrating = false
        calibrationDeadline = nil
        guard calibSampleCount > 0 else { return }

        let n = Double(calibSampleCount)
        let gx = calibGravitySum.x / n
        let gy = calibGravitySum.y / n
        let gz = calibGravitySum.z / n
        let gMag = sqrt(gx * gx + gy * gy + gz * gz)
        guard gMag > 0.1 else { return }

        // Horizontal forward from averaged attitude, projected off gravity.
        var fx = calibAttitudeForwardSum.x / n
        var fz = calibAttitudeForwardSum.z / n
        // Remove gravity component in XZ if needed — gravity Y dominates when upright.
        let gHorizMag = sqrt(gx * gx + gz * gz)
        if gHorizMag > 0.05 {
            // Nudge forward away from gravity lean in horizontal plane.
            fx -= gx
            fz -= gz
        }
        let fMag = sqrt(fx * fx + fz * fz)
        if fMag < 1e-4 {
            // Fallback: assume +Z is forward in horizontal plane.
            fx = 0
            fz = 1
        } else {
            fx /= fMag
            fz /= fMag
        }
        forwardXZ = (fx, fz)
        isCalibrated = true
    }

    /// Project peak userAcceleration into calibrated horizontal plane → nearest octant.
    private func classifyOctant(
        userAcceleration ua: CMAcceleration,
        gravity g: CMAcceleration
    ) -> Int? {
        horizontalOctant(vectorX: ua.x, vectorY: ua.y, vectorZ: ua.z, gravity: g)
    }

    /// Live pointing: project watch −Z (outward) into the calibrated horizontal plane.
    private func classifyPointingOctant(
        attitude: CMAttitude,
        gravity g: CMAcceleration
    ) -> Int? {
        let rm = attitude.rotationMatrix
        // Device −Z into reference frame (same convention as calibration forward).
        let px = -rm.m13
        let py = -rm.m23
        let pz = -rm.m33
        return horizontalOctant(vectorX: px, vectorY: py, vectorZ: pz, gravity: g, minHorizontal: 0.15)
    }

    private func horizontalOctant(
        vectorX: Double,
        vectorY: Double,
        vectorZ: Double,
        gravity g: CMAcceleration,
        minHorizontal: Double = 0.05
    ) -> Int? {
        guard let forward = forwardXZ, isCalibrated else { return nil }

        // Horizontal plane ≈ reject component along gravity.
        let gMag = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
        guard gMag > 0.1 else { return nil }
        let ngx = g.x / gMag
        let ngy = g.y / gMag
        let ngz = g.z / gMag
        let alongG = vectorX * ngx + vectorY * ngy + vectorZ * ngz
        var hx = vectorX - alongG * ngx
        let hy = vectorY - alongG * ngy
        var hz = vectorZ - alongG * ngz
        _ = hy // vertical residual unused after gravity removal

        // Wrist flip: left wrist mirrors lateral axis relative to punch plane.
        if WKInterfaceDevice.current().wristLocation == .left {
            hx = -hx
        }

        let hMag = sqrt(hx * hx + hz * hz)
        guard hMag > minHorizontal else { return nil }
        hx /= hMag
        hz /= hMag

        // Angle of punch vs forward: 0 at 12 o'clock, clockwise positive.
        let dot = forward.x * hx + forward.z * hz
        let cross = forward.x * hz - forward.z * hx
        let angle = atan2(cross, dot)
        // atan2 gives CCW from forward; clock wants clockwise → negate.
        let clockAngle = -angle
        return ClockOctant.nearest(angleRadians: clockAngle).rawValue
    }
}
