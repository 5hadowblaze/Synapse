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
    let module: SessionModule
    let clockOffsetMs: Double
    let clockRttMs: Double
    let baselineGapMs: Double
    let baselineStdMs: Double
    let breakPointTrial: Int?
    let trials: [CannedTrial]
}

enum CannedSessionFactory {
    /// Synthetic demo session (vision-style visual RT break-point) for dashboard smoke.
    static func makeDemo() -> CannedSession {
        var trials: [CannedTrial] = []
        let baselineMean = 180.0
        let baselineStd = 12.0

        for i in 0..<16 {
            let targetOnset = Double(i) * 2000.0 + 500
            let visualRt: Double
            if i < 10 {
                visualRt = baselineMean + Double.random(in: -baselineStd...baselineStd)
            } else if i == 12 {
                visualRt = baselineMean + 2.5 * baselineStd
            } else {
                visualRt = baselineMean + Double.random(in: 0...1.5) * baselineStd
            }
            let saccade = targetOnset + visualRt
            let trial = TrialRecord(
                index: i,
                targetCell: 4,
                targetOnsetMs: targetOnset,
                saccadeOnsetMs: saccade,
                gazeSettleMs: saccade + 40,
                strikeMs: nil,
                visualRtMs: visualRt,
                motorRtMs: nil,
                cognitiveMotorGapMs: nil,
                peakG: nil,
                arousalIndex: Float.random(in: 0.2...0.8),
                valid: true,
                invalidReason: nil,
                targetOctant: nil,
                detectedOctant: nil,
                spatialMatch: nil
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
            module: .visionPvt,
            clockOffsetMs: 12.4,
            clockRttMs: 38.0,
            baselineGapMs: baselineMean,
            baselineStdMs: baselineStd,
            breakPointTrial: 12,
            trials: trials
        )
    }
}
