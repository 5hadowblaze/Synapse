import SwiftUI

// MARK: - Focus Setup

struct FocusSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            calmBackground

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { model.returnToHub() } label: {
                        Label("Hub", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.top, 12)

                Text("Focus")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Health-aware Pomodoro · face + HR")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))

                Text(model.hudMessage)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.teal.opacity(0.9))

                readinessRow

                Text("Duration")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(FocusPreset.all) { preset in
                        Button {
                            model.selectedFocusPreset = preset
                        } label: {
                            Text(preset.title)
                                .font(.headline.monospacedDigit())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(model.selectedFocusPreset == preset
                                              ? Color.teal.opacity(0.35)
                                              : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(
                                            model.selectedFocusPreset == preset
                                                ? Color.teal.opacity(0.8)
                                                : Color.white.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Text("Phone nearby for face arousal. Watch preferred for HR + stillness.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.leading)

                Button {
                    model.startFocusSession()
                } label: {
                    Text("Start focus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
    }

    private var readinessRow: some View {
        HStack(spacing: 16) {
            chip(
                ok: model.faceTracker.isTracking,
                label: model.faceTracker.isTracking ? "Face" : "Seek face"
            )
            chip(
                ok: model.isWatchConnected,
                label: model.isWatchConnected ? "Watch" : "No Watch"
            )
            if let bpm = model.phoneSession.lastHeartRateBpm {
                chip(ok: true, label: String(format: "%.0f bpm", bpm))
            }
        }
    }

    private func chip(ok: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color.teal : Color.orange.opacity(0.8))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ok ? Color.teal : Color.orange)
        }
    }

    private var calmBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.07, blue: 0.09),
                Color(red: 0.02, green: 0.04, blue: 0.06),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Focus Live

struct FocusLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                // Focus preview is ambient — disable cyan saccade flashes (token ≤ 0 is ignored).
                saccadeFlashToken: 0,
                faceMeshOpacity: 0,
                showGazeRay: false,
                showTrackingRing: false,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .opacity(0.18)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button { model.stopFocusSession() } label: {
                        Label("End", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if model.focusEngine.isPaused {
                        Button("Resume") { model.resumeFocus() }
                            .buttonStyle(.bordered)
                            .tint(.teal)
                    } else {
                        Button("Pause") { model.pauseFocus() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                FocusTimerRing(
                    progress: focusProgress,
                    fadeScore: model.focusEngine.fadeScore ?? 0,
                    suggested: model.focusEngine.fadeSuggested
                )
                .frame(width: 260, height: 260)

                Text(timeLabel)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.top, 28)

                Text(model.focusEngine.fadeSuggested ? "Fade suggested" : "Focus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(model.focusEngine.fadeSuggested ? Color.orange : Color.white.opacity(0.45))
                    .padding(.top, 6)

                HStack(spacing: 20) {
                    if let bpm = model.focusEngine.lastHrBpm ?? model.phoneSession.lastHeartRateBpm {
                        Label(String(format: "%.0f", bpm), systemImage: "heart.fill")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    if model.focusEngine.fadeCount > 0 {
                        Text("Fades \(model.focusEngine.fadeCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.top, 16)

                Spacer()

                if model.focusEngine.fadeSuggested {
                    VStack(spacing: 10) {
                        Button { model.acceptFocusBreak() } label: {
                            Text("Take break")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        HStack(spacing: 12) {
                            Button("Extend +5") { model.extendFocusBlock() }
                                .buttonStyle(.bordered)
                                .disabled(model.focusEngine.didExtend)
                            Button("Keep focusing") {
                                model.focusEngine.dismissFadeSuggestion()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                } else {
                    HStack(spacing: 12) {
                        Button("Break now") { model.acceptFocusBreak() }
                            .buttonStyle(.bordered)
                        Button("Extend +5") { model.extendFocusBlock() }
                            .buttonStyle(.bordered)
                            .disabled(model.focusEngine.didExtend)
                    }
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var focusProgress: Double {
        let total = Double(model.focusEngine.focusMinutes * 60)
        guard total > 0 else { return 0 }
        return 1.0 - min(1, max(0, model.focusEngine.remainingSeconds / total))
    }

    private var timeLabel: String {
        let s = Int(model.focusEngine.remainingSeconds.rounded(.up))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

// MARK: - Focus Break

struct FocusBreakView: View {
    @Bindable var model: AppModel

    private var breathing: BreathingCoach { model.breathingCoach }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.08),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Button { model.endFocusToRecap() } label: {
                        Label("End", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    if breathing.isRunning {
                        Button("Stop breath") { model.stopBreathingReset() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                if breathing.isRunning || breathing.phase == .complete {
                    breathingContent
                } else {
                    idleBreakContent
                }

                Spacer()

                bottomActions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
    }

    private var idleBreakContent: some View {
        VStack(spacing: 18) {
            Text("Break")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))

            Text(breakTimeLabel)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.teal)

            Text("Step away · soften your gaze · breathe")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var breathingContent: some View {
        VStack(spacing: 20) {
            Text(breathing.phase == .complete ? "Reset complete" : "Breathing reset")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 200, height: 200)
                Circle()
                    .trim(from: 0, to: breathing.overallProgress)
                    .stroke(Color.teal.opacity(0.85), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: breathing.overallProgress)

                VStack(spacing: 6) {
                    Text(breathing.phaseLabel)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    if breathing.isRunning, breathing.phaseRemaining > 0 {
                        Text(String(format: "%.0f", breathing.phaseRemaining.rounded(.up)))
                            .font(.title2.monospacedDigit())
                            .foregroundStyle(.teal)
                    }
                }
            }

            if breathing.isRunning {
                Text("Cycle \(breathing.cycleIndex + 1) of \(breathing.totalCycles)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        if model.showLockInTenCTA || breathing.phase == .complete {
            Button { model.lockInTenMinutes() } label: {
                Text("Lock in another 10 min")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            HStack(spacing: 12) {
                Button("Skip to recap") { model.skipFocusBreak() }
                    .buttonStyle(.bordered)
                Button("Extend +5") { model.extendFocusBlock() }
                    .buttonStyle(.bordered)
                    .disabled(model.focusEngine.didExtend)
            }
        } else if breathing.isRunning {
            Text("Follow the voice · inhale · hold · exhale")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Button { model.startBreathingReset() } label: {
                Text("Breathing reset")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            HStack(spacing: 12) {
                Button("Skip break") { model.skipFocusBreak() }
                    .buttonStyle(.bordered)
                Button("Extend +5") { model.extendFocusBlock() }
                    .buttonStyle(.bordered)
                    .disabled(model.focusEngine.didExtend)
                Button("Lock in 10") { model.lockInTenMinutes() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var breakTimeLabel: String {
        let s = Int(model.focusEngine.remainingSeconds.rounded(.up))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

// MARK: - Focus Recap

struct FocusRecapView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Recap")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    if let recap = model.lastFocusRecap {
                        recapRow("Focused", recap.focusedMinutesLabel)
                        recapRow("Break", formatSeconds(recap.breakSeconds))
                        recapRow("Fades", "\(recap.fadeCount)")
                        if let hr = recap.meanHrBpm {
                            recapRow("Mean HR", String(format: "%.0f bpm", hr))
                        }
                        recapRow(
                            "Baseline",
                            recap.baselineReady ? "Ready" : "Building"
                        )
                        if recap.extendedOnce {
                            recapRow("Extended", "+5 once")
                        }
                    } else {
                        Text("No session data")
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if !model.patternStore.tips.isEmpty {
                        Text("Patterns")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 8)

                        ForEach(Array(model.patternStore.tips.enumerated()), id: \.offset) { _, tip in
                            Text(tip)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                        }
                    }

                    Button {
                        model.returnToHub()
                    } label: {
                        Text("Back to Hub")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func recapRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
    }

    private func formatSeconds(_ t: TimeInterval) -> String {
        let s = Int(t)
        let m = s / 60
        let r = s % 60
        if m > 0 { return "\(m)m \(r)s" }
        return "\(r)s"
    }
}

// MARK: - Pattern tips (Hub)

struct FocusPatternTipsCard: View {
    let tips: [String]

    var body: some View {
        if tips.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Patterns")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
                ForEach(Array(tips.prefix(3).enumerated()), id: \.offset) { _, tip in
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
}

// MARK: - Timer ring

struct FocusTimerRing: View {
    let progress: Double
    let fadeScore: Double
    let suggested: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    suggested ? Color.orange.opacity(0.85) : Color.teal.opacity(0.85),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)

            Circle()
                .trim(from: 0, to: min(1, max(0, fadeScore)))
                .stroke(Color.orange.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(14)
                .rotationEffect(.degrees(-90))
        }
    }
}
