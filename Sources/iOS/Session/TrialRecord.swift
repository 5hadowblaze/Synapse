import Foundation
import simd

struct TrialRecord: Identifiable, Sendable, Equatable {
    var id: Int { index }
    let index: Int
    /// 3×3 cell (0..8, row-major). Vision flashes a peripheral cell (not 4); Kinetic may mirror targetOctant.
    let targetCell: Int
    var targetOnsetMs: Double?
    var saccadeOnsetMs: Double?
    var gazeSettleMs: Double?
    var strikeMs: Double?
    var visualRtMs: Double?
    var motorRtMs: Double?
    var cognitiveMotorGapMs: Double?
    var peakG: Double?
    var arousalIndex: Float?
    var valid: Bool
    var invalidReason: String?
    /// Kinetic only: prompted clock spoke 0..7.
    var targetOctant: Int?
    /// Kinetic only: watch-classified spoke 0..7.
    var detectedOctant: Int?
    /// Kinetic only: detected == target (timing always kept when strike arrives).
    var spatialMatch: Bool?

    /// Session-relative ms from session start (phone clock).
    static func relativeMs(absolute: PhoneTime, sessionStart: PhoneTime) -> Double {
        absolute.milliseconds(since: sessionStart)
    }
}

struct GazeWindowSample: Sendable, Equatable {
    let dt: Double
    let x: Float
    let y: Float
    let z: Float
}

enum TrialPhase: Equatable {
    case idle
    case waitingForOnset
    case awaitingResponse
    case complete
}
