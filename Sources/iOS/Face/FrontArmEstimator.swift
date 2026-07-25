import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Front-camera arm / hand direction from Vision pose on AR face frames.
/// Maps wrist vs shoulders (or hand tip) into the same 8 `ClockOctant`s as the Kinetic clock.
final class FrontArmEstimator: @unchecked Sendable {
    struct OverlayJoint: Sendable {
        let name: String
        let point: CGPoint // normalized 0…1, top-left origin, mirrored for selfie preview
    }

    struct Result: Sendable {
        let octant: Int?
        let joints: [OverlayJoint]
        let bones: [(CGPoint, CGPoint)]
        let isTracking: Bool
        let statusText: String
    }

    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let queue = DispatchQueue(label: "com.synapse.frontArm", qos: .userInitiated)
    private var lastProcessTime: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / 15.0

    init() {
        handRequest.maximumHandCount = 2
    }

    /// Throttled Vision pass on the front camera pixel buffer.
    func process(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right,
        completion: @escaping (Result) -> Void
    ) {
        let now = CACurrentMediaTime()
        guard now - lastProcessTime >= minInterval else { return }
        lastProcessTime = now

        queue.async { [bodyRequest, handRequest] in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform([bodyRequest, handRequest])
            } catch {
                completion(Result(
                    octant: nil,
                    joints: [],
                    bones: [],
                    isTracking: false,
                    statusText: "Arm Vision error"
                ))
                return
            }

            let result = Self.estimate(
                body: bodyRequest.results?.first,
                hands: handRequest.results ?? []
            )
            completion(result)
        }
    }

    private static func estimate(
        body: VNHumanBodyPoseObservation?,
        hands: [VNHumanHandPoseObservation]
    ) -> Result {
        var joints: [OverlayJoint] = []
        var bones: [(CGPoint, CGPoint)] = []

        func mirrored(_ p: CGPoint) -> CGPoint {
            // Vision: origin bottom-left → UI top-left, then mirror X for selfie preview.
            CGPoint(x: 1 - p.x, y: 1 - p.y)
        }

        func addJoint(_ name: String, _ point: CGPoint?, confidence: Float) {
            guard let point, confidence > 0.2 else { return }
            joints.append(OverlayJoint(name: name, point: mirrored(point)))
        }

        // Prefer body pose shoulders → wrists.
        var leftShoulder: CGPoint?
        var rightShoulder: CGPoint?
        var leftElbow: CGPoint?
        var rightElbow: CGPoint?
        var leftWrist: CGPoint?
        var rightWrist: CGPoint?
        var leftConf: Float = 0
        var rightConf: Float = 0

        if let body {
            func pt(_ joint: VNHumanBodyPoseObservation.JointName) -> (CGPoint, Float)? {
                guard let p = try? body.recognizedPoint(joint), p.confidence > 0.15 else { return nil }
                return (p.location, p.confidence)
            }
            if let s = pt(.leftShoulder) { leftShoulder = s.0; addJoint("LSh", s.0, confidence: s.1) }
            if let s = pt(.rightShoulder) { rightShoulder = s.0; addJoint("RSh", s.0, confidence: s.1) }
            if let e = pt(.leftElbow) { leftElbow = e.0; addJoint("LEl", e.0, confidence: e.1) }
            if let e = pt(.rightElbow) { rightElbow = e.0; addJoint("REl", e.0, confidence: e.1) }
            if let w = pt(.leftWrist) { leftWrist = w.0; leftConf = w.1; addJoint("LWr", w.0, confidence: w.1) }
            if let w = pt(.rightWrist) { rightWrist = w.0; rightConf = w.1; addJoint("RWr", w.0, confidence: w.1) }

            if let a = leftShoulder, let b = leftElbow { bones.append((mirrored(a), mirrored(b))) }
            if let a = leftElbow, let b = leftWrist { bones.append((mirrored(a), mirrored(b))) }
            if let a = rightShoulder, let b = rightElbow { bones.append((mirrored(a), mirrored(b))) }
            if let a = rightElbow, let b = rightWrist { bones.append((mirrored(a), mirrored(b))) }
            if let a = leftShoulder, let b = rightShoulder { bones.append((mirrored(a), mirrored(b))) }
        }

        // Hand tips as optional extension beyond wrist; also densify overlay with finger chains.
        var leftTip: CGPoint?
        var rightTip: CGPoint?
        let fingerChains: [(String, [VNHumanHandPoseObservation.JointName])] = [
            ("Th", [.thumbCMC, .thumbMP, .thumbTip]),
            ("Ix", [.indexMCP, .indexPIP, .indexTip]),
            ("Md", [.middleMCP, .middlePIP, .middleTip]),
            ("Rg", [.ringMCP, .ringPIP, .ringTip]),
            ("Pk", [.littleMCP, .littlePIP, .littleTip])
        ]
        for hand in hands {
            guard let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.2 else { continue }
            let tipNames: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .thumbTip]
            var bestTip: (CGPoint, Float)?
            for name in tipNames {
                guard let t = try? hand.recognizedPoint(name), t.confidence > 0.2 else { continue }
                if bestTip == nil || t.confidence > bestTip!.1 {
                    bestTip = (t.location, t.confidence)
                }
            }
            // Chirality: compare wrist to body wrists when available.
            let w = wrist.location
            let distL = leftWrist.map { hypot($0.x - w.x, $0.y - w.y) } ?? .greatestFiniteMagnitude
            let distR = rightWrist.map { hypot($0.x - w.x, $0.y - w.y) } ?? .greatestFiniteMagnitude
            let isLeft = distL <= distR
            let prefix = isLeft ? "L" : "R"
            if isLeft {
                leftTip = bestTip?.0 ?? leftTip
                if leftWrist == nil {
                    leftWrist = w
                    leftConf = wrist.confidence
                    addJoint("LWr", w, confidence: wrist.confidence)
                }
            } else {
                rightTip = bestTip?.0 ?? rightTip
                if rightWrist == nil {
                    rightWrist = w
                    rightConf = wrist.confidence
                    addJoint("RWr", w, confidence: wrist.confidence)
                }
            }
            // Finger lattice for wireframe net (overlay only; does not affect octant pick).
            for (tag, chain) in fingerChains {
                var prev: CGPoint? = w
                for (idx, joint) in chain.enumerated() {
                    guard let p = try? hand.recognizedPoint(joint), p.confidence > 0.18 else { continue }
                    addJoint("\(prefix)\(tag)\(idx)", p.location, confidence: p.confidence)
                    if let from = prev {
                        bones.append((mirrored(from), mirrored(p.location)))
                    }
                    prev = p.location
                }
            }
            if let tip = bestTip {
                addJoint("\(prefix)Tip", tip.0, confidence: tip.1)
            }
        }

        let midShoulder: CGPoint? = {
            switch (leftShoulder, rightShoulder) {
            case let (l?, r?): return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
            case let (l?, nil): return l
            case let (nil, r?): return r
            default: return nil
            }
        }()

        // Pick the more extended / confident arm (tip preferred over wrist).
        struct Candidate {
            let origin: CGPoint
            let tip: CGPoint
            let score: CGFloat
        }
        var candidates: [Candidate] = []

        func consider(origin: CGPoint?, tip: CGPoint?, conf: Float) {
            guard let origin, let tip, conf > 0.2 else { return }
            let dx = tip.x - origin.x
            let dy = tip.y - origin.y
            let len = hypot(dx, dy)
            guard len > 0.04 else { return }
            candidates.append(Candidate(origin: origin, tip: tip, score: len * CGFloat(conf)))
        }

        let leftOrigin = midShoulder ?? leftShoulder ?? leftElbow
        let rightOrigin = midShoulder ?? rightShoulder ?? rightElbow
        consider(origin: leftOrigin, tip: leftTip ?? leftWrist, conf: leftConf)
        consider(origin: rightOrigin, tip: rightTip ?? rightWrist, conf: rightConf)

        // Hand-only fallback: use wrist → tip with image center as origin substitute.
        if candidates.isEmpty {
            for hand in hands {
                guard let wrist = try? hand.recognizedPoint(.wrist), wrist.confidence > 0.25,
                      let tip = try? hand.recognizedPoint(.indexTip), tip.confidence > 0.2
                else { continue }
                consider(origin: wrist.location, tip: tip.location, conf: min(wrist.confidence, tip.confidence))
            }
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            return Result(
                octant: nil,
                joints: joints,
                bones: bones,
                isTracking: !joints.isEmpty,
                statusText: joints.isEmpty ? "Arm: seek pose" : "Arm: raise / extend"
            )
        }

        // Mirrored screen space: up = 12, right = 3.
        let o = mirrored(best.origin)
        let t = mirrored(best.tip)
        let dx = t.x - o.x
        let dy = t.y - o.y
        // UIKit y grows down; angle from 12 o'clock clockwise.
        let angle = atan2(Double(dx), Double(-dy))
        let octant = ClockOctant.nearest(angleRadians: angle).rawValue

        bones.append((o, t))

        return Result(
            octant: octant,
            joints: joints,
            bones: bones,
            isTracking: true,
            statusText: "Arm · \(ClockOctant(rawValue: octant)?.label ?? "?")"
        )
    }
}
