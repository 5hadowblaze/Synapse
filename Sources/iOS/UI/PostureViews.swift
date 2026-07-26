import SwiftUI

// MARK: - Posture Check (Lab)

struct PostureSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: 0,
                armJoints: postureArmJoints,
                armBones: model.faceTracker.postureBones,
                faceMeshOpacity: 0.12,
                showGazeRay: false,
                showTrackingRing: true,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button { model.returnToHub() } label: {
                        Label("Hub", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    SettingsGearButton { model.showSettings = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Text("Posture Check")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Text(model.hudMessage)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color(red: 0.72, green: 0.78, blue: 0.62).opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                Spacer()

                VStack(spacing: 14) {
                    Text("Sit tall — shoulders relaxed, screen near eye height. We’ll learn your baseline, then watch for drift.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.faceTracker.postureStatusText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.45))

                    Button("Start baseline") { model.startPostureSession() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.72, green: 0.78, blue: 0.62))
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var postureArmJoints: [FrontArmEstimator.OverlayJoint] {
        model.faceTracker.postureJoints.map {
            FrontArmEstimator.OverlayJoint(name: $0.name, point: $0.point)
        }
    }
}

struct PostureLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: 0,
                armJoints: postureArmJoints,
                armBones: model.faceTracker.postureBones,
                faceMeshOpacity: 0.10,
                showGazeRay: false,
                showTrackingRing: false,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button { model.stopPostureSession() } label: {
                        Label("Hub", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    SettingsGearButton { model.showSettings = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 12) {
                    if !model.postureBaselineReady {
                        Text("Learning your sit-tall baseline")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        ProgressView(value: model.postureBaselineProgress)
                            .tint(Color(red: 0.55, green: 0.78, blue: 0.72))
                        Text(String(format: "%.0f%%", model.postureBaselineProgress * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Text(driftTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(driftTint)
                        Text(driftDetail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)

                        PostureDriftMeter(score: model.postureLiveScore)
                            .frame(height: 10)
                            .padding(.top, 4)
                    }

                    Text(trackingLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.4))

                    Button("Stop") { model.stopPostureSession() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.72, green: 0.78, blue: 0.62))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var postureArmJoints: [FrontArmEstimator.OverlayJoint] {
        model.faceTracker.postureJoints.map {
            FrontArmEstimator.OverlayJoint(name: $0.name, point: $0.point)
        }
    }

    private var driftTitle: String {
        if model.postureNudgeVisible { return "Ease your posture" }
        let score = model.postureLiveScore
        let threshold = PostureDriftDetector.defaultScoreThreshold
        if score < 0.2 { return "Steady" }
        if score < threshold { return "Slight drift" }
        return "Drifting"
    }

    private var driftDetail: String {
        if model.postureNudgeVisible {
            return "You’ve drifted from your sit-tall baseline."
        }
        return "Compared to the posture you set at the start of this check."
    }

    private var driftTint: Color {
        if model.postureNudgeVisible {
            return Color(red: 0.85, green: 0.70, blue: 0.42)
        }
        let score = model.postureLiveScore
        if score < 0.2 { return Color(red: 0.55, green: 0.78, blue: 0.72) }
        return Color(red: 0.85, green: 0.78, blue: 0.55)
    }

    private var trackingLine: String {
        if model.faceTracker.isPostureTracking {
            return String(format: "Score %.2f · %@", model.postureLiveScore, model.faceTracker.postureStatusText)
        }
        return "Seek upper body in frame · sit back slightly"
    }
}

private struct PostureDriftMeter: View {
    let score: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(meterTint)
                    .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, score)))))
            }
        }
    }

    private var meterTint: Color {
        if score < 0.2 { return Color(red: 0.55, green: 0.78, blue: 0.72) }
        if score < PostureDriftDetector.defaultScoreThreshold {
            return Color(red: 0.85, green: 0.78, blue: 0.55)
        }
        return Color(red: 0.85, green: 0.70, blue: 0.42)
    }
}

/// Soft Focus posture reminders — parallel to fade, never weights break score.
struct PostureRemindersToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Posture reminders")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Soft nudge if you drift from your sit-tall baseline. Doesn’t affect break suggestions.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                ReactionToggleMark(isOn: isOn)
                    .padding(.top, 2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOn ? Color(red: 0.72, green: 0.78, blue: 0.62).opacity(0.14) : Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isOn ? Color(red: 0.72, green: 0.78, blue: 0.62).opacity(0.5) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .accessibilityLabel("Posture reminders")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
