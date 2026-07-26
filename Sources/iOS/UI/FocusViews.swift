import SwiftUI
import UIKit

// MARK: - Chrome

/// Shared Focus surfaces — dark, cool charcoal with one teal accent.
/// Inspired by calm health apps (quiet labels, hero numbers); no purple, no neon glow.
private enum FocusChrome {
    static let canvasTop = Color(red: 0.045, green: 0.07, blue: 0.085)
    static let canvasMid = Color(red: 0.025, green: 0.04, blue: 0.055)
    static let canvasBreak = Color(red: 0.05, green: 0.08, blue: 0.07)
    static let surface = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.10)
    static let label = Color.white.opacity(0.38)
    static let body = Color.white.opacity(0.55)
    static let accent = Color(red: 0.35, green: 0.72, blue: 0.68)
}

// MARK: - Signal state styling

/// Colour + copy for the three HUD states. Escalation is by warmth, not by alarm:
/// teal → sand → amber, with no reds and no motion spikes.
extension FocusSignalState {
    var label: String {
        switch self {
        case .steady: return "Steady"
        case .easing: return "Easing off"
        case .breakSuggested: return "Break suggested"
        }
    }

    var detail: String? {
        switch self {
        case .steady: return nil
        case .easing: return "Drifting from your baseline"
        case .breakSuggested: return "A pause now costs less than pushing through"
        }
    }

    var tint: Color {
        switch self {
        case .steady: return FocusChrome.accent
        case .easing: return Color(red: 0.85, green: 0.70, blue: 0.42)
        case .breakSuggested: return Color(red: 0.93, green: 0.56, blue: 0.30)
        }
    }

    /// Label opacity — steady stays quiet, escalation earns contrast.
    var labelOpacity: Double {
        self == .steady ? 0.55 : 0.95
    }
}

// MARK: - Shared chrome bits

private struct FocusSectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .kerning(1.4)
            .foregroundStyle(FocusChrome.label)
    }
}

private struct FocusPrimaryButton: View {
    let title: String
    var tint: Color = FocusChrome.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.92))
                )
        }
        .buttonStyle(SoftPressButtonStyle())
    }
}

private var focusCalmBackground: some View {
    LinearGradient(
        colors: [FocusChrome.canvasTop, FocusChrome.canvasMid, Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
}

// MARK: - Focus Setup

struct FocusSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            focusCalmBackground

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            Button { model.returnToHub() } label: {
                                Label("Hub", systemImage: "chevron.left")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(FocusChrome.surface)
                                    .overlay(Capsule(style: .continuous).strokeBorder(FocusChrome.hairline, lineWidth: 1))
                            )
                            Spacer()
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Focus")
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .tracking(-0.6)
                                .foregroundStyle(.white)

                            Text(model.focusCameraMode.setupSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(FocusChrome.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        readinessRow

                        VStack(alignment: .leading, spacing: 10) {
                            FocusSectionLabel(title: "Sensing")
                            FocusCameraModePicker(selection: $model.focusCameraMode)

                            Text(model.focusCameraMode.honestyLine)
                                .font(.caption)
                                .foregroundStyle(
                                    model.focusCameraMode == .watchOnly
                                        ? Color(red: 0.85, green: 0.70, blue: 0.42).opacity(0.9)
                                        : FocusChrome.body.opacity(0.85)
                                )
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Face sensing stays on-device. No face video leaves the phone.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.28))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            FocusSectionLabel(title: "Duration")

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(model.availableFocusPresets) { preset in
                                    FocusPresetCell(
                                        preset: preset,
                                        isSelected: model.selectedFocusPreset == preset
                                    ) {
                                        model.selectedFocusPreset = preset
                                    }
                                }
                            }

                            presetNote
                        }

                        ReactionCheckBookendToggle(isOn: $model.reactionCheckBookendEnabled)

                        if model.focusCameraMode != .watchOnly {
                            PostureRemindersToggle(isOn: $model.postureRemindersEnabled)
                        }

                        Text(
                            model.focusCameraMode == .watchOnly
                                ? "Watch preferred for HR + stillness. Camera stays off for this block."
                                : model.focusCameraMode == .briefCheckIns
                                    ? "Camera sleeps between short looks. Watch preferred for HR + stillness."
                                    : "Phone nearby for face arousal. Watch preferred for HR + stillness."
                        )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)

                FocusPrimaryButton(
                    title: model.reactionCheckBookendEnabled ? "Start with reaction check" : "Start focus"
                ) {
                    model.beginFocusFlow()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var presetNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.selectedFocusPreset.note)
                .font(.caption)
                .foregroundStyle(FocusChrome.body)
            if model.selectedFocusPreset.calibratesFast {
                Text("Fade signal goes live in about \(model.selectedFocusPreset.baselineSeconds) seconds.")
                    .font(.caption2)
                    .foregroundStyle(FocusChrome.accent.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.22), value: model.selectedFocusPreset)
    }

    private var readinessRow: some View {
        HStack(spacing: 14) {
            switch model.focusCameraMode {
            case .alwaysOn:
                chip(
                    ok: model.faceTracker.isTracking,
                    label: model.faceTracker.isTracking ? "Face" : "Seek face"
                )
            case .briefCheckIns:
                chip(ok: true, label: "Brief looks", muted: true)
            case .watchOnly:
                chip(ok: true, label: "Camera off", muted: true)
            }
            chip(
                ok: model.isWatchConnected,
                label: model.isWatchConnected ? "Watch" : "No Watch"
            )
            if let bpm = model.phoneSession.lastHeartRateBpm {
                chip(ok: true, label: String(format: "%.0f bpm", bpm))
            }
        }
    }

    private func chip(ok: Bool, label: String, muted: Bool = false) -> some View {
        let color: Color = muted
            ? Color.white.opacity(0.45)
            : (ok ? FocusChrome.accent : Color.orange.opacity(0.8))
        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(FocusChrome.surface)
        )
    }
}

