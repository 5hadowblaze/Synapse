import ARKit
import Foundation
import simd

@Observable
@MainActor
final class FaceTracker: NSObject {
    /// Shared session — attach at most one `ARSCNView` to this; never run a second face config.
    let session = ARSession()

    var isTracking = false
    /// True after `start()` until `stop()` — independent of momentary face loss.
    private(set) var isSessionRunning = false
    var latestGaze: GazeSample?
    var statusText = "Face: idle"
    var onGaze: ((GazeSample) -> Void)?

    /// Face-space look-at and mid-eye for preview / mapper (updated each tracked frame).
    var latestLookAt = SIMD3<Float>(0, 0, -1)
    var latestMidEye = SIMD3<Float>(0, 0, 0)
    /// Approximate camera-to-face distance in meters from face transform translation.
    var estimatedDistanceMeters: Float?
    var eyeBlink: Float = 0
    var eyeWide: Float = 0
    /// Bumps on saccade onset so the preview can flash.
    var saccadeFlashToken = 0

    // MARK: Front-camera arm (Vision on face frames)

    /// Camera-estimated pointing octant (Kinetic spokes; independent of Watch).
    var armOctant: Int?
    var isArmTracking = false
    var armStatusText = "Arm: idle"
    /// Normalized mirrored joints for overlay (0…1, top-left).
    var armJoints: [FrontArmEstimator.OverlayJoint] = []
    var armBones: [(CGPoint, CGPoint)] = []
    var onArmOctant: ((Int?) -> Void)?

    private let saccadeDetector = SaccadeDetector()
    private let arousalIndexer = ArousalIndexer()
    private let armEstimator = FrontArmEstimator()
    private var armPoseEnabled = false

    var lastSaccade: SaccadeOnset?
    var lastArousal: Float?

    func start() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusText = "TrueDepth / face tracking unsupported"
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
        saccadeDetector.reset()
        arousalIndexer.reset()
        statusText = "Face tracking started"
    }

    /// Idempotent — re-runs face config if the session was paused while flagged running
    /// (e.g. after rear-body path stole TrueDepth).
    func ensureStarted() {
        guard ARFaceTrackingConfiguration.isSupported else {
            statusText = "TrueDepth / face tracking unsupported"
            return
        }
        if isSessionRunning, session.delegate === self, session.configuration is ARFaceTrackingConfiguration {
            return
        }
        start()
    }

    /// Force face anchors to re-add so a newly attached `ARSCNView` gets `nodeFor`.
    func refreshPreviewAnchors() {
        guard isSessionRunning, ARFaceTrackingConfiguration.isSupported else {
            ensureStarted()
            return
        }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.delegate = self
        session.run(config, options: [.removeExistingAnchors])
    }

    func stop() {
        session.pause()
        isSessionRunning = false
        isTracking = false
        estimatedDistanceMeters = nil
        clearArmState()
        statusText = "Face tracking stopped"
    }

    func setArmPoseEnabled(_ enabled: Bool) {
        armPoseEnabled = enabled
        if !enabled {
            clearArmState()
        } else {
            armStatusText = "Arm: seeking"
        }
    }

    func resetDetectors() {
        saccadeDetector.reset()
        arousalIndexer.reset()
        lastSaccade = nil
        lastArousal = nil
    }

    private func clearArmState() {
        armOctant = nil
        isArmTracking = false
        armJoints = []
        armBones = []
        armStatusText = "Arm: idle"
        onArmOctant?(nil)
    }

    private func ingestArm(_ result: FrontArmEstimator.Result) {
        armOctant = result.octant
        isArmTracking = result.isTracking
        armJoints = result.joints
        armBones = result.bones
        armStatusText = result.statusText
        onArmOctant?(result.octant)
    }
}

extension FaceTracker: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
        let look = face.lookAtPoint
        let blinkL = face.blendShapes[.eyeBlinkLeft]?.floatValue ?? 0
        let blinkR = face.blendShapes[.eyeBlinkRight]?.floatValue ?? 0
        let wideL = face.blendShapes[.eyeWideLeft]?.floatValue ?? 0
        let wideR = face.blendShapes[.eyeWideRight]?.floatValue ?? 0
        let frameTime = session.currentFrame?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let timestamp = PhoneTime(seconds: frameTime)

        let leftEye = face.leftEyeTransform.columns.3
        let rightEye = face.rightEyeTransform.columns.3
        let midEye = SIMD3<Float>(
            (leftEye.x + rightEye.x) * 0.5,
            (leftEye.y + rightEye.y) * 0.5,
            (leftEye.z + rightEye.z) * 0.5
        )
        let translation = face.transform.columns.3
        let distance = simd_length(SIMD3<Float>(translation.x, translation.y, translation.z))

        let sample = GazeSample(
            time: timestamp,
            lookAt: SIMD3<Float>(look.x, look.y, look.z),
            eyeBlinkLeft: blinkL,
            eyeBlinkRight: blinkR,
            eyeWideLeft: wideL,
            eyeWideRight: wideR
        )

        Task { @MainActor in
            self.isTracking = face.isTracked
            self.latestGaze = sample
            self.latestLookAt = sample.lookAt
            self.latestMidEye = midEye
            self.estimatedDistanceMeters = face.isTracked ? distance : nil
            self.eyeBlink = max(blinkL, blinkR)
            self.eyeWide = sample.eyeWide
            self.statusText = face.isTracked ? "Face tracked" : "Face lost"
            if let saccade = self.saccadeDetector.process(sample) {
                if saccade.settle == nil {
                    self.lastSaccade = saccade
                    self.saccadeFlashToken &+= 1
                } else {
                    self.lastSaccade = SaccadeOnset(
                        onset: self.lastSaccade?.onset ?? saccade.onset,
                        settle: saccade.settle
                    )
                }
            }
            if let arousal = self.arousalIndexer.update(sample) {
                self.lastArousal = arousal
            }
            self.onGaze?(sample)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Arm pose runs on the shared front face session when Kinetic enables it.
        Task { @MainActor in
            guard self.armPoseEnabled else { return }
            let buffer = frame.capturedImage
            self.armEstimator.process(pixelBuffer: buffer, orientation: .right) { [weak self] result in
                Task { @MainActor in
                    self?.ingestArm(result)
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusText = "ARSession error: \(error.localizedDescription)"
            self.isTracking = false
            self.isSessionRunning = false
            self.estimatedDistanceMeters = nil
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            self.statusText = "Face session interrupted"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.ensureStarted()
            self.statusText = "Face session resumed"
        }
    }
}
