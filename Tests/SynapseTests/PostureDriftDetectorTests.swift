import XCTest
@testable import Synapse

final class PostureDriftDetectorTests: XCTestCase {
    private func upright(cranio: Double = 0.55, midY: Double = 0.42, dist: Double? = 0.45) -> PostureFeatures {
        PostureFeatures(
            cranioRatio: cranio,
            midShoulderY: midY,
            faceDistanceMeters: dist,
            quality: 0.8
        )
    }

    private func slumped(from base: PostureFeatures) -> PostureFeatures {
        PostureFeatures(
            cranioRatio: base.cranioRatio - 0.22,
            midShoulderY: base.midShoulderY + 0.08,
            faceDistanceMeters: base.faceDistanceMeters.map { $0 - 0.12 },
            quality: 0.8
        )
    }

    private func makeDetector(
        baselineSamples: Int = 12,
        cooldownSeconds: TimeInterval = 0,
        samplesToFire: Int = 3
    ) -> PostureDriftDetector {
        PostureDriftDetector(
            baselineSamples: baselineSamples,
            cooldownSeconds: cooldownSeconds,
            samplesToFire: samplesToFire
        )
    }

    private func calibrate(
        _ detector: inout PostureDriftDetector,
        count: Int = 12,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> PostureFeatures {
        let base = upright()
        for i in 0..<count {
            // Tiny jitter so σ is non-zero but still “sit tall”.
            let f = PostureFeatures(
                cranioRatio: base.cranioRatio + Double(i % 3) * 0.002,
                midShoulderY: base.midShoulderY + Double(i % 2) * 0.001,
                faceDistanceMeters: 0.45 + Double(i % 2) * 0.002,
                quality: 0.8
            )
            let result = detector.ingest(now: TimeInterval(i), features: f, joints: [], bones: [])
            XCTAssertFalse(result.fired, "calibration must not fire", file: file, line: line)
        }
        XCTAssertTrue(detector.isBaselineReady, file: file, line: line)
        return base
    }

    func testBaselineThenFiresOnSustainedSlump() {
        var detector = makeDetector()
        let base = calibrate(&detector)

        let bad = slumped(from: base)
        XCTAssertFalse(detector.ingestForced(now: 20, features: bad))
        XCTAssertFalse(detector.ingestForced(now: 21, features: bad))
        XCTAssertTrue(detector.ingestForced(now: 22, features: bad))
        XCTAssertEqual(detector.fireCount, 1)
    }

    func testCooldownSuppressesRapidRefire() {
        var detector = makeDetector(cooldownSeconds: 60, samplesToFire: 2)
        let base = calibrate(&detector)
        let bad = slumped(from: base)

        _ = detector.ingestForced(now: 30, features: bad)
        XCTAssertTrue(detector.ingestForced(now: 31, features: bad))
        XCTAssertEqual(detector.fireCount, 1)

        // Still in cooldown — even sustained exceedance should not refire.
        XCTAssertFalse(detector.ingestForced(now: 40, features: bad))
        XCTAssertFalse(detector.ingestForced(now: 41, features: bad))
        XCTAssertEqual(detector.fireCount, 1)

        XCTAssertFalse(detector.ingestForced(now: 95, features: bad))
        XCTAssertTrue(detector.ingestForced(now: 96, features: bad))
        XCTAssertEqual(detector.fireCount, 2)
    }

    func testPoorQualityDoesNotFire() {
        var detector = makeDetector(samplesToFire: 1)
        _ = calibrate(&detector)
        let poor = PostureFeatures(
            cranioRatio: 0.1,
            midShoulderY: 0.7,
            faceDistanceMeters: 0.2,
            quality: 0.1
        )
        XCTAssertFalse(detector.ingestForced(now: 50, features: poor))
        XCTAssertEqual(detector.fireCount, 0)
    }

    func testSavedBaselineSkipsCalibration() {
        var detector = makeDetector(baselineSamples: 12, samplesToFire: 2)
        let base = calibrate(&detector)
        guard let snap = detector.exportedBaseline else {
            return XCTFail("expected snapshot")
        }

        var next = makeDetector(baselineSamples: 12, samplesToFire: 2)
        next.applySavedBaseline(snap)
        XCTAssertTrue(next.isBaselineReady)
        XCTAssertEqual(next.baselineProgress, 1, accuracy: 0.001)

        let bad = slumped(from: base)
        XCTAssertFalse(next.ingestForced(now: 1, features: bad))
        XCTAssertTrue(next.ingestForced(now: 2, features: bad))
    }

    func testUprightAfterBaselineDoesNotFire() {
        var detector = makeDetector(samplesToFire: 2)
        let base = calibrate(&detector)
        for i in 0..<6 {
            XCTAssertFalse(detector.ingestForced(now: TimeInterval(50 + i), features: base))
        }
        XCTAssertEqual(detector.fireCount, 0)
    }

    func testFocusBaselineNeedsMoreSamplesThanLab() {
        XCTAssertEqual(PostureDriftDetector.labBaselineSamples, 80)
        XCTAssertEqual(PostureDriftDetector.focusBaselineSamples, 220)
        XCTAssertEqual(PostureDriftDetector.defaultScoreThreshold, 0.48, accuracy: 0.001)
        XCTAssertEqual(PostureDriftDetector.defaultCooldownSeconds, 90, accuracy: 0.001)
        XCTAssertEqual(PostureDriftDetector.focusCooldownSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(PostureDriftDetector.defaultSamplesToFire, 56)
        XCTAssertEqual(PostureDriftDetector.focusSamplesToFire, 64)
        XCTAssertGreaterThan(
            PostureDriftDetector.focusBaselineSamples,
            PostureDriftDetector.labBaselineSamples
        )
        XCTAssertGreaterThan(
            PostureDriftDetector.focusCooldownSeconds,
            PostureDriftDetector.defaultCooldownSeconds
        )
        XCTAssertGreaterThan(
            PostureDriftDetector.focusSamplesToFire,
            PostureDriftDetector.defaultSamplesToFire
        )

        var focus = PostureDriftDetector(baselineSamples: PostureDriftDetector.focusBaselineSamples)
        let labCount = PostureDriftDetector.labBaselineSamples
        for i in 0..<labCount {
            let f = upright(
                cranio: 0.55 + Double(i % 3) * 0.002,
                midY: 0.42 + Double(i % 2) * 0.001
            )
            _ = focus.ingest(now: TimeInterval(i), features: f, joints: [], bones: [])
        }
        XCTAssertFalse(focus.isBaselineReady, "Lab-length samples must not freeze a Focus baseline")

        let remaining = PostureDriftDetector.focusBaselineSamples - labCount
        for i in 0..<remaining {
            let f = upright(
                cranio: 0.55 + Double(i % 3) * 0.002,
                midY: 0.42 + Double(i % 2) * 0.001
            )
            _ = focus.ingest(now: TimeInterval(labCount + i), features: f, joints: [], bones: [])
        }
        XCTAssertTrue(focus.isBaselineReady)
    }

    func testResetCanSwitchBaselineLength() {
        var detector = PostureDriftDetector(baselineSamples: PostureDriftDetector.labBaselineSamples)
        detector.reset(baselineSamples: PostureDriftDetector.focusBaselineSamples)
        XCTAssertEqual(detector.baselineProgress, 0, accuracy: 0.001)
        XCTAssertFalse(detector.isBaselineReady)
    }
}
