import SwiftUI

@Observable
@MainActor
final class AppModel {
    let phoneSession = PhoneSessionManager()
    let faceTracker = FaceTracker()
    let trialEngine = TrialEngine()
    let writer = SessionWriter()

    var athleteId = "athlete-1"
    var hudMessage = "Synapse"
    var showBreakPointFlash = false

    func bootstrap() {
        wireCallbacks()
        faceTracker.start()
    }

    func startLiveSession() {
        _ = writer.startSession(
            athleteId: athleteId,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        faceTracker.resetDetectors()
        trialEngine.startSession()
        hudMessage = "Live session"
    }

    func stopLiveSession() {
        trialEngine.stopSession()
        writer.completeSession()
        hudMessage = "Stopped"
    }

    func runCannedReplay() {
        let canned = CannedSessionFactory.makeDemo()
        writer.ingestCannedSession(canned)
        hudMessage = "Canned replay → \(writer.sessionId ?? "?")"
        if canned.breakPointTrial != nil {
            flashBreakPoint(trial: canned.breakPointTrial ?? 0)
            phoneSession.sendBreakPointHaptic()
        }
    }

    private func wireCallbacks() {
        phoneSession.onStrike = { [weak self] event in
            self?.trialEngine.ingestStrike(event)
        }

        phoneSession.onSyncQuality = { [weak self] offsetMs, rttMs in
            self?.writer.updateClockQuality(offsetMs: offsetMs, rttMs: rttMs)
        }

        faceTracker.onGaze = { [weak self] sample in
            guard let self else { return }
            self.trialEngine.ingestGaze(sample)
            if let saccade = self.faceTracker.lastSaccade {
                self.trialEngine.ingestSaccade(saccade)
            }
            if let arousal = self.faceTracker.lastArousal {
                self.trialEngine.ingestArousal(arousal)
            }
        }

        trialEngine.onTrialCompleted = { [weak self] trial, gaze, t0 in
            guard let self else { return }
            // Fire-and-forget — writer never blocks the trial loop.
            self.writer.writeTrial(trial, gaze: gaze, t0Ms: t0)
            self.hudMessage = trial.valid
                ? String(format: "Gap %.0f ms", trial.cognitiveMotorGapMs ?? 0)
                : "Invalid: \(trial.invalidReason ?? "?")"
        }

        trialEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }

        trialEngine.onBreakPoint = { [weak self] index, mean, std in
            guard let self else { return }
            self.writer.writeBreakPoint(
                trialIndex: index,
                baselineGapMs: mean,
                baselineStdMs: std
            )
            self.phoneSession.sendBreakPointHaptic()
            self.flashBreakPoint(trial: index)
        }
    }

    private func flashBreakPoint(trial: Int) {
        showBreakPointFlash = true
        hudMessage = "BREAK-POINT · trial \(trial + 1)"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showBreakPointFlash = false
        }
    }
}

@main
struct SynapseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.bootstrap() }
        }
    }
}
