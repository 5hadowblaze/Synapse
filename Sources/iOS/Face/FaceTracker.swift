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
    /// Face anchor translation in camera space (meters) — used for Kinetic framing prompts.
    var facePositionCamera: SIMD3<Float>?
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
    /// Which athlete arm to draw / use for octant (default right).
    private(set) var preferredArmSide: KineticArmSide = .right

    // MARK: Front-camera posture (Vision on face frames)

    var postureJoints: [PostureOverlayJoint] = []
    var postureBones: [(CGPoint, CGPoint)] = []
    var isPostureTracking = false
    var postureStatusText = "Posture: idle"
    var latestPostureFeatures: PostureFeatures?
    var onPostureFeatures: ((PostureFeatures?, [PostureOverlayJoint], [(CGPoint, CGPoint)]) -> Void)?

    private let saccadeDetector = SaccadeDetector()
    private let arousalIndexer = ArousalIndexer()
    /// Temporary — nil unless SYNAPSE_AROUSAL_DIAG=1. Delete with `ArousalDiagnostics`.
    private let arousalDiagnostics = ArousalDiagnostics.makeIfEnabled()
    private let armEstimator = FrontArmEstimator()
    private var armPoseEnabled = false
    private var postureEnabled = false

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
        arousalDiagnostics?.begin()
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
        arousalDiagnostics?.finish()
        session.pause()
        isSessionRunning = false
        isTracking = false
        facePositionCamera = nil
        estimatedDistanceMeters = nil
        clearArmState()
        clearPostureState()
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

    func setPostureEnabled(_ enabled: Bool) {
        postureEnabled = enabled
        if !enabled {
            clearPostureState()
        } else {
            postureStatusText = "Posture: seeking"
        }
    }

    func setPreferredArmSide(_ side: KineticArmSide) {
        preferredArmSide = side
        if armPoseEnabled {
            armStatusText = "Arm: seeking"
        }
    }

    func resetDetectors() {
        saccadeDetector.reset()
        arousalIndexer.reset()
        arousalDiagnostics?.begin()
        lastSaccade = nil
        lastArousal = nil
    }

    private var bodyPoseEnabled: Bool { armPoseEnabled || postureEnabled }

    private func clearArmState() {
        armOctant = nil
        isArmTracking = false
        armJoints = []
        armBones = []
        armStatusText = "Arm: idle"
        onArmOctant?(nil)
    }

    private func clearPostureState() {
        postureJoints = []
        postureBones = []
        isPostureTracking = false
        latestPostureFeatures = nil
        postureStatusText = "Posture: idle"
        onPostureFeatures?(nil, [], [])
    }

    private func ingestArm(_ result: FrontArmEstimator.Result) {
        armOctant = result.octant
        isArmTracking = result.isTracking
        armJoints = result.joints
        armBones = result.bones
        armStatusText = result.statusText
        onArmOctant?(result.octant)
    }

    private func ingestPosture(
        features: PostureFeatures?,
        joints: [PostureOverlayJoint],
        bones: [(CGPoint, CGPoint)]
    ) {
        latestPostureFeatures = features
        postureJoints = joints
        postureBones = bones
        isPostureTracking = features != nil
        postureStatusText = features != nil ? "Posture tracked" : "Posture: seek torso"
        onPostureFeatures?(features, joints, bones)
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
            self.facePositionCamera = face.isTracked
                ? SIMD3<Float>(translation.x, translation.y, translation.z)
                : nil
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
            let arousal = self.arousalIndexer.update(sample)
            if !face.isTracked {
                // Face lost: publish nothing rather than holding the last good reading, so
                // consumers see the gap instead of a stale value frozen at look-away time.
                self.lastArousal = nil
            } else if let arousal {
                self.lastArousal = arousal
            }
            self.arousalDiagnostics?.record(sample: sample, acceptedValue: arousal)
            self.onGaze?(sample)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Shared Vision body-pose pass for Kinetic arm + Posture Check.
        Task { @MainActor in
            guard self.bodyPoseEnabled else { return }
            let buffer = frame.capturedImage
            let side = self.preferredArmSide
            let needArm = self.armPoseEnabled
            let needPosture = self.postureEnabled
            let faceDistance = self.estimatedDistanceMeters.map(Double.init)
            self.armEstimator.processFrame(
                pixelBuffer: buffer,
                orientation: .right,
                side: side,
                needArm: needArm,
                needPosture: needPosture,
                faceDistanceMeters: faceDistance
            ) { [weak self] frameResult in
                Task { @MainActor in
                    guard let self else { return }
                    if needArm, let arm = frameResult.arm {
                        self.ingestArm(arm)
                    }
                    if needPosture {
                        self.ingestPosture(
                            features: frameResult.postureFeatures,
                            joints: frameResult.postureJoints,
                            bones: frameResult.postureBones
                        )
                    }
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusText = "ARSession error: \(error.localizedDescription)"
            self.isTracking = false
            self.isSessionRunning = false
            self.facePositionCamera = nil
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
