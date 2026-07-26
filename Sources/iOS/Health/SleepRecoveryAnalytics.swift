import Foundation

// MARK: - Sleep stages (HealthKit sleepAnalysis)

/// Mapped from `HKCategoryValueSleepAnalysis` — kept as Int-free enum for pure tests.
enum SleepStageKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case inBed
    case awake
    case core
    case deep
    case rem
    case unspecified

    var isAsleep: Bool {
        switch self {
        case .core, .deep, .rem, .unspecified: return true
        case .inBed, .awake: return false
        }
    }

    var title: String {
        switch self {
        case .inBed: return "In bed"
        case .awake: return "Awake"
        case .core: return "Core"
        case .deep: return "Deep"
        case .rem: return "REM"
        case .unspecified: return "Asleep"
        }
    }
}

/// One sleepAnalysis interval (stage + window).
struct SleepIntervalPoint: Equatable, Sendable {
    let start: Date
    let end: Date
    let stage: SleepStageKind
    /// Prefer Apple Watch when collapsing duplicate sources.
    let fromWatch: Bool

    init(start: Date, end: Date, stage: SleepStageKind = .unspecified, fromWatch: Bool = false) {
        self.start = start
        self.end = end
        self.stage = stage
        self.fromWatch = fromWatch
    }

    var durationSeconds: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

/// Transparent 0…100 score from last night — pacing context only, not a clinical instrument.
struct SleepScore: Equatable, Sendable {
    let value: Int
    /// Short band label (e.g. “Solid”).
    let band: String
    /// Whether stage mix contributed (Watch stages) or duration/efficiency only.
    let usedStages: Bool
}

/// Today’s pacing-capacity hint derived from the sleep score — never a diagnosis.
struct SleepPacingHint: Equatable, Sendable {
    let title: String
    let detail: String
}

/// Asleep + stage totals for one night window (18:00 → 18:00 ending on `wakeDayStart`).
struct SleepNightSummary: Equatable, Sendable {
    /// Calendar day the night is attributed to (the morning you wake).
    let wakeDayStart: Date
    let asleepSeconds: TimeInterval
    let inBedSeconds: TimeInterval
    let awakeSeconds: TimeInterval
    let coreSeconds: TimeInterval
    let deepSeconds: TimeInterval
    let remSeconds: TimeInterval
    let unspecifiedAsleepSeconds: TimeInterval
    let intervals: [SleepIntervalPoint]
    let score: SleepScore
    let pacingHint: SleepPacingHint

    var asleepHours: Double { asleepSeconds / 3600 }
    var inBedHours: Double { inBedSeconds / 3600 }

    /// Asleep / in-bed when in-bed is known; else nil.
    var efficiency: Double? {
        guard inBedSeconds > 60 else { return nil }
        return min(1, asleepSeconds / inBedSeconds)
    }

    var hasStageBreakdown: Bool {
        (coreSeconds + deepSeconds + remSeconds) > 60
    }

    func stageFraction(_ stage: SleepStageKind) -> Double? {
        guard asleepSeconds > 60 else { return nil }
        let seconds: TimeInterval
        switch stage {
        case .core: seconds = coreSeconds
        case .deep: seconds = deepSeconds
        case .rem: seconds = remSeconds
        case .unspecified: seconds = unspecifiedAsleepSeconds
        case .awake, .inBed: return nil
        }
        return seconds / asleepSeconds
    }
}

/// Sleep: last night + multi-night asleep totals.
struct SleepTrendSummary: Equatable, Sendable {
    let lastNight: SleepNightSummary?
    /// Oldest → newest nights with any asleep time.
    let nights: [SleepNightSummary]
    let isSparse: Bool

    var isEmpty: Bool { nights.isEmpty }

    init(nights: [SleepNightSummary], sparseThreshold: Int = 2) {
        let sorted = nights
            .filter { $0.asleepSeconds > 0 }
            .sorted { $0.wakeDayStart < $1.wakeDayStart }
        self.nights = sorted
        self.lastNight = sorted.last
        self.isSparse = sorted.count < sparseThreshold
    }
}

// MARK: - Score + pacing (pure)

enum SleepRecoveryAnalytics {
    /// Build a night summary from raw intervals already attributed to one wake day.
    static func summarizeNight(
        wakeDayStart: Date,
        intervals: [SleepIntervalPoint]
    ) -> SleepNightSummary? {
        let sorted = intervals
            .filter { $0.durationSeconds > 0 }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return nil }

        var inBed: TimeInterval = 0
        var awake: TimeInterval = 0
        var core: TimeInterval = 0
        var deep: TimeInterval = 0
        var rem: TimeInterval = 0
        var unspecified: TimeInterval = 0

        for interval in sorted {
            let d = interval.durationSeconds
            switch interval.stage {
            case .inBed: inBed += d
            case .awake: awake += d
            case .core: core += d
            case .deep: deep += d
            case .rem: rem += d
            case .unspecified: unspecified += d
            }
        }

