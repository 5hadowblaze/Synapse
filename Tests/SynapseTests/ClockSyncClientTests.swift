import XCTest
@testable import Synapse

@MainActor
final class ClockSyncClientTests: XCTestCase {
    final class MockRoundTrip: ClockSyncRoundTripPerforming {
        var samples: [ClockSyncSample?] = []
        private var index = 0

        func performSyncRoundTrip() async -> ClockSyncSample? {
            defer { index += 1 }
            guard index < samples.count else { return nil }
            return samples[index]
        }
    }

    func testBurstKeepsLowestRTT() async {
        let mock = MockRoundTrip()
        mock.samples = [
            ClockSyncSample(offsetSeconds: 1.0, rttSeconds: 0.050),
            ClockSyncSample(offsetSeconds: 1.1, rttSeconds: 0.020),
            ClockSyncSample(offsetSeconds: 0.9, rttSeconds: 0.080)
        ]
        let client = ClockSyncClient()
        client.burstSampleCount = 3
        client.interSampleDelayNanoseconds = 0
        client.attach(roundTrip: mock)
        let best = await client.runBurst()
        XCTAssertEqual(best?.rttSeconds, 0.020, accuracy: 1e-12)
        XCTAssertEqual(client.offsetSeconds, 1.1, accuracy: 1e-12)
        XCTAssertEqual(client.bestRttSeconds, 0.020, accuracy: 1e-12)
    }

    func testBurstWithAllNilLeavesOffsetUnset() async {
        let mock = MockRoundTrip()
        mock.samples = [nil, nil]
        let client = ClockSyncClient()
        client.burstSampleCount = 2
        client.interSampleDelayNanoseconds = 0
        client.attach(roundTrip: mock)
        let best = await client.runBurst()
        XCTAssertNil(best)
        XCTAssertNil(client.offsetSeconds)
    }
}
