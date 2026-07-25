import Foundation

enum WCMessageKey {
    static let type = "type"
    static let syncPing = "syncPing"
    static let syncPong = "syncPong"
    static let strike = "strike"
    static let breakPointHaptic = "breakPointHaptic"
    static let status = "status"

    static let t1 = "t1"
    static let t2 = "t2"
    static let t3 = "t3"
    static let watchTimestamp = "watchTimestamp"
    static let peakG = "peakG"
    static let phoneTimestamp = "phoneTimestamp"
}

struct StrikeEvent: Codable, Sendable, Equatable {
    /// Watch-local sample timestamp (`CMLogItem.timestamp`).
    let watchTimestamp: Double
    /// Peak acceleration magnitude in g.
    let peakG: Double
    /// Phone-clock seconds after applying offset on the watch before send.
    let phoneTimestamp: Double

    var phoneTime: PhoneTime { PhoneTime(seconds: phoneTimestamp) }
    var watchTime: WatchTime { WatchTime(seconds: watchTimestamp) }

    func asMessage() -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.strike,
            WCMessageKey.watchTimestamp: watchTimestamp,
            WCMessageKey.peakG: peakG,
            WCMessageKey.phoneTimestamp: phoneTimestamp
        ]
    }

    static func from(message: [String: Any]) -> StrikeEvent? {
        guard
            let watchTimestamp = message[WCMessageKey.watchTimestamp] as? Double,
            let peakG = message[WCMessageKey.peakG] as? Double,
            let phoneTimestamp = message[WCMessageKey.phoneTimestamp] as? Double
        else { return nil }
        return StrikeEvent(
            watchTimestamp: watchTimestamp,
            peakG: peakG,
            phoneTimestamp: phoneTimestamp
        )
    }
}
