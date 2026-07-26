import SwiftUI

/// Narrative indicator cards for Focus recap — plain language, indicator framing.
struct FocusPacingNarrativeSection: View {
    let narrative: FocusPacingNarrative

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PACING INDICATORS")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.38))
                Text(FocusPacingNarrative.disclaimer)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(narrative.cards) { card in
                FocusPacingNarrativeCardView(card: card)
            }
        }
    }
}

private struct FocusPacingNarrativeCardView: View {
    let card: FocusPacingNarrative.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(1.4)
                .foregroundStyle(.white.opacity(0.35))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(card.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if let highlight = card.highlight {
                    Text(highlight)
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Text(card.body)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            if let footnote = card.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
    }

    private var titleColor: Color {
        switch card.tone {
        case .steady:
            return Color(red: 0.35, green: 0.72, blue: 0.68)
        case .easing:
            return Color(red: 0.85, green: 0.70, blue: 0.42)
        case .breakSuggested:
            return Color(red: 0.93, green: 0.56, blue: 0.30)
        case .neutral:
            return .white
        }
    }

    private var borderColor: Color {
        switch card.tone {
        case .steady:
            return Color(red: 0.35, green: 0.72, blue: 0.68).opacity(0.28)
        case .easing:
            return Color(red: 0.85, green: 0.70, blue: 0.42).opacity(0.30)
        case .breakSuggested:
            return Color(red: 0.93, green: 0.56, blue: 0.30).opacity(0.32)
        case .neutral:
            return Color.white.opacity(0.10)
        }
    }
}
