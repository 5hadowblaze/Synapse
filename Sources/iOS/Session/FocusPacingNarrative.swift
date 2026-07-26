import Foundation

/// Plain-language pacing indicators for Focus recap.
/// Inferred from the block + optional reaction check — never a diagnosis or productivity score.
struct FocusPacingNarrative: Equatable, Sendable {
    struct Card: Equatable, Identifiable, Sendable {
        enum Tone: String, Sendable {
            case steady
            case easing
            case breakSuggested
            case neutral
        }

        let id: String
        let eyebrow: String
        let title: String
        let body: String
        let footnote: String?
        let highlight: String?
        let tone: Tone
    }

    static let disclaimer =
        "Indicators inferred from your baseline and optional reaction check — a pacing nudge, not a diagnosis or a productivity score."

    let cards: [Card]

    static func build(
        recap: FocusRecap?,
        comparison: TapPVTComparison?
    ) -> FocusPacingNarrative {
        var cards: [Card] = []
        if let recap {
            cards.append(blockCard(recap))
            cards.append(wellnessCard(recap))
        }
        if let comparison {
            cards.append(reactionCard(comparison))
        }
        return FocusPacingNarrative(cards: cards)
    }

    // MARK: - Cards

    private static func blockCard(_ recap: FocusRecap) -> Card {
        var body = "You spent \(recap.focusedMinutesLabel) focusing"
        if recap.breakSeconds > 0 {
            let brk = formatSeconds(recap.breakSeconds)
            body += " and \(brk) on break"
        }
        body += "."
        if recap.extendedOnce {
            body += " You locked in once after a suggestion — that override is always allowed."
        }

        return Card(
            id: "block",
            eyebrow: "Block summary",
            title: recap.focusedMinutesLabel,
            body: body,
            footnote: nil,
            highlight: nil,
            tone: .neutral
        )
    }

    private static func wellnessCard(_ recap: FocusRecap) -> Card {
        let title: String
        var body: String
        let tone: Card.Tone
        let highlight: String

        if !recap.baselineReady {
            title = "Baseline still building"
            tone = .neutral
            highlight = "—"
            body =
                "The wellness signal was still learning your baseline for this block, so any nudge would be less confident."
        } else if recap.fadeCount <= 0 {
            title = "Signals held near baseline"
            tone = .steady
            highlight = "0 nudges"
            body =
                "No break suggestion fired. Inferred indicator: proxies stayed close to your opening baseline."
        } else if recap.fadeCount == 1 {
            title = "One early pause suggested"
            tone = .easing
            highlight = "1× nudge"
            body =
                "The wellness signal suggested a break once. Inferred indicator: drift from your own baseline held long enough to nudge — not a claim that you failed the block."
        } else {
            title = "Several pause indicators"
            tone = .breakSuggested
            highlight = "\(recap.fadeCount)× nudges"
            body =
                "The wellness signal suggested a break \(recap.fadeCount) times. Inferred indicator: repeated drift vs baseline. Synapse nudges early on purpose — a short pause costs less than overrunning."
        }

        if let hr = recap.meanHrBpm {
            body += String(format: " Mean heart rate was about %.0f bpm.", hr)
        }

        return Card(
            id: "wellness",
            eyebrow: "Wellness signal",
            title: title,
            body: body,
            footnote:
                "Built from heart-rate trend vs your in-session baseline, plus wrist motion and camera presence when those channels are live.",
            highlight: highlight,
            tone: tone
        )
    }

    private static func reactionCard(_ comparison: TapPVTComparison) -> Card {
        let pre = comparison.pre.medianLabel
        let post = comparison.post.medianLabel
        let highlight = "\(pre) → \(post) ms"

        let title: String
        var body: String
        let tone: Card.Tone

        if comparison.medianDeltaMs == nil {
            title = "Reaction check incomplete"
            tone = .neutral
            body =
                "Not enough clean taps on both sides to compare. Treat this as incomplete, not as a fast result."
        } else {
            switch comparison.direction {
            case .slower:
                title = "Reaction slowed"
                tone = .breakSuggested
                body =
                    "\(comparison.headline) That is an indicator alertness may have drifted — useful to check against the break nudge, not a medical finding."
            case .faster:
                title = "Reaction held or improved"
                tone = .steady
                body =
                    "\(comparison.headline) An indicator this block did not cost vigilance in this sample — still not a diagnosis."
            case .steady:
                title = "Reaction held steady"
                tone = .steady
                body =
                    "\(comparison.headline) An indicator vigilance held through this block."
            }
        }

        body +=
            " Lapses (slower than 355 ms): \(comparison.pre.lapseCount) → \(comparison.post.lapseCount)."

        return Card(
            id: "reaction",
            eyebrow: "Reaction check · PVT-B",
            title: title,
            body: body,
            footnote:
                "PVT-B means Psychomotor Vigilance Test, brief form — a published 60-second tap test from sleep and aviation research. Synapse runs it before and after a block so you see a measured change, not a vibe.",
            highlight: highlight,
            tone: tone
        )
    }

    private static func formatSeconds(_ t: TimeInterval) -> String {
        let s = Int(t)
        let m = s / 60
        let r = s % 60
        if m > 0 { return "\(m)m \(r)s" }
        return "\(r)s"
    }
}
