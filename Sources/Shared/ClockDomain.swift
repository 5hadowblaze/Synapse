import Foundation

/// Phone-local media time (same domain as `CACurrentMediaTime` / ARKit timestamps on iOS).
/// Never mix with `WatchTime` without an explicit offset conversion.
struct PhoneTime: Hashable, Comparable, Sendable {
    let seconds: Double

    static func now() -> PhoneTime {
        PhoneTime(seconds: ProcessInfo.processInfo.systemUptime)
    }

    static func < (lhs: PhoneTime, rhs: PhoneTime) -> Bool {
        lhs.seconds < rhs.seconds
    }

    func milliseconds(since other: PhoneTime) -> Double {
        (seconds - other.seconds) * 1000.0
    }

    func advancing(byMilliseconds ms: Double) -> PhoneTime {
        PhoneTime(seconds: seconds + ms / 1000.0)
    }
}

/// Watch-local motion / boot-relative time (`CMLogItem.timestamp` domain).
struct WatchTime: Hashable, Comparable, Sendable {
    let seconds: Double

    static func now() -> WatchTime {
        // Matches CMLogItem.timestamp (uptime). QuartzCore is unavailable on watchOS.
        WatchTime(seconds: ProcessInfo.processInfo.systemUptime)
    }

    static func < (lhs: WatchTime, rhs: WatchTime) -> Bool {
        lhs.seconds < rhs.seconds
    }

    /// Convert to phone clock using Cristian's offset: `t_phone ≈ t_watch + offset`.
    func toPhoneTime(offsetSeconds: Double) -> PhoneTime {
        PhoneTime(seconds: seconds + offsetSeconds)
    }
}

/// Result of a Cristian's-algorithm sample.
struct ClockSyncSample: Sendable {
    let offsetSeconds: Double
    let rttSeconds: Double

    var offsetMs: Double { offsetSeconds * 1000.0 }
    var rttMs: Double { rttSeconds * 1000.0 }

    /// Cristian: offset = ((t2 - t1) + (t3 - t4)) / 2
    static func cristian(t1: WatchTime, t2: PhoneTime, t3: PhoneTime, t4: WatchTime) -> ClockSyncSample {
        let offset = ((t2.seconds - t1.seconds) + (t3.seconds - t4.seconds)) / 2.0
        let rtt = (t4.seconds - t1.seconds) - (t3.seconds - t2.seconds)
        return ClockSyncSample(offsetSeconds: offset, rttSeconds: max(0, rtt))
    }
}

enum ClockSyncConfig {
    static let burstSampleCount = 20
    static let resyncIntervalSeconds: TimeInterval = 30
}
