import XCTest
@testable import Synapse

@MainActor
final class FocusEngineTests: XCTestCase {
    func testStartSessionEntersFocusing() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.phase, .focusing)
        XCTAssertEqual(engine.focusMinutes, 2)
        XCTAssertEqual(engine.breakMinutes, 1)
        XCTAssertGreaterThan(engine.remainingSeconds, 100)
        engine.stopSession(emitComplete: false)
    }

    func testExtendFocusOnce() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        let before = engine.remainingSeconds
        XCTAssertTrue(engine.extendFocus(byMinutes: 5))
        XCTAssertEqual(engine.remainingSeconds, before + 300, accuracy: 1)
        XCTAssertTrue(engine.didExtend)
        XCTAssertFalse(engine.extendFocus(byMinutes: 5))
        engine.stopSession(emitComplete: false)
    }

    func testStartBreakTransitionsPhase() {
        let engine = FocusEngine()
        var broke = false
        engine.onBreakStarted = { broke = true }
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        engine.startBreak()
        XCTAssertEqual(engine.phase, .onBreak)
        XCTAssertTrue(broke)
        XCTAssertEqual(engine.remainingSeconds, 60, accuracy: 1)
        engine.stopSession(emitComplete: false)
    }

    func testSkipBreakCompletes() {
        let engine = FocusEngine()
        var recap: FocusRecap?
        engine.onComplete = { recap = $0 }
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        engine.startBreak()
        engine.skipBreak()
        XCTAssertEqual(engine.phase, .complete)
        XCTAssertNotNil(recap)
    }

    func testPauseAndResume() {
        let engine = FocusEngine()
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        engine.pause()
        XCTAssertTrue(engine.isPaused)
        engine.resume()
        XCTAssertFalse(engine.isPaused)
        engine.stopSession(emitComplete: false)
    }

    func testFadeSuggestionCallback() {
        let engine = FocusEngine()
        var suggested = false
        engine.onFadeSuggested = { suggested = true }
        engine.startSession(focusMinutes: 2, breakMinutes: 1)
        engine.noteFadeSuggested()
        XCTAssertTrue(suggested)
        XCTAssertEqual(engine.phase, .breakSuggested)
        engine.dismissFadeSuggestion()
        XCTAssertEqual(engine.phase, .focusing)
        engine.stopSession(emitComplete: false)
    }
}
