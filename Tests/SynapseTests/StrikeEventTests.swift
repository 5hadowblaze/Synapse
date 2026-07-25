import XCTest
@testable import Synapse

final class StrikeEventTests: XCTestCase {
    func testRoundTripWithOctant() {
        let event = StrikeEvent(
            watchTimestamp: 12.34,
            peakG: 4.2,
            phoneTimestamp: 56.78,
            detectedOctant: 3
        )
        let message = event.asMessage()
        XCTAssertEqual(message[WCMessageKey.type] as? String, WCMessageKey.strike)
        let decoded = StrikeEvent.from(message: message)
        XCTAssertEqual(decoded, event)
    }

    func testRoundTripWithoutOctant() {
        let event = StrikeEvent(
            watchTimestamp: 1,
            peakG: 3.5,
            phoneTimestamp: 2,
            detectedOctant: nil
        )
        XCTAssertEqual(StrikeEvent.from(message: event.asMessage()), event)
    }

    func testRejectsWrongType() {
        let message: [String: Any] = [
            WCMessageKey.type: WCMessageKey.liveDirection,
            WCMessageKey.watchTimestamp: 1.0,
            WCMessageKey.peakG: 4.0,
            WCMessageKey.phoneTimestamp: 2.0
        ]
        XCTAssertNil(StrikeEvent.from(message: message))
    }

    func testAcceptsIntNumericBridging() {
        let message: [String: Any] = [
            WCMessageKey.type: WCMessageKey.strike,
            WCMessageKey.watchTimestamp: 1,
            WCMessageKey.peakG: 4,
            WCMessageKey.phoneTimestamp: 2,
            WCMessageKey.detectedOctant: 5
        ]
        let decoded = StrikeEvent.from(message: message)
        XCTAssertEqual(decoded?.peakG, 4)
        XCTAssertEqual(decoded?.detectedOctant, 5)
    }
}
