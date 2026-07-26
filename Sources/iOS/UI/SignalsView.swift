import Charts
import SwiftUI

// MARK: - Chrome (matches FocusViews FocusChrome — calm dark teal)

private enum SignalsChrome {
    static let canvasTop = Color(red: 0.045, green: 0.07, blue: 0.085)
    static let canvasMid = Color(red: 0.025, green: 0.04, blue: 0.055)
    static let surface = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.10)
    static let label = Color.white.opacity(0.38)
    static let body = Color.white.opacity(0.55)
    static let accent = Color(red: 0.35, green: 0.72, blue: 0.68)
    static let heart = Color(red: 0.85, green: 0.45, blue: 0.42)
    static let pace = Color(red: 0.35, green: 0.72, blue: 0.68)
    static let presence = Color(red: 0.55, green: 0.78, blue: 0.72)
    static let motion = Color(red: 0.78, green: 0.68, blue: 0.48)
    static let sand = Color(red: 0.85, green: 0.70, blue: 0.42)
    static let amber = Color(red: 0.93, green: 0.56, blue: 0.30)
    static let sleep = Color(red: 0.55, green: 0.62, blue: 0.88)
    static let hrv = Color(red: 0.62, green: 0.78, blue: 0.70)
    static let steps = Color(red: 0.72, green: 0.78, blue: 0.55)
    static let energy = Color(red: 0.90, green: 0.62, blue: 0.42)
    static let stand = Color(red: 0.48, green: 0.72, blue: 0.82)
}

private enum SignalsPane: String, CaseIterable, Identifiable {
    case live
    case recovery
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "Live"
        case .recovery: return "Recovery"
        case .activity: return "Activity"
        }
    }
}

// MARK: - Screen

