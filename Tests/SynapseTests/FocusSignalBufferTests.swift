import XCTest
@testable import Synapse

final class FocusSignalBufferTests: XCTestCase {
    func testAppendRespectsCapacity() {
        var buffer = FocusSignalBuffer(capacity: 3)
        for i in 0..<5 {
            buffer.append(makeSample(elapsed: TimeInterval(i), hr: Double(60 + i)))
        }
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.samples.map(\.elapsedSeconds), [2, 3, 4])
        XCTAssertEqual(buffer.samples.first?.heartRateBpm, 62)
    }

    func testMissingChannelsDoNotAppearInSeries() {
        var buffer = FocusSignalBuffer(capacity: 10)
        buffer.append(makeSample(elapsed: 0, hr: 70, pace: nil, presence: nil, motion: nil, camera: false))
        buffer.append(makeSample(elapsed: 2, hr: nil, pace: 0.2, presence: 0.5, motion: 0.1, camera: true))
        buffer.append(makeSample(elapsed: 4, hr: 72, pace: 0.3, presence: nil, motion: nil, camera: false))

        XCTAssertEqual(buffer.heartRateSeries.map(\.value), [70, 72])
        XCTAssertEqual(buffer.paceSeries.map(\.value), [0.2, 0.3])
        XCTAssertEqual(buffer.presenceSeries.map(\.value), [0.5])
        XCTAssertEqual(buffer.motionSeries.map(\.value), [0.1])
        XCTAssertTrue(buffer.hasHeartRate)
        XCTAssertTrue(buffer.hasPace)
        XCTAssertTrue(buffer.hasPresence)
        XCTAssertTrue(buffer.hasMotion)
    }

    func testPresenceSeriesRequiresCameraAwake() {
        var buffer = FocusSignalBuffer(capacity: 5)
        buffer.append(makeSample(elapsed: 0, presence: 0.8, camera: false))
        XCTAssertTrue(buffer.presenceSeries.isEmpty)
        XCTAssertFalse(buffer.hasPresence)

        buffer.append(makeSample(elapsed: 2, presence: 0.7, camera: true))
        XCTAssertEqual(buffer.presenceSeries.map(\.value), [0.7])
        XCTAssertTrue(buffer.hasPresence)
    }

    func testEventsTrimWithSampleWindow() {
        var buffer = FocusSignalBuffer(capacity: 2)
        buffer.mark(FocusSignalEvent(date: Date(), elapsedSeconds: 0, kind: .baselineReady))
        buffer.append(makeSample(elapsed: 0, hr: 60))
        buffer.append(makeSample(elapsed: 1, hr: 61))
        buffer.append(makeSample(elapsed: 2, hr: 62))
        // Capacity 2 keeps elapsed 1 and 2 — event at 0 should drop.
        XCTAssertTrue(buffer.events.isEmpty)

        buffer.mark(FocusSignalEvent(date: Date(), elapsedSeconds: 2, kind: .breakSuggested))
        XCTAssertEqual(buffer.events.count, 1)
        XCTAssertEqual(buffer.events.first?.kind, .breakSuggested)
    }

    func testResetClearsSamplesAndEvents() {
        var buffer = FocusSignalBuffer(capacity: 5)
        buffer.append(makeSample(elapsed: 1, hr: 65))
        buffer.mark(FocusSignalEvent(date: Date(), elapsedSeconds: 1, kind: .baselineReady))
        buffer.reset()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertTrue(buffer.events.isEmpty)
    }

    @MainActor
    func testStoreThrottlesOrdinarySamples() {
        let store = FocusSignalStore()
        store.minSampleInterval = 2
        store.beginSession(at: Date(timeIntervalSince1970: 1_000))

        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(store.record(
            heartRateBpm: 60,
            paceScore: 0.1,
            presenceProxy: nil,
            motionEnergy: nil,
            signalState: .steady,
            cameraAwake: false,
            at: t0
        ))
        XCTAssertFalse(store.record(
            heartRateBpm: 61,
            paceScore: 0.1,
            presenceProxy: nil,
            motionEnergy: nil,
            signalState: .steady,
            cameraAwake: false,
            at: t0.addingTimeInterval(0.5)
        ))
        XCTAssertTrue(store.record(
            heartRateBpm: 62,
            paceScore: 0.12,
            presenceProxy: nil,
            motionEnergy: nil,
            signalState: .steady,
            cameraAwake: false,
            at: t0.addingTimeInterval(2.1)
        ))
        XCTAssertEqual(store.buffer.count, 2)
    }

    @MainActor
    func testStoreForceBypassesThrottle() {
        let store = FocusSignalStore()
        store.minSampleInterval = 10
        let t0 = Date(timeIntervalSince1970: 2_000)
        store.beginSession(at: t0)
        XCTAssertTrue(store.record(
            heartRateBpm: 60,
            paceScore: nil,
            presenceProxy: nil,
            motionEnergy: nil,
            signalState: .steady,
            cameraAwake: false,
            at: t0
        ))
        XCTAssertTrue(store.record(
            heartRateBpm: 90,
            paceScore: 0.9,
            presenceProxy: nil,
            motionEnergy: nil,
            signalState: .breakSuggested,
            cameraAwake: false,
            force: true,
            at: t0.addingTimeInterval(0.2)
        ))
        XCTAssertEqual(store.buffer.count, 2)
    }

    @MainActor
    func testStoreMarksBaselineAndBreakEvents() {
        let store = FocusSignalStore()
        let t0 = Date(timeIntervalSince1970: 3_000)
        store.beginSession(at: t0)
        store.markBaselineReady(at: t0.addingTimeInterval(30))
        store.markBreakSuggested(at: t0.addingTimeInterval(90))
        XCTAssertEqual(store.buffer.events.map(\.kind), [.baselineReady, .breakSuggested])
        XCTAssertEqual(store.buffer.events[0].elapsedSeconds, 30, accuracy: 0.01)
        XCTAssertEqual(store.buffer.events[1].elapsedSeconds, 90, accuracy: 0.01)
    }

    @MainActor
    func testEndSessionKeepsBufferForLastSession() {
        let store = FocusSignalStore()
        store.beginSession()
        _ = store.record(
            heartRateBpm: 68,
            paceScore: 0.05,
            presenceProxy: nil,
            motionEnergy: 0.2,
            signalState: .steady,
            cameraAwake: false
        )
        store.endSession()
        XCTAssertFalse(store.isLive)
        XCTAssertTrue(store.hasSessionData)
        XCTAssertEqual(store.buffer.count, 1)
    }

    // MARK: - Helpers

    private func makeSample(
        elapsed: TimeInterval,
        hr: Double? = nil,
        pace: Double? = nil,
        presence: Double? = nil,
        motion: Double? = nil,
        camera: Bool = false,
        state: FocusSignalState = .steady
    ) -> FocusSignalSample {
        FocusSignalSample(
            date: Date(timeIntervalSince1970: 1_700_000_000 + elapsed),
            elapsedSeconds: elapsed,
            heartRateBpm: hr,
            paceScore: pace,
            presenceProxy: presence,
            motionEnergy: motion,
            signalState: state,
            cameraAwake: camera
        )
    }
}