        let stagedAsleep = core + deep + rem
        let asleep = stagedAsleep > 60 ? stagedAsleep + unspecified : unspecified + stagedAsleep
        guard asleep > 60 else { return nil }

        // If we never got inBed samples, approximate bed time as asleep + awake.
        if inBed < asleep {
            inBed = asleep + awake
        }

        let score = score(
            asleepSeconds: asleep,
            inBedSeconds: inBed,
            deepSeconds: deep,
            remSeconds: rem,
            hasStages: stagedAsleep > 60
        )
        return SleepNightSummary(
            wakeDayStart: wakeDayStart,
            asleepSeconds: asleep,
            inBedSeconds: inBed,
            awakeSeconds: awake,
            coreSeconds: core,
            deepSeconds: deep,
            remSeconds: rem,
            unspecifiedAsleepSeconds: unspecified,
            intervals: sorted,
            score: score,
            pacingHint: pacingHint(for: score)
        )
    }

    /// Transparent heuristic — not medical. Duration + efficiency + stage mix when available.
    static func score(
        asleepSeconds: TimeInterval,
        inBedSeconds: TimeInterval,
        deepSeconds: TimeInterval,
        remSeconds: TimeInterval,
        hasStages: Bool
    ) -> SleepScore {
        let hours = asleepSeconds / 3600
        // Duration: full credit 7…9h, taper outside 5…10h.
        let durationPts: Double
        if hours >= 7, hours <= 9 {
            durationPts = 1
        } else if hours < 5 || hours > 11 {
            durationPts = 0.15
        } else if hours < 7 {
            durationPts = 0.15 + 0.85 * ((hours - 5) / 2)
        } else {
            // 9…11h
            durationPts = 0.15 + 0.85 * max(0, (11 - hours) / 2)
        }

        let efficiency: Double
        if inBedSeconds > 60 {
            efficiency = min(1, asleepSeconds / inBedSeconds)
        } else {
            efficiency = 0.85
        }
        // 75% → 0, 90%+ → 1
        let efficiencyPts = min(1, max(0, (efficiency - 0.75) / 0.15))

        var total: Double
        var usedStages = false
        if hasStages, asleepSeconds > 60 {
            usedStages = true
            let deepFrac = deepSeconds / asleepSeconds
            let remFrac = remSeconds / asleepSeconds
            // Deep ideal ~15–20%; REM ideal ~20–25%
            let deepPts = bandScore(deepFrac, low: 0.10, idealLow: 0.13, idealHigh: 0.23, high: 0.35)
            let remPts = bandScore(remFrac, low: 0.12, idealLow: 0.18, idealHigh: 0.28, high: 0.40)
            total = 100 * (0.40 * durationPts + 0.20 * efficiencyPts + 0.20 * deepPts + 0.20 * remPts)
        } else {
            total = 100 * (0.65 * durationPts + 0.35 * efficiencyPts)
        }

        let value = Int(min(100, max(0, total)).rounded())
        let band: String
        switch value {
        case 85...: band = "Strong"
        case 70..<85: band = "Solid"
        case 55..<70: band = "Fair"
        case 40..<55: band = "Light"
        default: band = "Thin"
        }
        return SleepScore(value: value, band: band, usedStages: usedStages)
    }

    static func pacingHint(for score: SleepScore) -> SleepPacingHint {
        switch score.value {
        case 80...:
            return SleepPacingHint(
                title: "Fuller capacity today",
                detail: "Overnight recovery looks strong. Longer Focus blocks are reasonable if you feel steady — still take the nudge when the signal eases."
            )
        case 65..<80:
            return SleepPacingHint(
                title: "Steady capacity today",
                detail: "A solid night. Keep your usual pacing; watch for early easing and prefer the first break over pushing through."
            )
        case 50..<65:
            return SleepPacingHint(
                title: "Protect today’s envelope",
                detail: "Recovery was lighter. Prefer Quick or Short blocks, and treat the first break suggestion as the plan — not optional."
            )
        default:
            return SleepPacingHint(
                title: "Go gentle today",
                detail: "Thin overnight recovery. Favor short blocks, fewer stacked sessions, and earlier breaks. This is pacing context — not a diagnosis."
            )
        }
    }

    /// Prefer Watch-sourced intervals when any Watch asleep sample exists in the set.
    static func preferWatchSources(_ intervals: [SleepIntervalPoint]) -> [SleepIntervalPoint] {
        let watchAsleep = intervals.contains { $0.fromWatch && $0.stage.isAsleep }
        guard watchAsleep else { return intervals }
        return intervals.filter(\.fromWatch)
    }

    private static func bandScore(
        _ value: Double,
        low: Double,
        idealLow: Double,
        idealHigh: Double,
        high: Double
    ) -> Double {
        if value >= idealLow, value <= idealHigh { return 1 }
        if value <= low || value >= high { return 0 }
        if value < idealLow {
            return max(0, (value - low) / max(0.001, idealLow - low))
        }
        return max(0, (high - value) / max(0.001, high - idealHigh))
    }
}
