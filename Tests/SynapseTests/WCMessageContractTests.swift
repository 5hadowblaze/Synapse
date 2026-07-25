import XCTest
@testable import Synapse

final class WCMessageContractTests: XCTestCase {
    func testSyncQualityContractFrozen() {
        XCTAssertEqual(WCMessageKey.syncQuality, "syncQuality")
        XCTAssertEqual(WCMessageKey.offsetMs, "offsetMs")
        XCTAssertEqual(WCMessageKey.rttMs, "rttMs")
        let payload = WatchOutboundMessage.syncQuality(offsetMs: 12.5, rttMs: 40)
        XCTAssertEqual(payload[WCMessageKey.type] as? String, "syncQuality")
        XCTAssertEqual(payload[WCMessageKey.offsetMs] as? Double, 12.5)
        XCTAssertEqual(payload[WCMessageKey.rttMs] as? Double, 40)
    }

    func testCalibrateStartParsesDuration() {
        let message: [String: Any] = [
            WCMessageKey.type: WCMessageKey.calibrateStart,
            WCMessageKey.duration: 8.0
        ]
        XCTAssertEqual(
            WatchInboundCommand.parse(message),
            .calibrateStart(durationSeconds: 8)
        )
    }

    func testCalibrateStartDefaultsDuration() {
        let message: [String: Any] = [WCMessageKey.type: WCMessageKey.calibrateStart]
        XCTAssertEqual(
            WatchInboundCommand.parse(message),
            .calibrateStart(durationSeconds: 10)
        )
    }

    func testInboundCommandSet() {
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.breakPointHaptic]),
            .breakPointHaptic
        )
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.liveDirectionStart]),
            .liveDirectionStart
        )
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.liveDirectionStop]),
            .liveDirectionStop
        )
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.motionEnergyStart]),
            .motionEnergyStart
        )
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.motionEnergyStop]),
            .motionEnergyStop
        )
        XCTAssertEqual(
            WatchInboundCommand.parse([WCMessageKey.type: WCMessageKey.calibrateStop]),
            .calibrateStop
        )
        XCTAssertNil(WatchInboundCommand.parse([WCMessageKey.type: "unknown"]))
    }

    func testCalibrateResultPayload() {
        let payload = WatchOutboundMessage.calibrateResult(success: true)
        XCTAssertEqual(payload[WCMessageKey.type] as? String, WCMessageKey.calibrateResult)
        XCTAssertEqual(payload[WCMessageKey.success] as? Bool, true)
    }
}