/// Named block, then the minutes. The name is what gets said out loud.
struct FocusPresetCell: View {
    let preset: FocusPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(preset.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if preset.calibratesFast {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(FocusChrome.accent.opacity(isSelected ? 0.9 : 0.5))
                    }
                }
                Text(preset.title)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(isSelected ? 0.72 : 0.42))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? FocusChrome.accent.opacity(0.18) : FocusChrome.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? FocusChrome.accent.opacity(0.7) : FocusChrome.hairline,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityLabel("\(preset.name), \(preset.focusMinutes) minute focus, \(preset.breakMinutes) minute break")
    }
}

/// Segmented camera policy for Focus — three MASTER §6 modes, calm chrome.
struct FocusCameraModePicker: View {
    @Binding var selection: FocusCameraMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FocusCameraMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.shortLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == mode ? Color.white : Color.white.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selection == mode ? FocusChrome.accent.opacity(0.26) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FocusChrome.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(FocusChrome.hairline, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

// MARK: - Focus Live

struct FocusLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.focusUsesCamera {
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
                .opacity(0.14)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else {
                focusCalmBackground
            }

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Spacer(minLength: 12)

                FocusTimerRing(
                    progress: focusProgress,
                    fadeProgress: model.focusEngine.fadeProgress ?? 0,
                    state: signalState,
                    baselineProgress: model.focusEngine.baselineReady
                        ? 1
                        : model.focusEngine.baselineProgress,
                    clawdState: focusClawdState,
                    clawdOpacity: focusClawdOpacity
                )
                .frame(width: 248, height: 248)

                Text(timeLabel)
                    .font(.system(size: 58, weight: .light, design: .rounded))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                signalReadout
                    .padding(.top, 10)

                if model.postureNudgeVisible {
                    postureNudgeBanner
                        .padding(.top, 12)
                        .padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                presenceNote

                heartRateLive
                    .padding(.top, 18)
                    .padding(.horizontal, 24)

                if let sid = model.writer.sessionId {
                    dashboardSessionLink(sid)
                        .padding(.top, 10)
                        .padding(.horizontal, 24)
                }

                if model.focusEngine.fadeCount > 0 {
                    Text("Fades \(model.focusEngine.fadeCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.top, 8)
                }

                Spacer(minLength: 12)

                bottomChrome
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
            .animation(.easeInOut(duration: 0.35), value: model.postureNudgeVisible)
        }
    }

    private var postureNudgeBanner: some View {
        VStack(spacing: 4) {
            Text("Ease your posture")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.85, green: 0.70, blue: 0.42))
            Text("You’ve drifted from your sit-tall baseline")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.85, green: 0.70, blue: 0.42).opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.85, green: 0.70, blue: 0.42).opacity(0.45), lineWidth: 1)
                )
        )
        .accessibilityLabel("Posture reminder")
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            liveChromeButton(title: "End", systemImage: "xmark") {
                model.stopFocusSession()
            }
            Spacer()
            Button {
                model.showSignals = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(FocusChrome.surface)
                            .overlay(Circle().strokeBorder(FocusChrome.hairline, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Signals")

            Text(model.focusCameraPresence.chipLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cameraChipColor)
                .padding(.trailing, 4)
            if model.focusEngine.isPaused {
                liveChromeButton(title: "Resume") { model.resumeFocus() }
            } else {
                liveChromeButton(title: "Pause") { model.pauseFocus() }
            }
        }
    }

    private func liveChromeButton(title: String, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(FocusChrome.surface)
                    .overlay(Capsule(style: .continuous).strokeBorder(FocusChrome.hairline, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var presenceNote: some View {
        if model.focusCameraMode == .watchOnly {
            Text("Lower confidence — camera off")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 4)
        } else if model.focusCameraMode == .briefCheckIns, !model.focusUsesCamera {
            Text("Camera sleeping · HR still watching")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 4)
        } else if model.postureRemindersEnabled,
                  model.focusUsesCamera,
                  !model.postureBaselineReady {
            let pct = Int((model.postureBaselineProgress * 100).rounded())
            Text("Sit tall · posture baseline \(pct)%")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 4)
        }
    }

    private var liveHeartRateBpm: Double? {
        model.focusEngine.lastHrBpm ?? model.phoneSession.lastHeartRateBpm
    }

    /// Reachable Watch or a recent sample — show the measuring / live HR surface.
    private var isWatchHeartRateLive: Bool {
        liveHeartRateBpm != nil || model.phoneSession.isReachable
    }

    @ViewBuilder
    private var heartRateLive: some View {
        if isWatchHeartRateLive {
            HeartRatePulseIndicator(
                bpm: liveHeartRateBpm,
                isMeasuring: liveHeartRateBpm == nil && model.phoneSession.isReachable,
                measuredAt: model.phoneSession.lastHeartRateReceivedAt,
                size: .card
            )
            .animation(.snappy(duration: 0.25), value: liveHeartRateBpm.map { Int($0.rounded()) })
        }
    }

    private func dashboardSessionLink(_ sessionId: String) -> some View {
        let url = "https://synapse-clinical-hz.web.app/session/\(sessionId)"
        return Button {
            UIPasteboard.general.string = url
            model.hudMessage = "Dashboard link copied"
        } label: {
            VStack(spacing: 3) {
                Text("Live dashboard")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FocusChrome.accent.opacity(0.85))
                Text(sessionId)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Tap to copy link")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FocusChrome.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy live dashboard link")
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if model.focusEngine.fadeSuggested {
            earlyBreakCTA
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            softTimerChrome
        }
    }

    /// Early break on rising fade — dismissible. Soft timer still completes if ignored.
    private var earlyBreakCTA: some View {
        VStack(spacing: 12) {
            Text("Better a short pause now than overrunning later.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            FocusPrimaryButton(
                title: "Take a break",
                tint: FocusSignalState.breakSuggested.tint
            ) {
                model.acceptFocusBreak()
            }

            HStack(spacing: 10) {
                Button("Extend +5") { model.extendFocusBlock() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FocusChrome.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                            )
                    )
                    .disabled(model.focusEngine.didExtend)
                    .opacity(model.focusEngine.didExtend ? 0.4 : 1)

                Button {
                    model.focusEngine.dismissFadeSuggestion()
                } label: {
                    Text("Keep focusing")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(FocusChrome.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            FocusSignalState.breakSuggested.tint.opacity(0.28),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.35), value: model.focusEngine.fadeSuggested)
    }

    /// Soft timer fallback — block still ends when the clock hits zero.
    private var softTimerChrome: some View {
        VStack(spacing: 10) {
            Text("Soft timer · ends on its own if you stay")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.28))

            HStack(spacing: 10) {
                Button("Break now") { model.acceptFocusBreak() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FocusChrome.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                            )
                    )

                Button("Extend +5") { model.extendFocusBlock() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FocusChrome.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                            )
                    )
                    .disabled(model.focusEngine.didExtend)
                    .opacity(model.focusEngine.didExtend ? 0.4 : 1)
            }
            .buttonStyle(.plain)
        }
    }

    /// Steady · easing off · break suggested. Copy changes, layout never jumps.
    private var signalReadout: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(signalState.tint)
                    .frame(width: 6, height: 6)
                    .opacity(signalState == .steady ? 0.55 : 1)
                Text(signalState.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(signalState.tint.opacity(signalState.labelOpacity))
            }

            Text(detailLine ?? " ")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.38))
                .frame(height: 16)
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.5), value: signalState)
    }

    private var signalState: FocusSignalState {
        model.focusEngine.signalState
    }

    private var cameraChipColor: Color {
        switch model.focusCameraPresence {
        case .cameraOn:
            return FocusChrome.accent.opacity(0.9)
        case .checkingIn:
            return Color(red: 0.85, green: 0.70, blue: 0.42).opacity(0.95)
        case .cameraOff:
            return .white.opacity(0.45)
        }
    }

    private var detailLine: String? {
        if !model.focusEngine.baselineReady, signalState == .steady {
            // The window is full but the detector is still holding out for a settled
            // heart rate. Percentage has stopped moving, so say what it is waiting on
            // rather than letting a stuck number read as a hang.
            if model.focusEngine.isSettlingBaseline {
                return "Waiting for your heart rate to settle"
            }
            let pct = Int((model.focusEngine.baselineProgress * 100).rounded())
            return "Learning your baseline · \(pct)%"
        }
        return signalState.detail
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

    /// Clawd sleeps in the ring during Focus; animates only when a nudge speaks.
    private var focusClawdState: ClawdAnimState {
        let voice = model.voiceAssistant
        if voice.isAwakeForNudge, voice.phase == .idle {
            return .waiting
        }
        switch voice.phase {
        case .idle: return .idle
        case .connecting: return .waving
        case .listening: return .waiting
        case .thinking: return .running
        case .speaking: return .review
        case .error: return .failed
        }
    }

    private var focusClawdOpacity: Double {
        let voice = model.voiceAssistant
        if voice.isAwakeForNudge { return 0.85 }
        switch voice.phase {
        case .idle: return 0.5
        case .error: return 0.55
        default: return 0.85
        }
    }
}

