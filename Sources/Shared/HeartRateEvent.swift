import Foundation

/// Watch → Phone heart-rate sample. Series 5 yields ~1 BPM update / few seconds during workout — not sample-locked to camera frames.
struct HeartRateEvent: Sendable, Equatable {
    let bpm: Double
    /// Watch uptime seconds at send (WatchTime domain).
    let watchTimestamp: Double
    /// Phone-clock seconds = watchTimestamp + offset when available.
    let phoneTimestamp: Double
    /// HealthKit quantity window start (CFAbsoluteTime / timeIntervalSinceReferenceDate).
    let hkStart: Double?
    /// HealthKit quantity window end.
    let hkEnd: Double?
    /// Provenance for schema honesty (`workoutBuilder` | `unknown`).
    let source: String

    func asMessage() -> [String: Any] {
        var message: [String: Any] = [
            WCMessageKey.type: WCMessageKey.heartRate,
            WCMessageKey.bpm: bpm,
            WCMessageKey.watchTimestamp: watchTimestamp,
            WCMessageKey.phoneTimestamp: phoneTimestamp,
            WCMessageKey.hrSource: source
        ]
        if let hkStart { message[WCMessageKey.hkStart] = hkStart }
        if let hkEnd { message[WCMessageKey.hkEnd] = hkEnd }
        return message
    }

    static func from(message: [String: Any]) -> HeartRateEvent? {
        if let type = message[WCMessageKey.type] as? String, type != WCMessageKey.heartRate {
            return nil
        }
        guard
            let bpm = doubleValue(message[WCMessageKey.bpm]),
            let watchTimestamp = doubleValue(message[WCMessageKey.watchTimestamp]),
            let phoneTimestamp = doubleValue(message[WCMessageKey.phoneTimestamp])
        else { return nil }
        let source = (message[WCMessageKey.hrSource] as? String) ?? "unknown"
        return HeartRateEvent(
            bpm: bpm,
            watchTimestamp: watchTimestamp,
            phoneTimestamp: phoneTimestamp,
            hkStart: doubleValue(message[WCMessageKey.hkStart]),
            hkEnd: doubleValue(message[WCMessageKey.hkEnd]),
            source: source
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
