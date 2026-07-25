import ARKit
import Foundation
import simd

@Observable
@MainActor
final class FaceTracker: NSObject {
    var isTracking = false
    var latestGaze: GazeSample?
    var statusText = "Face: idle"
    var onGaze: ((GazeSample) -> Void)?

    private let session = ARSession()
    private let saccadeDetector = SaccadeDetector()
    private let arousalIndexer = ArousalIndexer()

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
        saccadeDetector.reset()
        arousalIndexer.reset()
        statusText = "Face tracking started"
    }

    func stop() {
        session.pause()
        isTracking = false
        statusText = "Face tracking stopped"
    }

    func resetDetectors() {
        saccadeDetector.reset()
        arousalIndexer.reset()
        lastSaccade = nil
        lastArousal = nil
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
            self.statusText = face.isTracked ? "Face tracked" : "Face lost"
            if let saccade = self.saccadeDetector.process(sample) {
                if saccade.settle == nil {
                    self.lastSaccade = saccade
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

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusText = "ARSession error: \(error.localizedDescription)"
            self.isTracking = false
        }
    }
}
