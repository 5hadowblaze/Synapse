import XCTest
@testable import Synapse

final class FocusPacingNarrativeTests: XCTestCase {
    func testWellnessCardInfersPauseFromFadeCount() {
        let recap = FocusRecap(
            focusedSeconds: 300,
            breakSeconds: 60,
            fadeCount: 2,
            meanHrBpm: 78,
            baselineReady: true,
            extendedOnce: false
        )
        let narrative = FocusPacingNarrative.build(recap: recap, comparison: nil)
        XCTAssertEqual(narrative.cards.count, 2)
        let wellness = narrative.cards.first { $0.id == "wellness" }
        XCTAssertEqual(wellness?.tone, .breakSuggested)
        XCTAssertTrue(wellness?.body.contains("Inferred indicator") == true)
        XCTAssertFalse(wellness?.body.lowercased().contains("fatigue") == true)
        XCTAssertFalse(wellness?.body.lowercased().contains("productivity") == true)
    }

    func testReactionCardExplainsPVTInFootnote() {
        let pre = TapPVTResult(
            stage: .pre,
            startedAt: Date(),
            durationSeconds: 60,
            trials: (0..<5).map { TapPVTTrial(index: $0, isiMs: 2000, reactionMs: 280) }
        )
        let post = TapPVTResult(
            stage: .post,
            startedAt: Date(),
            durationSeconds: 60,
            trials: (0..<5).map { TapPVTTrial(index: $0, isiMs: 2000, reactionMs: 340) }
        )
        let comparison = TapPVTComparison(pre: pre, post: post)
        let narrative = FocusPacingNarrative.build(
            recap: FocusRecap(
                focusedSeconds: 120,
                breakSeconds: 30,
                fadeCount: 1,
                meanHrBpm: 72,
                baselineReady: true,
                extendedOnce: false
            ),
            comparison: comparison
        )
        let reaction = narrative.cards.first { $0.id == "reaction" }
        XCTAssertEqual(reaction?.tone, .breakSuggested)
        XCTAssertTrue(reaction?.footnote?.contains("Psychomotor Vigilance") == true)
        XCTAssertTrue(reaction?.eyebrow.contains("PVT-B") == true)
        XCTAssertTrue(reaction?.highlight?.contains("→") == true)
    }

    func testDisclaimerIsIndicatorFramed() {
        XCTAssertTrue(FocusPacingNarrative.disclaimer.contains("Indicators"))
        XCTAssertTrue(FocusPacingNarrative.disclaimer.contains("not a diagnosis"))
        XCTAssertTrue(FocusPacingNarrative.disclaimer.contains("productivity score"))
    }
}
