import Foundation

/// Parsed Phone → Watch commands (shared contract for tests + Watch handler).
enum WatchInboundCommand: Equatable, Sendable {
    case breakPointHaptic
    case calibrateStart(durationSeconds: Double)
    case calibrateStop
    case liveDirectionStart
    case liveDirectionStop
    case motionEnergyStart
    case motionEnergyStop

    static func parse(_ message: [String: Any]) -> WatchInboundCommand? {
        guard let type = message[WCMessageKey.type] as? String else { return nil }
        switch type {
        case WCMessageKey.breakPointHaptic:
            return .breakPointHaptic
        case WCMessageKey.calibrateStart:
            let duration = Self.doubleValue(message[WCMessageKey.duration]) ?? 10
            return .calibrateStart(durationSeconds: duration)
        case WCMessageKey.calibrateStop:
            return .calibrateStop
        case WCMessageKey.liveDirectionStart:
            return .liveDirectionStart
        case WCMessageKey.liveDirectionStop:
            return .liveDirectionStop
        case WCMessageKey.motionEnergyStart:
            return .motionEnergyStart
        case WCMessageKey.motionEnergyStop:
            return .motionEnergyStop
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }
}

/// Helpers for Watch → Phone payload construction (shared with phone-side parsers in tests).
enum WatchOutboundMessage {
    static func syncQuality(offsetMs: Double, rttMs: Double) -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.syncQuality,
            WCMessageKey.offsetMs: offsetMs,
            WCMessageKey.rttMs: rttMs
        ]
    }

    static func liveDirection(octant: Int) -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.liveDirection,
            WCMessageKey.detectedOctant: octant
        ]
    }

    static func calibrateResult(success: Bool) -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.calibrateResult,
            WCMessageKey.success: success
        ]
    }

    static func syncPing(t1: Double) -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.syncPing,
            WCMessageKey.t1: t1
        ]
    }

    static func heartRate(_ event: HeartRateEvent) -> [String: Any] {
        event.asMessage()
    }

    static func motionEnergy(_ energy: Double) -> [String: Any] {
        [
            WCMessageKey.type: WCMessageKey.motionEnergy,
            WCMessageKey.energy: energy
        ]
    }
}
