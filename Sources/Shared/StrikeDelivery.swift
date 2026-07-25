import Foundation

/// Pure strike → phone payload decision (no WatchConnectivity).
enum StrikeDeliveryOutcome: Equatable, Sendable {
    case deliver(StrikeEvent)
    case needsClockSync
}

enum StrikeDelivery {
    static func prepare(
        watchTime: WatchTime,
        peakG: Double,
        detectedOctant: Int?,
        offsetSeconds: Double?
    ) -> StrikeDeliveryOutcome {
        guard let offsetSeconds else { return .needsClockSync }
        let phone = watchTime.toPhoneTime(offsetSeconds: offsetSeconds)
        return .deliver(
            StrikeEvent(
                watchTimestamp: watchTime.seconds,
                peakG: peakG,
                phoneTimestamp: phone.seconds,
                detectedOctant: detectedOctant
            )
        )
    }
}
