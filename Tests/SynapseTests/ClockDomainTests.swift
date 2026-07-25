import XCTest
@testable import Synapse

final class ClockDomainTests: XCTestCase {
    func testCristianOffsetAndRtt() {
        let t1 = WatchTime(seconds: 100)
        let t2 = PhoneTime(seconds: 200.010)
        let t3 = PhoneTime(seconds: 200.012)
        let t4 = WatchTime(seconds: 100.020)
        let sample = ClockSyncSample.cristian(t1: t1, t2: t2, t3: t3, t4: t4)
        // offset = ((200.010-100) + (200.012-100.020)) / 2 = (100.010 + 99.992) / 2 = 100.001
        XCTAssertEqual(sample.offsetSeconds, 100.001, accuracy: 1e-9)
        // rtt = (100.020-100) - (200.012-200.010) = 0.020 - 0.002 = 0.018
        XCTAssertEqual(sample.rttSeconds, 0.018, accuracy: 1e-9)
        XCTAssertEqual(sample.offsetMs, 100_001, accuracy: 1e-6)
        XCTAssertEqual(sample.rttMs, 18, accuracy: 1e-6)
    }

    func testCristianClampsNegativeRtt() {
        let sample = ClockSyncSample.cristian(
            t1: WatchTime(seconds: 10),
            t2: PhoneTime(seconds: 20),
            t3: PhoneTime(seconds: 25),
            t4: WatchTime(seconds: 11)
        )
        // rtt = 1 - 5 = -4 → clamped to 0
        XCTAssertEqual(sample.rttSeconds, 0, accuracy: 1e-12)
    }

    func testWatchTimeToPhoneTime() {
        let watch = WatchTime(seconds: 50)
        let phone = watch.toPhoneTime(offsetSeconds: 1.5)
        XCTAssertEqual(phone.seconds, 51.5, accuracy: 1e-12)
    }
}
