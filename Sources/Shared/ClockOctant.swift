import Foundation

/// Eight clock directions: 12, 1:30, 3, 4:30, 6, 7:30, 9, 10:30.
enum ClockOctant: Int, CaseIterable, Codable, Sendable, Equatable {
    case twelve = 0
    case oneThirty = 1
    case three = 2
    case fourThirty = 3
    case six = 4
    case sevenThirty = 5
    case nine = 6
    case tenThirty = 7

    /// Human-readable spoke label for HUD.
    var label: String {
        switch self {
        case .twelve: return "12"
        case .oneThirty: return "1:30"
        case .three: return "3"
        case .fourThirty: return "4:30"
        case .six: return "6"
        case .sevenThirty: return "7:30"
        case .nine: return "9"
        case .tenThirty: return "10:30"
        }
    }

    /// Angle from 12 o'clock, clockwise, in radians.
    var angleRadians: Double {
        Double(rawValue) * (.pi / 4.0)
    }

    /// Nearest octant from an angle in radians (0 = 12 o'clock, clockwise positive).
    static func nearest(angleRadians: Double) -> ClockOctant {
        var a = angleRadians.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        let sector = (.pi / 4.0)
        let index = Int(floor((a + sector / 2) / sector)) % 8
        return ClockOctant(rawValue: index) ?? .twelve
    }
}

enum SessionModule: String, Codable, Sendable, Equatable {
    case kineticClock
    case visionPvt
}
