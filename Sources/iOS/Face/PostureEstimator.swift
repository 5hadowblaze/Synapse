import CoreGraphics
import Foundation
import Vision

/// Upper-body posture proxy from front-camera Vision joints + optional face distance.
/// Wellness signal vs the user's own sit-tall baseline — not a clinical posture score.
struct PostureFeatures: Equatable, Sendable {
    /// Nose above mid-shoulder, divided by shoulder width (Vision Y-up). Higher = more upright.
    let cranioRatio: Double
    /// Mid-shoulder Y in Vision coords (0…1, bottom-left origin).
    let midShoulderY: Double
    /// Camera-to-face meters when AR face is tracked.
    let faceDistanceMeters: Double?
    /// Minimum joint confidence used for this sample.
    let quality: Float
}

struct PostureOverlayJoint: Equatable, Sendable {
    let name: String
    /// Normalized 0…1, top-left origin, mirrored for selfie preview.
    let point: CGPoint
}

struct PostureSample: Equatable, Sendable {
    let time: TimeInterval
    /// 0 = at / better than baseline uprightness, 1 = max adverse drift.
    let postureScore: Double
    let isTracking: Bool
    let qualityOK: Bool
    let features: PostureFeatures?
    let joints: [PostureOverlayJoint]
    let bones: [(CGPoint, CGPoint)]

