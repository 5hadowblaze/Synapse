import Foundation

/// WatchConnectivity message `type` values and payload field names.
/// Phone and Watch must stay in lockstep — tests cover encode/decode round-trips.
enum WCMessageKey {
    static let type = "type"

    // Watch → Phone
    static let syncPing = "syncPing"
    static let strike = "strike"
    static let liveDirection = "liveDirection"
    static let syncQuality = "syncQuality"
    static let calibrateResult = "calibrateResult"

    // Phone → Watch
    static let syncPong = "syncPong"
    static let breakPointHaptic = "breakPointHaptic"
    static let calibrateStart = "calibrateStart"
    static let calibrateStop = "calibrateStop"
    static let liveDirectionStart = "liveDirectionStart"
    static let liveDirectionStop = "liveDirectionStop"

    // Fields
    static let t1 = "t1"
    static let t2 = "t2"
    static let t3 = "t3"
    static let watchTimestamp = "watchTimestamp"
    static let peakG = "peakG"
    static let phoneTimestamp = "phoneTimestamp"
    static let detectedOctant = "detectedOctant"
    static let duration = "duration"
    static let success = "success"
    static let offsetMs = "offsetMs"
    static let rttMs = "rttMs"
}
