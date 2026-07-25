import Foundation

struct StrikeEvent: Codable, Sendable, Equatable {
    /// Watch-local sample timestamp (`CMLogItem.timestamp`).
    let watchTimestamp: Double
    /// Peak acceleration magnitude in g.
    let peakG: Double
    /// Phone-clock seconds after applying offset on the watch before send.
    let phoneTimestamp: Double
    /// Nearest of 8 clock octants from calibrated plane (nil if uncalibrated).
    let detectedOctant: Int?

    var phoneTime: PhoneTime { PhoneTime(seconds: phoneTimestamp) }
    var watchTime: WatchTime { WatchTime(seconds: watchTimestamp) }

    func asMessage() -> [String: Any] {
        var message: [String: Any] = [
            WCMessageKey.type: WCMessageKey.strike,
            WCMessageKey.watchTimestamp: watchTimestamp,
            WCMessageKey.peakG: peakG,
            WCMessageKey.phoneTimestamp: phoneTimestamp
        ]
        if let detectedOctant {
            message[WCMessageKey.detectedOctant] = detectedOctant
        }
        return message
    }

    /// Decode a WatchConnectivity strike payload.
    /// Accepts `Int` or `Double` for numeric fields (WC bridging quirks).
    static func from(message: [String: Any]) -> StrikeEvent? {
        if let type = message[WCMessageKey.type] as? String, type != WCMessageKey.strike {
            return nil
        }
        guard
            let watchTimestamp = doubleValue(message[WCMessageKey.watchTimestamp]),
            let peakG = doubleValue(message[WCMessageKey.peakG]),
            let phoneTimestamp = doubleValue(message[WCMessageKey.phoneTimestamp])
        else { return nil }

        let octant: Int?
        if let i = message[WCMessageKey.detectedOctant] as? Int {
            octant = i
        } else if let d = message[WCMessageKey.detectedOctant] as? Double {
            octant = Int(d)
        } else {
            octant = nil
        }
        return StrikeEvent(
            watchTimestamp: watchTimestamp,
            peakG: peakG,
            phoneTimestamp: phoneTimestamp,
            detectedOctant: octant
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}
