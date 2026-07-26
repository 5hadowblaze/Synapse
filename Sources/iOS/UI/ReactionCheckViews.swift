import SwiftUI

// MARK: - Palette

/// Reaction check keeps the Focus palette: teal for good, sand for drift, amber for cost.
enum ReactionPalette {
    static let good = Color.teal
    static let drift = Color(red: 0.85, green: 0.70, blue: 0.42)
    static let cost = Color(red: 0.93, green: 0.56, blue: 0.30)

    static func tint(for direction: TapPVTComparison.Direction) -> Color {
        switch direction {
        case .faster: return good
        case .steady: return good
        case .slower: return cost
        }
    }
}

// MARK: - Setup toggle

/// Opt-in bookend control on the Focus setup screen.
struct ReactionCheckBookendToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reaction check")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("60-second tap test before and after. Measures the slowdown instead of inferring it.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                ReactionToggleMark(isOn: isOn)
                    .padding(.top, 2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color.teal.opacity(0.14) : Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isOn ? Color.teal.opacity(0.5) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityLabel("Reaction check bookend")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct ReactionToggleMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? Color.teal : Color.white.opacity(0.25), lineWidth: 1.5)
                .frame(width: 22, height: 22)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.teal)
            }
        }
    }
}

// MARK: - Live test

/// The stage-proof path: neutral field, one stimulus, one tap. No camera, no Watch, no network.
struct ReactionCheckView: View {
    @Bindable var model: AppModel

    /// Guards against a single press being counted twice while the finger moves.
    @State private var isPressing = false

    private var engine: TapPVTEngine { model.tapPVTEngine }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.04).ignoresSafeArea()

            // Whole screen is the response target. A zero-distance drag fires on touch
            // *down*; a tap gesture would only land on release and inflate every RT.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !isPressing else { return }
                            isPressing = true
                            model.registerReactionTap()
                        }
                        .onEnded { _ in isPressing = false }
                )

            VStack(spacing: 0) {
                header
                Spacer()
                stimulusField
                Spacer()
                footer
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button { model.cancelReactionCheck() } label: {
                        Label("Skip", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                Spacer()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: engine.stimulusVisible) { _, isVisible in
            isVisible
        }
        .persistentSystemOverlays(.hidden)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(engine.stage.title.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(1.6)
                .foregroundStyle(.white.opacity(0.35))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.teal.opacity(0.55))
                        .frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 2)
            .frame(maxWidth: 180)
            .animation(.linear(duration: 0.12), value: engine.progress)

            // Time only. A running tap count at PVT-B cadence turns this into a score.
            Text("\(Int(engine.remainingSeconds.rounded()))s")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.28))
        }
        .padding(.top, 64)
    }

    /// Resting ring → filled disc. The only thing that moves on this screen.
    private var stimulusField: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1.5)
                .frame(width: 190, height: 190)

            Circle()
                .fill(ReactionPalette.good)
                .frame(width: 190, height: 190)
                .shadow(color: ReactionPalette.good.opacity(0.28), radius: 24)
                .opacity(engine.stimulusVisible ? 1 : 0)

            feedbackLabel
        }
        .animation(.easeOut(duration: 0.06), value: engine.stimulusVisible)
        .animation(.easeInOut(duration: 0.22), value: engine.feedback)
    }

    @ViewBuilder
    private var feedbackLabel: some View {
        switch engine.feedback {
        case .reaction(let ms):
            reactionText("\(Int(ms.rounded()))", unit: "ms", tint: .white)
        case .lapse(let ms):
            // Tinted, not labelled. Calling out ~20 individual lapses mid-run would
            // scold someone who is already tired; the count belongs in the recap.
            reactionText("\(Int(ms.rounded()))", unit: "ms", tint: ReactionPalette.drift)
        case .falseStart:
            calmNote("Too early")
        case .missed:
            calmNote("Missed")
        case .none:
            EmptyView()
        }
    }

    private func reactionText(_ value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 36, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.82))
            Text(unit)
                .font(.caption2)
                .foregroundStyle(tint.opacity(0.42))
        }
        .transition(.opacity)
    }

    private func calmNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .foregroundStyle(ReactionPalette.drift.opacity(0.8))
            .transition(.opacity)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Tap anywhere the moment the circle appears.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
            Text("Brief psychomotor vigilance task · 60 seconds")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.25))
        }
        .multilineTextAlignment(.center)
        .padding(.bottom, 56)
    }
}

// MARK: - Result card

/// The recap moment: 280 → 340, in numbers you can read from across a room.
struct ReactionDeltaCard: View {
    let comparison: TapPVTComparison
    var showsFootnote = true

    @State private var revealed = false

    private var tint: Color { ReactionPalette.tint(for: comparison.direction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("REACTION CHECK")
                .font(.caption2.weight(.semibold))
                .kerning(1.8)
                .foregroundStyle(.white.opacity(0.35))

            // One unit at the end: "282 → 348 ms" keeps both numbers on one line.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                bigNumber(comparison.pre.medianLabel, tint: .white.opacity(0.5))

                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))

                bigNumber(comparison.post.medianLabel, tint: tint)

                Text("ms")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(tint.opacity(0.5))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 6)

            Text(comparison.headline)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(revealed ? 1 : 0)

            HStack(spacing: 10) {
                statCell(
                    title: "Lapses",
                    value: "\(comparison.pre.lapseCount) → \(comparison.post.lapseCount)",
                    tint: comparison.lapseDelta > 0 ? ReactionPalette.cost : .white
                )
                statCell(
                    title: "Change",
                    value: percentLabel,
                    tint: comparison.direction == .slower ? tint : .white
                )
            }
            .opacity(revealed ? 1 : 0)

            if showsFootnote {
                Text("Median of \(comparison.post.validCount) taps. Lapses are responses slower than 355 ms — the PVT-B threshold from sleep and aviation medicine, set so a brief test stays comparable to the 10-minute standard.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.15)) { revealed = true }
        }
    }

    private var percentLabel: String {
        guard let pct = comparison.percentChange else { return "—" }
        let sign = pct > 0 ? "+" : ""
        return "\(sign)\(Int(pct.rounded()))%"
    }

    private func bigNumber(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.system(size: 58, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
    }

    private func statCell(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

/// Single-result summary — used after a standalone check with nothing to compare against.
struct ReactionResultCard: View {
    let result: TapPVTResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REACTION CHECK")
                .font(.caption2.weight(.semibold))
                .kerning(1.8)
                .foregroundStyle(.white.opacity(0.35))

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(result.medianLabel)
                    .font(.system(size: 62, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("ms")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text("Median across \(result.validCount) taps · \(result.lapseCount) \(result.lapseCount == 1 ? "lapse" : "lapses")")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.teal.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

#Preview("Reaction delta") {
    let pre = TapPVTResult(
        stage: .pre,
        startedAt: Date(),
        durationSeconds: 60,
        trials: [275, 280, 268, 291, 284, 302].enumerated().map {
            TapPVTTrial(index: $0.offset, isiMs: 4000, reactionMs: $0.element)
        }
    )
    let post = TapPVTResult(
        stage: .post,
        startedAt: Date(),
        durationSeconds: 60,
        trials: [318, 340, 355, 612, 329, 588].enumerated().map {
            TapPVTTrial(index: $0.offset, isiMs: 4000, reactionMs: $0.element)
        }
    )
    return ZStack {
        Color.black.ignoresSafeArea()
        ReactionDeltaCard(comparison: TapPVTComparison(pre: pre, post: post))
            .padding(24)
    }
    .preferredColorScheme(.dark)
}