    static func == (lhs: PostureSample, rhs: PostureSample) -> Bool {
        lhs.time == rhs.time
            && lhs.postureScore == rhs.postureScore
            && lhs.isTracking == rhs.isTracking
            && lhs.qualityOK == rhs.qualityOK
            && lhs.features == rhs.features
            && lhs.joints == rhs.joints
            && lhs.bones.count == rhs.bones.count
            && zip(lhs.bones, rhs.bones).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

/// Frozen sit-tall reference for persistence across Lab → Focus.
struct PostureBaselineSnapshot: Equatable, Codable, Sendable {
    let cranioMean: Double
    let cranioStd: Double
    let midShoulderYMean: Double
    let midShoulderYStd: Double
    let faceDistanceMean: Double?
    let faceDistanceStd: Double?
    let savedAt: TimeInterval
}

/// Extracts features from a Vision body pose observation (front camera).
enum PostureFeatureExtractor {
    static let minJointConfidence: Float = 0.25
    static let minShoulderWidth: Double = 0.04

    /// Vision bottom-left → UI top-left, then mirror X for selfie preview.
    static func mirrored(_ p: CGPoint) -> CGPoint {
        CGPoint(x: 1 - p.x, y: 1 - p.y)
    }

    static func extract(
        body: VNHumanBodyPoseObservation?,
        faceDistanceMeters: Double?
    ) -> (features: PostureFeatures?, joints: [PostureOverlayJoint], bones: [(CGPoint, CGPoint)]) {
        guard let body else {
            return (nil, [], [])
        }

        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> (CGPoint, Float)? {
            guard let p = try? body.recognizedPoint(joint), p.confidence >= minJointConfidence else {
                return nil
            }
            return (p.location, p.confidence)
        }

        guard let left = point(.leftShoulder),
              let right = point(.rightShoulder)
        else {
            return (nil, [], [])
        }

        let nose = point(.nose)
        let neck = point(.neck)

        var joints: [PostureOverlayJoint] = [
            PostureOverlayJoint(name: "LSh", point: mirrored(left.0)),
            PostureOverlayJoint(name: "RSh", point: mirrored(right.0))
        ]
        var bones: [(CGPoint, CGPoint)] = [
            (mirrored(left.0), mirrored(right.0))
        ]

        if let neck {
            joints.append(PostureOverlayJoint(name: "Nk", point: mirrored(neck.0)))
            bones.append((mirrored(left.0), mirrored(neck.0)))
            bones.append((mirrored(right.0), mirrored(neck.0)))
        }
        if let nose {
            joints.append(PostureOverlayJoint(name: "Ns", point: mirrored(nose.0)))
            if let neck {
                bones.append((mirrored(neck.0), mirrored(nose.0)))
            } else {
                let mid = CGPoint(
                    x: (left.0.x + right.0.x) * 0.5,
                    y: (left.0.y + right.0.y) * 0.5
                )
                bones.append((mirrored(mid), mirrored(nose.0)))
            }
        }

        let mid = CGPoint(
            x: (left.0.x + right.0.x) * 0.5,
            y: (left.0.y + right.0.y) * 0.5
        )
        let shoulderWidth = hypot(left.0.x - right.0.x, left.0.y - right.0.y)
        guard shoulderWidth >= minShoulderWidth else {
            return (nil, joints, bones)
        }

        // Prefer nose; fall back to neck for cranio proxy when nose is missing.
        let headY: Double
        var quality = min(left.1, right.1)
        if let nose {
            headY = Double(nose.0.y)
            quality = min(quality, nose.1)
        } else if let neck {
            headY = Double(neck.0.y)
            quality = min(quality, neck.1)
        } else {
            return (nil, joints, bones)
        }

        let cranioRatio = (headY - Double(mid.y)) / shoulderWidth
        let features = PostureFeatures(
            cranioRatio: cranioRatio,
            midShoulderY: Double(mid.y),
            faceDistanceMeters: faceDistanceMeters,
            quality: quality
        )
        return (features, joints, bones)
    }
}

/// Sit-tall baseline + sustained-drift fire. Parallel to Focus fade — never weights fade.
struct PostureDriftDetector {
    /// Lab Posture Check: ~10 s at 8 Hz.
    static let labBaselineSamples = 80
    /// Focus mode: ~27.5 s at 8 Hz — longer sit-tall learn than Lab (not a reuse of a short Lab baseline).
    static let focusBaselineSamples = 220
    /// Alias for Lab / default constructor.
    static let defaultBaselineSamples = labBaselineSamples
    /// Lab cooldown between nudges (~90 s).
    static let defaultCooldownSeconds: TimeInterval = 90
    /// Focus: longer gap so desk blocks aren't naggy.
    static let focusCooldownSeconds: TimeInterval = 120
    /// Lab: ~7 s sustained drift at 8 Hz.
    static let defaultSamplesToFire = 56
    /// Focus: ~8 s sustained drift at 8 Hz.
    static let focusSamplesToFire = 64
    static let defaultMinFeatureStd: Double = 0.015
    static let qualityFloor: Float = 0.25
    /// Soft threshold on the 0…1 score — ~0.48 once calibrated (less twitchy than ~0.35 / ≈1σ).
    static let defaultScoreThreshold: Double = 0.48

    private var baselineSamplesNeeded: Int
    private var cooldownSeconds: TimeInterval
    private var samplesToFire: Int
    private var minFeatureStd: Double

    private var pending: [PostureFeatures] = []
    private var snapshot: PostureBaselineSnapshot?
    private var consecutiveExceedances = 0
    private var lastFireAt: TimeInterval?
    private(set) var fireCount = 0
    private(set) var lastScore: Double?

    init(
        baselineSamples: Int = PostureDriftDetector.defaultBaselineSamples,
        cooldownSeconds: TimeInterval = PostureDriftDetector.defaultCooldownSeconds,
        samplesToFire: Int = PostureDriftDetector.defaultSamplesToFire,
        minFeatureStd: Double = PostureDriftDetector.defaultMinFeatureStd
    ) {
        self.baselineSamplesNeeded = max(8, baselineSamples)
        self.cooldownSeconds = cooldownSeconds
        self.samplesToFire = max(1, samplesToFire)
        self.minFeatureStd = minFeatureStd
    }

    /// Clears calibration / fire state. Pass Lab vs Focus lengths / cooldown / sustain.
    mutating func reset(
        baselineSamples: Int? = nil,
        cooldownSeconds: TimeInterval? = nil,
        samplesToFire: Int? = nil
    ) {
        if let baselineSamples {
            baselineSamplesNeeded = max(8, baselineSamples)
        }
        if let cooldownSeconds {
            self.cooldownSeconds = cooldownSeconds
        }
        if let samplesToFire {
            self.samplesToFire = max(1, samplesToFire)
        }
        pending = []
        snapshot = nil
        consecutiveExceedances = 0
        lastFireAt = nil
        fireCount = 0
        lastScore = nil
    }

    var isBaselineReady: Bool { snapshot != nil }
    var baselineProgress: Double {
        if snapshot != nil { return 1 }
        return min(1, Double(pending.count) / Double(baselineSamplesNeeded))
    }

    var exportedBaseline: PostureBaselineSnapshot? { snapshot }

    mutating func applySavedBaseline(_ saved: PostureBaselineSnapshot) {
        snapshot = saved
        pending = []
        consecutiveExceedances = 0
        lastScore = nil
    }

    /// Ingest one frame. Returns whether a posture nudge should fire (edge-triggered).
    mutating func ingest(
        now: TimeInterval,
        features: PostureFeatures?,
        joints: [PostureOverlayJoint],
        bones: [(CGPoint, CGPoint)]
    ) -> (sample: PostureSample, fired: Bool) {
        guard let features, features.quality >= Self.qualityFloor else {
            consecutiveExceedances = 0
            let sample = PostureSample(
                time: now,
                postureScore: lastScore ?? 0,
                isTracking: false,
                qualityOK: false,
                features: features,
                joints: joints,
                bones: bones
            )
            return (sample, false)
        }

        if snapshot == nil {
            pending.append(features)
            if pending.count >= baselineSamplesNeeded {
                freezeBaseline()
            }
            let sample = PostureSample(
                time: now,
                postureScore: 0,
                isTracking: true,
                qualityOK: true,
                features: features,
                joints: joints,
                bones: bones
            )
            lastScore = 0
            return (sample, false)
        }

        let score = scoreAgainstBaseline(features)
        lastScore = score

        let threshold = scoreThreshold()
        let exceeds = score > threshold
        if exceeds {
            consecutiveExceedances += 1
        } else {
            consecutiveExceedances = 0
        }

        var fired = false
        if consecutiveExceedances >= samplesToFire {
            let cooled = lastFireAt.map { now - $0 >= cooldownSeconds } ?? true
            if cooled {
                lastFireAt = now
                fireCount += 1
                consecutiveExceedances = 0
                fired = true
            }
        }

        let sample = PostureSample(
            time: now,
            postureScore: score,
            isTracking: true,
            qualityOK: true,
            features: features,
            joints: joints,
            bones: bones
        )
        return (sample, fired)
    }

    /// Test helper — force a scored ingest after baseline is ready.
    mutating func ingestForced(
        now: TimeInterval,
        features: PostureFeatures
    ) -> Bool {
        let result = ingest(now: now, features: features, joints: [], bones: [])
        return result.fired
    }

    private mutating func freezeBaseline() {
        let cranios = pending.map(\.cranioRatio)
        let mids = pending.map(\.midShoulderY)
        let dists = pending.compactMap(\.faceDistanceMeters)

        snapshot = PostureBaselineSnapshot(
            cranioMean: mean(cranios),
            cranioStd: max(std(cranios), minFeatureStd),
            midShoulderYMean: mean(mids),
            midShoulderYStd: max(std(mids), minFeatureStd),
            faceDistanceMean: dists.isEmpty ? nil : mean(dists),
            faceDistanceStd: dists.isEmpty ? nil : max(std(dists), minFeatureStd * 0.5),
            savedAt: ProcessInfo.processInfo.systemUptime
        )
        pending = []
    }

    /// Higher = more slumped / leaned-in vs sit-tall baseline.
    private func scoreAgainstBaseline(_ f: PostureFeatures) -> Double {
        guard let snap = snapshot else { return 0 }

        // Cranio drop (lost upright head–shoulder separation).
        let cranioZ = max(0, (snap.cranioMean - f.cranioRatio) / snap.cranioStd)
        // Shoulders rising in Vision Y (shrug / collapse toward head).
        let shoulderZ = max(0, (f.midShoulderY - snap.midShoulderYMean) / snap.midShoulderYStd)

        var terms: [Double] = [
            min(3, cranioZ) / 3,
            min(3, shoulderZ) / 3
        ]
        var weights: [Double] = [0.55, 0.25]

        if let meanD = snap.faceDistanceMean,
           let stdD = snap.faceDistanceStd,
           let dist = f.faceDistanceMeters {
            let leanZ = max(0, (meanD - dist) / stdD)
            terms.append(min(3, leanZ) / 3)
            weights.append(0.20)
        }

        let wSum = weights.reduce(0, +)
        let weighted = zip(terms, weights).map { $0 * $1 }.reduce(0, +) / wSum
        return min(1, max(0, weighted))
    }

    /// Soft threshold on the 0…1 score — see `defaultScoreThreshold`.
    private func scoreThreshold() -> Double {
        Self.defaultScoreThreshold
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func std(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
