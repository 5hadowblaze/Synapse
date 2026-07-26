import SwiftUI

/// Apple Heart Rate–style live BPM: red heart pulsing to the beat, large digit, BPM caption.
/// Shared by Focus live (iPhone), Signals Live, and the Watch status UI.
struct HeartRatePulseIndicator: View {
    /// Latest BPM from Watch workout stream. Nil = measuring / disconnected.
    let bpm: Double?
    /// Watch reachable or workout active but no sample yet.
    var isMeasuring: Bool = false
    /// When the last sample arrived — drives “Measured X sec ago”.
    var measuredAt: Date? = nil
    /// `hero` = Watch / Signals full face; `card` = Focus live row; `compact` = tight chip.
    var size: Size = .card

    enum Size {
        case hero
        case card
        case compact
    }

    private var heartRed: Color {
        Color(red: 1.0, green: 0.23, blue: 0.19)
    }

    private var displayBpm: Int? {
        guard let bpm, bpm > 0, bpm.isFinite else { return nil }
        return Int(bpm.rounded())
    }

    /// Seconds per beat; falls back to a calm ~72 bpm measuring tick.
    private var beatSeconds: Double {
        if let bpm, bpm > 30, bpm < 220 {
            return 60.0 / bpm
        }
        return 60.0 / 72.0
    }

    var body: some View {
        Group {
            switch size {
            case .hero: heroBody
            case .card: cardBody
            case .compact: compactBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Layouts

    private var heroBody: some View {
        VStack(spacing: 10) {
            pulsingHeart(pointSize: 44)
            bpmBlock(numberSize: 52, captionSize: 13)
            measuredAgeLine(fontSize: 12)
        }
    }

    private var cardBody: some View {
        HStack(spacing: 14) {
            ZStack {
                if displayBpm != nil || isMeasuring {
                    rippleRing(maxDiameter: 56)
                }
                pulsingHeart(pointSize: 28)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                bpmBlock(numberSize: 36, captionSize: 11)
                measuredAgeLine(fontSize: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var compactBody: some View {
        HStack(spacing: 6) {
            pulsingHeart(pointSize: 12)
            if let displayBpm {
                Text("\(displayBpm)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(heartRed.opacity(0.95))
            } else {
                Text(isMeasuring ? "—" : "HR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private func bpmBlock(numberSize: CGFloat, captionSize: CGFloat) -> some View {
        VStack(alignment: size == .hero ? .center : .leading, spacing: 2) {
            if let displayBpm {
                Text("\(displayBpm)")
                    .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } else if isMeasuring {
                Text("—")
                    .font(.system(size: numberSize, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text("—")
                    .font(.system(size: numberSize, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.22))
            }

            Text(isMeasuring && displayBpm == nil ? "Measuring…" : "BPM")
                .font(.system(size: captionSize, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(heartRed.opacity(displayBpm == nil ? 0.45 : 0.85))
        }
    }

    @ViewBuilder
    private func measuredAgeLine(fontSize: CGFloat) -> some View {
        if displayBpm != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(measuredAgeCopy(at: context.date))
                    .font(.system(size: fontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .multilineTextAlignment(size == .hero ? .center : .leading)
            }
        }
    }

    private func measuredAgeCopy(at now: Date) -> String {
        guard let measuredAt else { return "Measured just now" }
        let seconds = max(0, Int(now.timeIntervalSince(measuredAt).rounded()))
        if seconds < 2 {
            return "Measured just now"
        }
        if seconds < 60 {
            return "Measured \(seconds) sec ago"
        }
        let minutes = seconds / 60
        if minutes == 1 {
            return "Measured 1 min ago"
        }
        return "Measured \(minutes) min ago"
    }

    // MARK: - Heart + ripple (beat-synced)

    private func pulsingHeart(pointSize: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let scale = heartScale(at: context.date)
            Image(systemName: "heart.fill")
                .font(.system(size: pointSize, weight: .regular))
                .foregroundStyle(heartRed.opacity(displayBpm == nil && !isMeasuring ? 0.25 : 1))
                .shadow(color: heartRed.opacity(displayBpm == nil ? 0 : 0.45), radius: pointSize * 0.35, y: 0)
                .scaleEffect(scale)
        }
    }

    private func rippleRing(maxDiameter: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = beatPhase(at: context.date)
            let expand = phase
            let opacity = max(0, 0.35 * (1 - phase))
            Circle()
                .stroke(heartRed.opacity(opacity), lineWidth: 2)
                .frame(
                    width: maxDiameter * (0.55 + 0.55 * expand),
                    height: maxDiameter * (0.55 + 0.55 * expand)
                )
        }
    }

    private func beatPhase(at date: Date) -> Double {
        let period = max(0.35, beatSeconds)
        let t = date.timeIntervalSinceReferenceDate
        return (t.truncatingRemainder(dividingBy: period)) / period
    }

    private func heartScale(at date: Date) -> CGFloat {
        guard displayBpm != nil || isMeasuring else { return 1 }
        let p = beatPhase(at: date)
        let primary = pulseEnvelope(p, start: 0.0, width: 0.16, peak: 1.22)
        let secondary = pulseEnvelope(p, start: 0.22, width: 0.12, peak: 1.12)
        return CGFloat(max(primary, secondary))
    }

    private func pulseEnvelope(_ phase: Double, start: Double, width: Double, peak: Double) -> Double {
        guard phase >= start, phase <= start + width else { return 1 }
        let local = (phase - start) / width
        let shaped = sin(local * .pi)
        return 1 + (peak - 1) * shaped
    }

    private var accessibilityLabel: String {
        if let displayBpm {
            return "Heart rate \(displayBpm) beats per minute. \(measuredAgeCopy(at: Date()))"
        }
        if isMeasuring {
            return "Measuring heart rate"
        }
        return "Heart rate unavailable"
    }
}