// MARK: - Focus Break

struct FocusBreakView: View {
    @Bindable var model: AppModel

    private var breathing: BreathingCoach { model.breathingCoach }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [FocusChrome.canvasBreak, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Button { model.endFocusToRecap() } label: {
                        Label("End", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(FocusChrome.surface)
                                    .overlay(Capsule(style: .continuous).strokeBorder(FocusChrome.hairline, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if breathing.isRunning {
                        Button("Stop breath") { model.stopBreathingReset() }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(FocusChrome.surface)
                                    .overlay(Capsule(style: .continuous).strokeBorder(FocusChrome.hairline, lineWidth: 1))
                            )
                            .buttonStyle(.plain)
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
        VStack(spacing: 16) {
            FocusSectionLabel(title: "Break")

            Text(breakTimeLabel)
                .font(.system(size: 64, weight: .light, design: .rounded))
                .tracking(-1.4)
                .monospacedDigit()
                .foregroundStyle(FocusChrome.accent)

            Text("Step away · soften your gaze · breathe")
                .font(.subheadline)
                .foregroundStyle(FocusChrome.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var breathingContent: some View {
        VStack(spacing: 22) {
            Text(breathing.phase == .complete ? "Reset complete" : "Breathing reset")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.48))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    .frame(width: 200, height: 200)
                Circle()
                    .trim(from: 0, to: breathing.overallProgress)
                    .stroke(
                        FocusChrome.accent.opacity(0.88),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
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
                            .foregroundStyle(FocusChrome.accent)
                    }
                }
            }

            if breathing.isRunning {
                Text("Cycle \(breathing.cycleIndex + 1) of \(breathing.totalCycles)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        if model.showLockInTenCTA || breathing.phase == .complete {
            FocusPrimaryButton(title: "Lock in another 10 min") {
                model.lockInTenMinutes()
            }

            HStack(spacing: 10) {
                secondaryBreakButton("Skip to recap") { model.skipFocusBreak() }
                secondaryBreakButton("Extend +5") { model.extendFocusBlock() }
                    .disabled(model.focusEngine.didExtend)
                    .opacity(model.focusEngine.didExtend ? 0.4 : 1)
            }
        } else if breathing.isRunning {
            Text("Follow the voice · inhale · hold · exhale")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            FocusPrimaryButton(title: "Breathing reset") {
                model.startBreathingReset()
            }

            HStack(spacing: 8) {
                secondaryBreakButton("Skip break") { model.skipFocusBreak() }
                secondaryBreakButton("Extend +5") { model.extendFocusBlock() }
                    .disabled(model.focusEngine.didExtend)
                    .opacity(model.focusEngine.didExtend ? 0.4 : 1)
                secondaryBreakButton("Lock in 10") { model.lockInTenMinutes() }
            }
        }
    }

    private func secondaryBreakButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FocusChrome.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
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

    private var narrative: FocusPacingNarrative {
        FocusPacingNarrative.build(
            recap: model.lastFocusRecap,
            comparison: model.lastReactionComparison
        )
    }

    private var voice: VoiceAssistantController { model.voiceAssistant }

    var body: some View {
        ZStack {
            focusCalmBackground

            if voice.isReflecting {
                FocusReflectView(model: model)
                    .transition(.opacity)
            } else {
                recapScroll
            }
        }
        .animation(.easeInOut(duration: 0.28), value: voice.isReflecting)
    }

    private var recapScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Recap")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .padding(.top, 28)

                // Measured, not inferred — this leads the recap when it exists.
                if let comparison = model.lastReactionComparison {
                    ReactionDeltaCard(comparison: comparison)
                        .padding(.bottom, 4)
                }

                if !narrative.cards.isEmpty {
                    FocusPacingNarrativeSection(narrative: narrative)
                }

                if let recap = model.lastFocusRecap {
                    VStack(spacing: 0) {
                        recapRow("Focused", recap.focusedMinutesLabel)
                        recapDivider
                        recapRow("Break", formatSeconds(recap.breakSeconds))
                        recapDivider
                        recapRow("Fades", "\(recap.fadeCount)")
                        if let hr = recap.meanHrBpm {
                            recapDivider
                            recapRow("Mean HR", String(format: "%.0f bpm", hr))
                        }
                        recapDivider
                        recapRow(
                            "Baseline",
                            recap.baselineReady ? "Ready" : "Building"
                        )
                        if recap.extendedOnce {
                            recapDivider
                            recapRow("Extended", "+5 once")
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(FocusChrome.surface)
                    )
                } else {
                    Text("No session data")
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let summary = voice.checkInSummary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        FocusSectionLabel(title: "You said")
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }

                if !model.patternStore.tips.isEmpty {
                    FocusSectionLabel(title: "Patterns")
                        .padding(.top, 4)

                    ForEach(Array(model.patternStore.tips.enumerated()), id: \.offset) { _, tip in
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 2)
                    }
                }

                VStack(spacing: 12) {
                    if voice.isVoiceOnline {
                        FocusPrimaryButton(title: "Talk it through") {
                            voice.startReflectMode()
                        }
                    } else {
                        Text("Voice offline — talk-through unavailable")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        if !voice.checkInResolved {
                            voice.skipCheckIn()
                        }
                        model.returnToHub()
                    } label: {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(FocusChrome.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 28)
        }
    }

    private var recapDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func recapRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func formatSeconds(_ t: TimeInterval) -> String {
        let s = Int(t)
        let m = s / 60
        let r = s % 60
        if m > 0 { return "\(m)m \(r)s" }
        return "\(r)s"
    }
}

// MARK: - Talk-through (reflect)

/// Full-bleed calm reflect surface — orb pulse + live caption; no card grid.
struct FocusReflectView: View {
    @Bindable var model: AppModel

    private var voice: VoiceAssistantController { model.voiceAssistant }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.08),
                    Color(red: 0.02, green: 0.04, blue: 0.05),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Soft breath of teal — atmosphere, not a card.
            Circle()
                .fill(FocusChrome.accent.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(y: -40)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        voice.skipCheckIn()
                    } label: {
                        Text("Skip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(FocusChrome.surface)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(FocusChrome.hairline, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                VStack(spacing: 28) {
                    Text("Talk it through")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(FocusChrome.label)

                    ZStack {
                        Circle()
                            .fill(FocusChrome.accent.opacity(voice.phase == .speaking ? 0.28 : 0.14))
                            .frame(width: 120, height: 120)
                            .scaleEffect(voice.phase == .listening || voice.phase == .speaking ? 1.08 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                value: voice.phase == .listening || voice.phase == .speaking
                            )

                        Circle()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            .frame(width: 88, height: 88)

                        Image(systemName: reflectIcon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .symbolEffect(.pulse, isActive: voice.phase == .listening || voice.phase == .speaking)
                    }

                    Text(caption)
                        .font(.title3.weight(.regular))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 36)
                        .frame(minHeight: 88, alignment: .top)
                        .animation(.easeOut(duration: 0.2), value: caption)

                    Text(phaseHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer()

                Text("Self-report only · say when you're done")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.bottom, 36)
            }
        }
    }

    private var caption: String {
        if voice.phase == .error, let err = voice.lastError, !err.isEmpty {
            return err
        }
        let t = voice.transcriptSnippet
        if !t.isEmpty { return t }
        return "…"
    }

    private var phaseHint: String {
        switch voice.phase {
        case .connecting: return "Connecting…"
        case .listening: return "Listening"
        case .thinking: return "…"
        case .speaking: return "Synapse"
        case .error: return "Voice issue"
        case .idle: return " "
        }
    }

    private var reflectIcon: String {
        switch voice.phase {
        case .listening: return "mic.fill"
        case .speaking: return "waveform"
        case .connecting, .thinking: return "ellipsis"
        case .error: return "exclamationmark.triangle.fill"
        case .idle: return "waveform"
        }
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
                FocusSectionLabel(title: "Patterns")
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
                    .fill(FocusChrome.surface)
            )
        }
    }
}

// MARK: - Timer ring

struct FocusTimerRing: View {
    let progress: Double
    /// 0…1 from the baseline mean toward the fade threshold — not the raw fade score,
    /// which rests near zero and would leave this ring looking broken.
    let fadeProgress: Double
    let state: FocusSignalState
    /// 0…1 toward a usable fade baseline. Below 1 the inner ring reads as "still learning".
    var baselineProgress: Double = 1
    /// Sleeping Clawd in the ring during Focus live (nil = no pet).
    var clawdState: ClawdAnimState? = nil
    var clawdOpacity: Double = 0.5

    private var isCalibrating: Bool { baselineProgress < 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 9)

            // Elapsed time.
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    state.tint.opacity(0.88),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)

            // Inner ring: baseline fill while calibrating, then progress toward a break.
            // Half-full is exactly where `easing` begins, so the label and the ring agree.
            Circle()
                .trim(from: 0, to: innerTrim)
                .stroke(
                    state.tint.opacity(isCalibrating ? 0.22 : 0.36),
                    style: isCalibrating
                        ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6])
                        : StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .padding(16)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.1), value: innerTrim)

            // Soft escalation wash — opacity only, no bloom radius spike.
            Circle()
                .fill(state.tint.opacity(haloOpacity))
                .blur(radius: 28)
                .padding(8)
                .allowsHitTesting(false)

            if let clawdState {
                ClawdSpriteView(state: clawdState, displayHeight: 78)
                    .opacity(clawdOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: 0.85), value: state)
    }

    private var innerTrim: Double {
        min(1, max(0, isCalibrating ? baselineProgress : fadeProgress))
    }

    private var haloOpacity: Double {
        switch state {
        case .steady: return 0
        case .easing: return 0.06
        case .breakSuggested: return 0.11
        }
    }
}
