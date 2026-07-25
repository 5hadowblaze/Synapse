import Foundation

struct CannedTrial: Sendable {
    let trial: TrialRecord
    let gaze: [GazeWindowSample]
    let t0Ms: Double
}

struct CannedSession: Sendable {
    /// Matches web default / seed: `demo-session-001`.
    let sessionId: String
    let athleteId: String
    let clockOffsetMs: Double
    let clockRttMs: Double
    let baselineGapMs: Double
    let baselineStdMs: Double
    let breakPointTrial: Int?
    let trials: [CannedTrial]
}

enum CannedSessionFactory {
    /// Synthetic demo session with a clear fatigue break-point after baseline.
    static func makeDemo() -> CannedSession {
        var trials: [CannedTrial] = []
        let baselineMean = 180.0
        let baselineStd = 12.0

        for i in 0..<16 {
            let targetOnset = Double(i) * 2000.0 + 500
            let visualRt = 120.0 + Double.random(in: -10...10)
            let gap: Double
            if i < 10 {
                gap = baselineMean + Double.random(in: -baselineStd...baselineStd)
            } else if i == 12 {
                gap = baselineMean + 2.5 * baselineStd
            } else {
                gap = baselineMean + Double.random(in: 0...1.5) * baselineStd
            }
            let saccade = targetOnset + visualRt
            let strike = saccade + gap
            let cell = i % 9
            let trial = TrialRecord(
                index: i,
                targetCell: cell,
                targetOnsetMs: targetOnset,
                saccadeOnsetMs: saccade,
                gazeSettleMs: saccade + 40,
                strikeMs: strike,
                visualRtMs: visualRt,
                motorRtMs: strike - targetOnset,
                cognitiveMotorGapMs: gap,
                peakG: 4.5 + Double.random(in: -0.5...1.5),
                arousalIndex: Float.random(in: 0.2...0.8),
                valid: true,
                invalidReason: nil
            )
            let t0 = targetOnset - 200
            var gaze: [GazeWindowSample] = []
            for s in 0..<60 {
                let dt = Double(s) * (1000.0 / 60.0)
                gaze.append(GazeWindowSample(
                    dt: dt,
                    x: Float(sin(dt / 80)) * 0.05,
                    y: Float(cos(dt / 90)) * 0.05,
                    z: -0.3
                ))
            }
            trials.append(CannedTrial(trial: trial, gaze: gaze, t0Ms: t0))
        }

        return CannedSession(
            sessionId: SynapseSessionIDs.demo,
            athleteId: "athlete-demo",
            clockOffsetMs: 12.4,
            clockRttMs: 38.0,
            baselineGapMs: baselineMean,
            baselineStdMs: baselineStd,
            breakPointTrial: 12,
            trials: trials
        )
    }
}
