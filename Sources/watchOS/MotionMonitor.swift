import CoreMotion
import Foundation

/// 100Hz accelerometer strike detector. Uses sample timestamp, not handler run time.
@MainActor
final class MotionMonitor {
    /// Peak acceleration threshold in g.
    var spikeThresholdG: Double = 3.5
    /// Refractory period to avoid double-fires on one punch.
    var refractorySeconds: Double = 0.35

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var lastStrikeWatchTime: Double = 0

    var onStrike: ((WatchTime, Double) -> Void)?
    private(set) var isRunning = false

    init() {
        queue.name = "synapse.motion"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 100.0
        isRunning = true
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let magnitude = sqrt(x * x + y * y + z * z)
            // CMAccelerometerData is in g already (user acceleration when using deviceMotion;
            // raw accelerometer includes gravity ≈ 1g at rest).
            let peakG = magnitude
            let sampleTime = data.timestamp

            guard peakG >= self.spikeThresholdG else { return }
            guard sampleTime - self.lastStrikeWatchTime >= self.refractorySeconds else { return }
            self.lastStrikeWatchTime = sampleTime

            let watchTime = WatchTime(seconds: sampleTime)
            Task { @MainActor in
                self.onStrike?(watchTime, peakG)
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        isRunning = false
    }
}