/// Live Focus proxies + Health recovery/activity trends — one composition per pane.
struct SignalsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pane: SignalsPane = .live

    private var store: FocusSignalStore { model.signalStore }
    private var buffer: FocusSignalBuffer { store.buffer }
    private var history: HistoricalHeartRateStore { model.historicalHeartRate }
    private var trends: HealthTrendsStore { model.healthTrends }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SignalsChrome.canvasTop, SignalsChrome.canvasMid, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                panePicker
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                content
                    .id(pane)
                    .transition(reduceMotion ? .opacity : SynapseMotion.paneTransition)
            }
        }
        .animation(reduceMotion ? nil : SynapseMotion.page, value: pane)
        .preferredColorScheme(.dark)
        .task {
            await model.ensureHealthDataForSignals()
            if buffer.isEmpty && !store.hasSessionData {
                if trends.snapshot?.hasAnyData == true {
                    pane = .recovery
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .live:
            liveContent
        case .recovery:
            ScrollView {
                recoveryContent
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        case .activity:
            ScrollView {
                activityContent
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Signals")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(SignalsChrome.body)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(SignalsChrome.surface))
                    .overlay(Circle().strokeBorder(SignalsChrome.hairline, lineWidth: 1))
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel("Close")
        }
    }

    private var panePicker: some View {
        Picker("Signals pane", selection: $pane) {
            ForEach(SignalsPane.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .colorScheme(.dark)
    }

    private var subtitle: String {
        switch pane {
        case .live:
            if model.phoneSession.lastHeartRateBpm != nil { return "Live Watch heart rate" }
            if store.isLive { return "Live · this Focus block" }
            if store.hasSessionData { return "Last Focus block" }
            if history.snapshot?.isEmpty == false { return "Last 24h from Health" }
            return "Heart rate, pace, presence"
        case .recovery:
            return "Resting · sleep · HRV · pacing context"
        case .activity:
            return "Steps · energy · stand · today’s load"
        }
    }

    // MARK: - Live pane

    @ViewBuilder
    private var liveContent: some View {
        if buffer.isEmpty && !hasHistoricalContext && !hasLiveWatchHeartRate {
            emptyLiveState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    liveWatchHeartRateHero

                    if !buffer.isEmpty {
                        statusStrip
                        primaryChart
                        secondaryRow
                    } else if hasHistoricalContext {
                        historyOnlyIntro
                    }
                    historicalContextChart
                    honestyFooterLive
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var liveWatchHeartRateBpm: Double? {
        model.focusEngine.lastHrBpm ?? model.phoneSession.lastHeartRateBpm
    }

    private var hasLiveWatchHeartRate: Bool {
        liveWatchHeartRateBpm != nil || model.phoneSession.isReachable
    }

    @ViewBuilder
    private var liveWatchHeartRateHero: some View {
        if hasLiveWatchHeartRate {
            VStack(spacing: 12) {
                Text("WATCH")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(SignalsChrome.label)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HeartRatePulseIndicator(
                    bpm: liveWatchHeartRateBpm,
                    isMeasuring: liveWatchHeartRateBpm == nil && model.phoneSession.isReachable,
                    measuredAt: model.phoneSession.lastHeartRateReceivedAt,
                    size: .hero
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SignalsChrome.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(SignalsChrome.hairline, lineWidth: 1)
                        )
                )
                .animation(
                    .snappy(duration: 0.25),
                    value: liveWatchHeartRateBpm.map { Int($0.rounded()) }
                )
            }
        }
    }

    private var hasHistoricalContext: Bool {
        if let snapshot = history.snapshot, !snapshot.isEmpty { return true }
        return history.hasPromptedAuthorization || trends.hasPromptedAuthorization
    }

    private var emptyLiveState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No samples yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("Start a Focus block for live Watch heart rate, or allow Health for recovery and activity context. Missing channels stay empty — nothing is invented.")
                .font(.subheadline)
                .foregroundStyle(SignalsChrome.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !trends.hasPromptedAuthorization {
                Button {
                    Task { await model.ensureHealthDataForSignals() }
                } label: {
                    Text("Enable Health")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SignalsChrome.accent.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            } else {
                Button {
                    pane = .recovery
                } label: {
                    Text("See Recovery")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SignalsChrome.accent.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            if !model.focusEngine.isRunning {
                Button {
                    dismiss()
                    model.openFocus()
                } label: {
                    Text("Open Focus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(trends.hasPromptedAuthorization ? 1 : 0.85))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule(style: .continuous)
                                .fill(trends.hasPromptedAuthorization
                                      ? SignalsChrome.accent.opacity(0.9)
                                      : Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    private var historyOnlyIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(history.statusSummary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("Live Watch heart rate appears when Synapse is open on the Watch. Focus graphs fill during a block. Recovery and Activity use phone Health for pacing context.")
                .font(.caption)
                .foregroundStyle(SignalsChrome.body)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceCard)
    }

    // MARK: - Recovery pane

    private var recoveryContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if trends.isRefreshing && trends.snapshot == nil {
                channelEmpty("Loading recovery context from Health…")
            } else if !trends.hasPromptedAuthorization {
                deniedOrPromptState(
                    title: "Allow Health for recovery context",
                    body: "Synapse reads resting heart rate, sleep, and HRV (SDNN) already on your phone — as pacing context, not a diagnosis."
                )
            } else if !hasRecoveryData {
                channelEmpty("No resting heart rate, sleep, or HRV samples in Health for this window. Nothing is invented.")
            } else {
                sectionLabel("Recovery")
                recoveryStrip
                lastNightSleepDetail
                restingHRChart
                sleepChart
                hrvChart
            }
            honestyFooterRecovery
        }
    }

    private var hasRecoveryData: Bool {
        guard let snap = trends.snapshot else { return false }
        return !snap.restingHeartRate.isEmpty || !snap.sleep.isEmpty || !snap.hrvSDNN.isEmpty
    }

    private var recoveryStrip: some View {
        let snap = trends.snapshot
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                statChip(
                    title: "Resting",
                    value: snap?.restingHeartRate.latest.map { String(format: "%.0f", $0.value) } ?? "—",
                    unit: "bpm"
                )
                statChip(
                    title: "HRV",
                    value: snap?.hrvSDNN.latest.map { String(format: "%.0f", $0.value) } ?? "—",
                    unit: "ms"
                )
            }
            HStack(spacing: 10) {
                statChip(
                    title: "Asleep",
                    value: snap?.sleep.lastNight.map { String(format: "%.1f", $0.asleepHours) } ?? "—",
                    unit: "h"
                )
                statChip(
                    title: "Score",
                    value: snap?.sleep.lastNight.map { "\($0.score.value)" } ?? "—",
                    unit: snap?.sleep.lastNight?.score.band ?? ""
                )
            }
        }
    }

    @ViewBuilder
    private var lastNightSleepDetail: some View {
        if let night = trends.snapshot?.sleep.lastNight {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LAST NIGHT")
                            .font(.caption2.weight(.semibold))
                            .kerning(1.3)
                            .foregroundStyle(SignalsChrome.label)
                        Text("\(night.score.value)")
                            .font(.system(size: 56, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text("Sleep score · \(night.score.band)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SignalsChrome.sleep)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        sleepMetricLabel("Asleep", value: String(format: "%.1f h", night.asleepHours))
                        sleepMetricLabel("In bed", value: String(format: "%.1f h", night.inBedHours))
                        if let efficiency = night.efficiency {
                            sleepMetricLabel("Efficiency", value: String(format: "%.0f%%", efficiency * 100))
                        }
                    }
                }

                if night.hasStageBreakdown {
                    Text("Stages")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SignalsChrome.label)
                    sleepStageStack(night: night)
                    sleepStageLegend(night: night)
                } else {
                    Text("Stage breakdown needs Watch sleep tracking — showing total asleep only.")
                        .font(.caption)
                        .foregroundStyle(SignalsChrome.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TODAY’S CAPACITY")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.3)
                        .foregroundStyle(SignalsChrome.label)
                    Text(night.pacingHint.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(night.pacingHint.detail)
                        .font(.caption)
                        .foregroundStyle(SignalsChrome.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceCard)
        }
    }

    private func sleepMetricLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SignalsChrome.label)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private struct SleepStageSegment: Identifiable {
        let id: SleepStageKind
        let title: String
        let seconds: TimeInterval
        let color: Color
    }

    private func sleepStageStack(night: SleepNightSummary) -> some View {
        let segments = sleepStageSegments(for: night).filter { $0.seconds > 0 }
        let total = max(segments.reduce(0) { $0 + $1.seconds }, 1)
        return GeometryReader { geo in
            let gap: CGFloat = 2
            let gapTotal = gap * CGFloat(max(segments.count - 1, 0))
            let available = max(geo.size.width - gapTotal, 0)
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    let width = available * CGFloat(segment.seconds / total)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color)
                        .frame(width: width)
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sleepStageAccessibilityLabel(night: night))
    }

    private func sleepStageLegend(night: SleepNightSummary) -> some View {
        let rows = sleepStageSegments(for: night).filter { $0.seconds > 0 }
        return HStack(spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.caption2)
                            .foregroundStyle(SignalsChrome.label)
                        Text(formatSleepHours(row.seconds))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sleepStageAccessibilityLabel(night: SleepNightSummary) -> String {
        sleepStageSegments(for: night)
            .filter { $0.seconds > 0 }
            .map { "\($0.title) \(formatSleepHours($0.seconds))" }
            .joined(separator: ", ")
    }

    private func sleepStageSegments(for night: SleepNightSummary) -> [SleepStageSegment] {
        [
            SleepStageSegment(
                id: .deep,
                title: "Deep",
                seconds: night.deepSeconds,
                color: Color(red: 0.35, green: 0.42, blue: 0.92)
            ),
            SleepStageSegment(
                id: .core,
                title: "Core",
                seconds: night.coreSeconds,
                color: Color(red: 0.45, green: 0.58, blue: 0.95)
            ),
            SleepStageSegment(
                id: .rem,
                title: "REM",
                seconds: night.remSeconds,
                color: Color(red: 0.62, green: 0.55, blue: 0.95)
            ),
            SleepStageSegment(
                id: .awake,
                title: "Awake",
                seconds: night.awakeSeconds,
                color: Color(red: 0.85, green: 0.55, blue: 0.40)
            )
        ]
    }

    private func formatSleepHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        if hours < 0.05 { return "0h" }
        if hours < 1 {
            return String(format: "%.0fm", seconds / 60)
        }
        return String(format: "%.1fh", hours)
    }

    private var restingHRChart: some View {
        let daily = trends.snapshot?.restingHeartRate.daily ?? []
        return trendChartCard(
            title: "Resting heart rate",
            subtitle: "Daily · last \(trends.dayCount) days · settled pace context",
            empty: "No resting heart-rate samples yet.",
            points: daily,
            color: SignalsChrome.heart,
            valueFormat: { String(format: "%.0f", $0) }
        )
    }

    private var sleepChart: some View {
        let nights = trends.snapshot?.sleep.nights ?? []
        let points = nights.map {
            DailyQuantityPoint(dayStart: $0.wakeDayStart, value: $0.asleepHours)
        }
        return trendChartCard(
            title: "Sleep",
            subtitle: "Asleep hours · last nights from Health (Watch stages when available)",
            empty: "No asleep intervals in Health for recent nights.",
            points: points,
            color: SignalsChrome.sleep,
            valueFormat: { String(format: "%.1fh", $0) }
        )
    }

    private var hrvChart: some View {
        let trend = trends.snapshot?.hrvSDNN
        let daily = trend?.daily ?? []
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("HRV · SDNN")
            Text("Helps separate strain from a settled state — as context for pacing, not a diagnosis.")
                .font(.caption)
                .foregroundStyle(SignalsChrome.body)

            if daily.isEmpty {
                channelEmpty("HRV is sparse on many Watches. No SDNN samples in this window — nothing invented.")
                    .padding(14)
                    .background(surfaceCard)
            } else {
                if trend?.isSparse == true {
                    Text("Sparse samples — treat the trend lightly.")
                        .font(.caption2)
                        .foregroundStyle(SignalsChrome.label)
                }
                dailyLineChart(
                    points: daily,
                    color: SignalsChrome.hrv,
                    valueFormat: { String(format: "%.0f", $0) }
                )
                .padding(14)
                .background(surfaceCard)
            }
        }
    }

    // MARK: - Activity pane

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if trends.isRefreshing && trends.snapshot == nil {
                channelEmpty("Loading activity from Health…")
            } else if !trends.hasPromptedAuthorization {
                deniedOrPromptState(
                    title: "Allow Health for activity context",
                    body: "Synapse reads steps, active energy, and stand hours already on your phone — today’s load as pacing context."
                )
            } else if !(trends.snapshot.map { !$0.steps.isEmpty || !$0.activeEnergyKcal.isEmpty || !$0.standHours.isEmpty } ?? false) {
                channelEmpty("No steps, active energy, or stand samples in Health for this window.")
            } else {
                sectionLabel("Activity")
                activityStrip
                stepsChart
                energyChart
                standChart
            }
            honestyFooterActivity
        }
    }

    private var activityStrip: some View {
        let snap = trends.snapshot
        return HStack(spacing: 10) {
            statChip(
                title: "Steps",
                value: snap?.steps.latest.map { formatSteps($0.value) } ?? "—",
                unit: ""
            )
            statChip(
                title: "Energy",
                value: snap?.activeEnergyKcal.latest.map { String(format: "%.0f", $0.value) } ?? "—",
                unit: "kcal"
            )
            statChip(
                title: "Stand",
                value: snap?.standHours.latest.map { String(format: "%.0f", $0.value) } ?? "—",
                unit: "h"
            )
        }
    }

    private var stepsChart: some View {
        trendChartCard(
            title: "Steps",
            subtitle: "Daily totals · last \(trends.dayCount) days",
            empty: "No step samples yet.",
            points: trends.snapshot?.steps.daily ?? [],
            color: SignalsChrome.steps,
            valueFormat: { formatSteps($0) }
        )
    }

    private var energyChart: some View {
        trendChartCard(
            title: "Active energy",
            subtitle: "Kilocalories · last \(trends.dayCount) days",
            empty: "No active energy samples yet.",
            points: trends.snapshot?.activeEnergyKcal.daily ?? [],
            color: SignalsChrome.energy,
            valueFormat: { String(format: "%.0f", $0) }
        )
    }

    private var standChart: some View {
        trendChartCard(
            title: "Stand hours",
            subtitle: "Apple Stand Hours · last \(trends.dayCount) days",
            empty: "No stand-hour samples yet.",
            points: trends.snapshot?.standHours.daily ?? [],
            color: SignalsChrome.stand,
            valueFormat: { String(format: "%.0f", $0) }
        )
    }

    // MARK: - Shared trend UI

    private func deniedOrPromptState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(SignalsChrome.body)
            Button {
                Task { await model.ensureHealthDataForSignals() }
            } label: {
                Text("Enable Health")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(SignalsChrome.accent.opacity(0.9))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceCard)
    }

    private func statChip(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(1.1)
                .foregroundStyle(SignalsChrome.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(SignalsChrome.body)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceCard)
    }

    private func trendChartCard(
        title: String,
        subtitle: String,
        empty: String,
        points: [DailyQuantityPoint],
        color: Color,
        valueFormat: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(SignalsChrome.body)

            if points.isEmpty {
                channelEmpty(empty)
                    .padding(14)
                    .background(surfaceCard)
            } else {
                dailyLineChart(points: points, color: color, valueFormat: valueFormat)
                    .padding(14)
                    .background(surfaceCard)
                    .synapseChartReveal(replayKey: chartReplayKey(points: points, title: title))
            }
        }
    }

    private func dailyLineChart(
        points: [DailyQuantityPoint],
        color: Color,
        valueFormat: @escaping (Double) -> String
    ) -> some View {
        SynapseDailyLineChart(points: points, color: color, valueFormat: valueFormat)
    }

    private func chartReplayKey(points: [DailyQuantityPoint], title: String) -> String {
        let fingerprint = points
            .suffix(4)
            .map { "\($0.dayStart.timeIntervalSince1970)-\(Int($0.value * 100))" }
            .joined(separator: ".")
        return "\(title)-\(fingerprint)"
    }

    private var surfaceCard: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(SignalsChrome.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SignalsChrome.hairline, lineWidth: 1)
            )
    }

    // MARK: - Status strip (live)

    private var statusStrip: some View {
        let latest = buffer.latest
        let state = latest?.signalState ?? model.focusEngine.signalState
        return HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)
                    .opacity(state == .steady ? 0.55 : 1)
                Text(state.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(state.tint.opacity(state.labelOpacity))
            }

            Spacer()

            if store.isLive {
                HStack(spacing: 5) {
                    Circle()
                        .fill(SignalsChrome.accent)
                        .frame(width: 6, height: 6)
                    Text("Live")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(SignalsChrome.accent.opacity(0.9))
                }
            }

            if let bpm = latest?.heartRateBpm ?? model.focusEngine.lastHrBpm {
                Text(String(format: "%.0f bpm", bpm))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(SignalsChrome.heart.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(surfaceCard)
    }

    // MARK: - Primary chart (HR + pace stacked)

    private var primaryChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Heart rate · Pace signal")

            if !buffer.hasHeartRate && !buffer.hasPace {
                channelEmpty("Waiting for heart rate or a pace reading…")
            } else {
                VStack(spacing: 10) {
                    heartRateStackedSeries
                    stackedSeries(
                        title: "Pace signal",
                        unit: "0…1 drift",
                        series: buffer.paceSeries,
                        color: SignalsChrome.pace,
                        dashed: true,
                        yDomain: 0...1
                    )
                }

                if !buffer.events.isEmpty {
                    eventLegend
                }
            }
        }
    }

    private var heartRateStackedSeries: some View {
        let live = buffer.heartRateSeries
        let context = sessionHistoryOverlay
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Heart rate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(context.isEmpty ? "bpm · live" : "bpm · live + Health context")
                    .font(.caption2)
                    .foregroundStyle(SignalsChrome.label)
            }

            if live.isEmpty && context.isEmpty {
                channelEmpty("No heart rate samples yet")
                    .frame(height: 72)
            } else {
                Chart {
                    ForEach(Array(context.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("Health", point.value)
                        )
                        .foregroundStyle(SignalsChrome.heart.opacity(0.35))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    }

                    ForEach(Array(live.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.elapsed),
                            y: .value("Live", point.value)
                        )
                        .foregroundStyle(SignalsChrome.heart.opacity(0.14))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value("Live", point.value)
                        )
                        .foregroundStyle(SignalsChrome.heart)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.4))
                    }

                    ForEach(buffer.events) { event in
                        RuleMark(x: .value("Event", event.elapsedSeconds))
                            .foregroundStyle(eventColor(event.kind).opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(formatElapsed(seconds))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.0f", v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .chartYScale(domain: heartRateDomain)
                .chartXScale(domain: xDomain)
                .frame(height: 96)
            }
        }
        .padding(14)
        .background(surfaceCard)
        .synapseChartReveal(replayKey: "hr-live")
    }

    private var sessionHistoryOverlay: [(elapsed: TimeInterval, value: Double)] {
        let end: Date
        if store.isLive {
            end = Date()
        } else if let last = buffer.latest?.date {
            end = last
        } else {
            end = Date()
        }
        return history.sessionOverlaySeries(
            sessionStart: store.sessionStartedAt,
            sessionEnd: end
        )
    }

    // MARK: - 24h Health context (live pane)

    @ViewBuilder
    private var historicalContextChart: some View {
        let buckets = history.snapshot?.buckets ?? []
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Last 24 hours · Health")

            if history.isRefreshing && buckets.isEmpty {
                channelEmpty("Loading heart rate from Health…")
            } else if buckets.isEmpty {
                channelEmpty(
                    history.hasPromptedAuthorization
                        ? "No heart-rate samples in Health for the last day."
                        : "Allow Health to show recent heart rate trends for pacing context."
                )
            } else {
                HStack(spacing: 12) {
                    if let latest = history.snapshot?.latestBpm {
                        Text(String(format: "%.0f bpm latest", latest))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(SignalsChrome.heart.opacity(0.75))
                    }
                    if let overnight = history.snapshot?.overnightMinBpm {
                        Text(String(format: "Overnight low %.0f", overnight))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(SignalsChrome.body)
                    }
                    Spacer()
                }

                Chart {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                        LineMark(
                            x: .value("Time", bucket.date),
                            y: .value("HR", bucket.bpm)
                        )
                        .foregroundStyle(SignalsChrome.heart.opacity(0.55))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        AreaMark(
                            x: .value("Time", bucket.date),
                            y: .value("HR", bucket.bpm)
                        )
                        .foregroundStyle(SignalsChrome.heart.opacity(0.08))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour().minute())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let bpm = value.as(Double.self) {
                                Text(String(format: "%.0f", bpm))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .padding(.vertical, 4)
                .synapseChartReveal(replayKey: "hist24-\(buckets.count)")
            }
        }
    }

    private func stackedSeries(
        title: String,
        unit: String,
        series: [(elapsed: TimeInterval, value: Double)],
        color: Color,
        dashed: Bool,
        yDomain: ClosedRange<Double>?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(SignalsChrome.label)
            }

            if series.isEmpty {
                channelEmpty("No \(title.lowercased()) samples yet")
                    .frame(height: 72)
            } else {
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                        AreaMark(
                            x: .value("Time", point.elapsed),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(color.opacity(0.14))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", point.elapsed),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
                    }

                    ForEach(buffer.events) { event in
                        RuleMark(x: .value("Event", event.elapsedSeconds))
                            .foregroundStyle(eventColor(event.kind).opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(formatElapsed(seconds))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(formatAxis(v, unitHint: unit))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SignalsChrome.label)
                            }
                        }
                    }
                }
                .chartYScale(domain: yDomain ?? 0...1)
                .chartXScale(domain: xDomain)
                .frame(height: 96)
            }
        }
        .padding(14)
        .background(surfaceCard)
        .synapseChartReveal(replayKey: title)
    }

    private var eventLegend: some View {
        HStack(spacing: 14) {
            ForEach(buffer.events.prefix(4)) { event in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(eventColor(event.kind).opacity(0.8))
                        .frame(width: 10, height: 2)
                    Text("\(eventLabel(event.kind)) · \(formatElapsed(event.elapsedSeconds))")
                        .font(.caption2)
                        .foregroundStyle(SignalsChrome.body)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var xDomain: ClosedRange<Double> {
        let times = buffer.samples.map(\.elapsedSeconds)
        let lo = times.min() ?? 0
        let hi = max(lo + 1, times.max() ?? 1)
        return lo...hi
    }

    private var heartRateDomain: ClosedRange<Double> {
        let values = buffer.heartRateSeries.map(\.value) + sessionHistoryOverlay.map(\.value)
        guard let minV = values.min(), let maxV = values.max() else {
            return 50...100
        }
        let pad = max(4, (maxV - minV) * 0.15)
        return (minV - pad)...(maxV + pad)
    }

    private func formatAxis(_ value: Double, unitHint: String) -> String {
        if unitHint.contains("bpm") {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Secondary row

    private var secondaryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            secondaryChart(
                title: "Presence",
                subtitle: presenceSubtitle,
                series: buffer.presenceSeries,
                color: SignalsChrome.presence,
                empty: presenceEmptyCopy,
                // Raw ARKit eyeWide — usually ~0.0–0.15 on a calm face. Fixed 0…1
                // made every session look “broken low”; zoom to the live range.
                yDomain: presenceYDomain
            )
            secondaryChart(
                title: "Wrist motion",
                subtitle: motionSubtitle,
                series: buffer.motionSeries,
                color: SignalsChrome.motion,
                empty: motionEmptyCopy,
                yDomain: 0...1
            )
        }
    }

    private func secondaryChart(
        title: String,
        subtitle: String,
        series: [(elapsed: TimeInterval, value: Double)],
        color: Color,
        empty: String,
        yDomain: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(SignalsChrome.label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if series.isEmpty {
                channelEmpty(empty)
                    .frame(height: 88)
            } else {
                SynapseSparklineChart(
                    series: series,
                    color: color,
                    xDomain: xDomain,
                    yDomain: yDomain,
                    replayKey: title
                )
                .frame(height: 88)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surfaceCard)
        .synapseChartReveal(replayKey: title)
    }

    private var honestyFooterLive: some View {
        Text("Wellness proxies against your own baseline — not a diagnosis. Live heart rate comes from an active Watch workout; the quieter Health series is phone history for context. Pace signal is drift from that baseline. Presence plots raw eyelid openness (ARKit) when the camera is on — a calm face sits near zero; that is normal, not “absent.”")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.28))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var honestyFooterRecovery: some View {
        Text("Recovery numbers are Apple Health context for pacing — resting rate, sleep stages / score, and HRV (SDNN). The sleep score and today’s capacity note are transparent heuristics, not a diagnosis, and they do not drive the Focus break nudge.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.28))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var honestyFooterActivity: some View {
        Text("Activity is today’s load from Health — steps, active energy, stand hours — shown as pacing context only. Not a medical score.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.28))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(1.3)
            .foregroundStyle(SignalsChrome.label)
    }

    private func channelEmpty(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(SignalsChrome.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 28)
            .padding(.horizontal, 4)
    }

    private func formatSteps(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private var presenceSubtitle: String {
        guard buffer.hasPresence else { return "Camera off or no face" }
        if let latest = buffer.presenceSeries.last?.value {
            return String(format: "Eyelid openness · %.2f (calm ≈ 0)", latest)
        }
        return "Eyelid openness · camera on"
    }

    private var motionSubtitle: String {
        buffer.hasMotion ? "Higher = more fidget" : "Watch stillness off"
    }

    /// Zoom Presence to the session’s actual eyeWide range so a calm face isn’t a flat line on 0…1.
    private var presenceYDomain: ClosedRange<Double> {
        let values = buffer.presenceSeries.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...0.2 }
        let pad = max(0.02, (hi - lo) * 0.35)
        let lower = max(0, lo - pad)
        let upper = min(1, max(hi + pad, lower + 0.08))
        return lower...upper
    }

    private func axisMarks(for domain: ClosedRange<Double>) -> [Double] {
        let mid = (domain.lowerBound + domain.upperBound) / 2
        return [domain.lowerBound, mid, domain.upperBound]
    }

    private var presenceEmptyCopy: String {
        "No presence samples — camera asleep or Watch-only."
    }

    private var motionEmptyCopy: String {
        "No wrist motion yet — connect Watch during Focus."
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private func eventLabel(_ kind: FocusSignalEventKind) -> String {
        switch kind {
        case .baselineReady: return "Baseline"
        case .breakSuggested: return "Break"
        }
    }

    private func eventColor(_ kind: FocusSignalEventKind) -> Color {
        switch kind {
        case .baselineReady: return SignalsChrome.accent
        case .breakSuggested: return SignalsChrome.amber
        }
    }
}

// MARK: - Animated charts

/// Daily trend line that draws up on appear (web chart-stroke feel).
private struct SynapseDailyLineChart: View {
    let points: [DailyQuantityPoint]
    let color: Color
    let valueFormat: (Double) -> String

    @State private var drawProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var replayKey: String {
        points
            .suffix(3)
            .map { "\($0.dayStart.timeIntervalSince1970)-\(Int($0.value * 10))" }
            .joined(separator: ".")
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minV = values.min(), let maxV = values.max() else { return 0...1 }
        if minV == maxV {
            let pad = max(1, abs(minV) * 0.1)
            return (minV - pad)...(maxV + pad)
        }
        let pad = max(0.5, (maxV - minV) * 0.12)
        return (minV - pad)...(maxV + pad)
    }

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                let y = point.value * drawProgress
                AreaMark(
                    x: .value("Day", point.dayStart),
                    y: .value("Value", y)
                )
                .foregroundStyle(color.opacity(0.12 * drawProgress))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Day", point.dayStart),
                    y: .value("Value", y)
                )
                .foregroundStyle(color.opacity(0.85))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Day", point.dayStart),
                    y: .value("Value", y)
                )
                .foregroundStyle(color.opacity(drawProgress > 0.82 ? 1 : 0))
                .symbolSize(28)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(SignalsChrome.label)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(valueFormat(v))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(SignalsChrome.label)
                    }
                }
            }
        }
        .frame(height: 128)
        .synapseChartDraw(replayKey: replayKey, progress: $drawProgress)
    }
}

/// Compact presence / motion sparkline with draw-up.
private struct SynapseSparklineChart: View {
    let series: [(elapsed: TimeInterval, value: Double)]
    let color: Color
    let xDomain: ClosedRange<Double>
    let yDomain: ClosedRange<Double>
    var replayKey: String = "spark"

    @State private var drawProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var axisValues: [Double] {
        let span = yDomain.upperBound - yDomain.lowerBound
        guard span > 0 else { return [yDomain.lowerBound] }
        return [
            yDomain.lowerBound,
            yDomain.lowerBound + span * 0.5,
            yDomain.upperBound
        ]
    }

    var body: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                let baseline = yDomain.lowerBound
                let y = baseline + (point.value - baseline) * drawProgress
                AreaMark(
                    x: .value("Time", point.elapsed),
                    y: .value("Value", y)
                )
                .foregroundStyle(color.opacity(0.22 * drawProgress))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.elapsed),
                    y: .value("Value", y)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(values: axisValues) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .synapseChartDraw(replayKey: replayKey, progress: $drawProgress)
    }
}

// MARK: - Hub card

struct SignalsHubCard: View {
    @Bindable var model: AppModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signals")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(hubSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(SignalsChrome.accent.opacity(0.85))
                }

                if !contextChips.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(contextChips, id: \.self) { chip in
                            Text(chip)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(SignalsChrome.hairline, lineWidth: 1)
                                        )
                                )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(SignalsChrome.accent.opacity(0.35), lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel("Signals")
        .accessibilityHint("Open live, recovery, and activity charts")
        .task {
            // Soft refresh for Hub chips — no cold-launch auth prompt.
            if model.healthTrends.hasPromptedAuthorization {
                await model.refreshHealthTrends()
            }
        }
    }

    private var contextChips: [String] {
        model.healthTrends.hubContextChips
    }

    private var hubSubtitle: String {
        if model.signalStore.isLive {
            return "Live graphs · this Focus block"
        }
        if model.signalStore.hasSessionData {
            return "Last block · HR, pace, presence"
        }
        if model.healthTrends.hasPromptedAuthorization,
           model.healthTrends.snapshot?.hasAnyData == true {
            return "Recovery · \(model.healthTrends.statusSummary)"
        }
        if let bpm = model.historicalHeartRate.snapshot?.latestBpm {
            return String(format: "Health context · %.0f bpm latest", bpm)
        }
        if !model.historicalHeartRate.hasPromptedAuthorization {
            return "Enable Health for recovery & activity trends"
        }
        return "Live · Recovery · Activity"
    }
}
