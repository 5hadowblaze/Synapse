import simd
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.route {
            case .hub:
                HubView(model: model)
            case .visionSetup:
                VisionSetupView(model: model)
            case .visionLive:
                VisionLiveView(model: model)
            case .kineticMainSetup:
                KineticMainSetupView(model: model)
            case .kineticMainLive:
                KineticMainLiveView(model: model)
            case .kineticDebugSetup:
                KineticSetupView(model: model)
            case .kineticDebugLive:
                KineticLiveView(model: model)
            case .focusSetup:
                FocusSetupView(model: model)
            case .focusLive:
                FocusLiveView(model: model)
            case .focusBreak:
                FocusBreakView(model: model)
            case .focusRecap:
                FocusRecapView(model: model)
            }

            if model.showBreakPointFlash {
                Color.red.opacity(0.55)
                    .ignoresSafeArea()
                    .overlay {
                        Text("BREAK-POINT")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Above routes + break-point flash so the orb stays tappable.
            VoiceAssistantOrbView(voice: model.voiceAssistant)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet(model: model)
        }
    }
}

// MARK: - Hub

struct HubView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYNAPSE")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Focus · health-aware Pomodoro")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                        Text(model.phoneSession.statusText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    SettingsGearButton { model.showSettings = true }
                }
                .padding(.top, 12)

                ModuleCard(
                    title: "Focus",
                    subtitle: "Health-aware Pomodoro · face + HR",
                    accent: .teal
                ) {
                    model.openFocus()
                }

                FocusPatternTipsCard(tips: model.patternStore.tips)

                Text("Lab")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 4)

                ModuleCard(
                    title: "Vision PVT",
                    subtitle: "Single-flash oculomotor · TrueDepth saccade & arousal",
                    accent: .cyan
                ) {
                    model.openVision()
                }

                ModuleCard(
                    title: "Kinetic Clock",
                    subtitle: "3D Batak · air-punch the lit pad · Watch strikes",
                    accent: .green
                ) {
                    model.openKinetic()
                }

                Button("Canned Replay") {
                    model.runCannedReplay()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Text(firebaseLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.4))

                if let bpm = model.phoneSession.lastHeartRateBpm {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 8, height: 8)
                        Text(String(format: "Watch HR %.0f bpm", bpm))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.red.opacity(0.9))
                        if !model.isWatchConnected {
                            Text("· stale?")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                } else if model.isWatchConnected {
                    Text("Watch HR · waiting for workout sample…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    private var firebaseLine: String {
        let mode = model.writer.isFirebaseReady ? "Firebase" : "Stub"
        return "\(mode) · pending \(model.writer.pendingWrites) · session \(model.writer.sessionId?.prefix(8) ?? "—")"
    }
}

struct ModuleCard: View {
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsGearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

struct SettingsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Kinetic") {
                    Button {
                        model.openKineticDebug()
                    } label: {
                        Label("Debug Kinetic (Test UI)", systemImage: "wrench.and.screwdriver")
                    }

                    Picker("Arm side", selection: $model.kineticArmSide) {
                        ForEach(KineticArmSide.allCases, id: \.self) { side in
                            Text(side.label).tag(side)
                        }
                    }

                    Toggle("Show face mesh on main", isOn: $model.showFaceMeshOnMain)
                }

                Section {
                    Text("Main Kinetic uses the floating 3D Batak clock. Air-punch only — no screen taps to score.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Vision

struct VisionSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: model.faceTracker.saccadeFlashToken,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ModuleChrome(title: "Vision PVT", model: model) {
                    model.returnToHub()
                }
                TrackingMetersView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Calibrate") { model.calibrateGaze() }
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                        Button("Start") { model.startVisionSession() }
                            .buttonStyle(.borderedProminent)
                    }
                    Text(model.gazeMapper.isCalibrated
                         ? "Calibrated · start when mesh + cyan ray look stable."
                         : "Look at phone center, then Calibrate.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}

struct VisionLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: model.faceTracker.saccadeFlashToken,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            // Single central flash stimulus (not a punch board).
            if model.visionEngine.flashVisible {
                Circle()
                    .fill(Color.green)
                    .frame(width: 72, height: 72)
                    .shadow(color: .green.opacity(0.7), radius: 24)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                ModuleChrome(title: "Vision PVT", model: model) {
                    model.stopVisionSession()
                }
                TrackingMetersView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Spacer()

                HStack(spacing: 12) {
                    Button("Stop") { model.stopVisionSession() }
                        .buttonStyle(.borderedProminent)
                    Button("Calibrate") { model.calibrateGaze() }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                }
                .padding(.bottom, 28)
            }
        }
    }
}

// MARK: - Kinetic main (production Batak)

struct KineticMainSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            cinematicCamera
            BatakClockSceneView(
                activeOctant: model.kineticPreviewOctant,
                facePositionCamera: model.faceTracker.facePositionCamera,
                depthMeters: 0.7
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

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

                Text("Kinetic Clock")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Text(model.hudMessage)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.green.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                if !model.isWatchConnected {
                    WatchWarningBanner()
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }

                Spacer()

                VStack(spacing: 12) {
                    Text(setupHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Button("Calibrate Watch") { model.calibrateWatch() }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .disabled(model.isWatchCalibrating || !model.isWatchConnected)
                        Button("Start") { model.startKineticSession() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var cinematicCamera: some View {
        FaceARPreviewView(
            session: model.faceTracker.session,
            isTracked: model.faceTracker.isTracking,
            saccadeFlashToken: model.faceTracker.saccadeFlashToken,
            armJoints: model.faceTracker.armJoints,
            armBones: model.faceTracker.armBones,
            faceMeshOpacity: model.showFaceMeshOnMain ? 0.22 : 0,
            showGazeRay: false,
            showTrackingRing: false,
            onAttached: { model.faceTracker.refreshPreviewAnchors() }
        )
        .ignoresSafeArea()
    }

    private var setupHint: String {
        if model.isWatchCalibrating {
            return "Hold still · face phone · arms neutral (10s)"
        }
        if model.isWatchConnected {
            return "Air-punch toward the lit pad. Watch records the strike — no screen taps."
        }
        return "Connect Apple Watch so punches register. Camera lights spokes as you aim."
    }
}

struct KineticMainLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: model.faceTracker.saccadeFlashToken,
                armJoints: model.faceTracker.armJoints,
                armBones: model.faceTracker.armBones,
                faceMeshOpacity: model.showFaceMeshOnMain ? 0.18 : 0,
                showGazeRay: false,
                showTrackingRing: false,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            BatakClockSceneView(
                activeOctant: model.kineticEngine.activeOctant,
                lastDetectedOctant: model.lastDetectedOctant ?? model.kineticPreviewOctant,
                spatialMatch: model.kineticEngine.lastSpatialMatch,
                facePositionCamera: model.faceTracker.facePositionCamera,
                depthMeters: 0.7
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Button { model.stopKineticSession() } label: {
                        Label("Hub", systemImage: "chevron.left")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    SettingsGearButton { model.showSettings = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                if !model.isWatchConnected {
                    WatchWarningBanner()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer()

                VStack(spacing: 8) {
                    Text(minimalHUD)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(model.kineticEngine.lastSpatialMatch == false ? Color.orange : Color.green)
                        .multilineTextAlignment(.center)

                    if let acc = model.kineticEngine.spatialAccuracyPercent {
                        Text(String(format: "Spatial %.0f%%", acc))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.cyan.opacity(0.85))
                    }

                    Button("Stop") { model.stopKineticSession() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var minimalHUD: String {
        let target = model.kineticEngine.activeOctant
            .flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
        let detected = model.lastDetectedOctant
            .flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
        let matchLabel: String = {
            guard let m = model.kineticEngine.lastSpatialMatch else { return "—" }
            return m ? "match" : "miss"
        }()
        return "Target \(target) · \(detected) · \(matchLabel)"
    }
}

struct WatchWarningBanner: View {
    var body: some View {
        Text("Apple Watch not connected — strikes won’t register")
            .font(.caption.weight(.bold))
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Kinetic debug (legacy Test UI)

struct KineticArmSideToggle: View {
    @Binding var selection: KineticArmSide

    var body: some View {
        Picker("Arm", selection: $selection) {
            ForEach(KineticArmSide.allCases, id: \.self) { side in
                Text(side.label).tag(side)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Arm side")
    }
}

struct KineticSetupView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: model.faceTracker.saccadeFlashToken,
                armJoints: model.faceTracker.armJoints,
                armBones: model.faceTracker.armBones,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ModuleChrome(title: "Debug Kinetic", model: model) {
                    model.returnToHub()
                }

                HStack {
                    Text("Front face + arm · camera lights spokes")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.9))
                    Spacer()
                    trackingChip
                }
                .padding(.horizontal, 24)
                .padding(.top, 6)

                KineticArmSideToggle(selection: $model.kineticArmSide)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if !model.isWatchConnected {
                    WatchWarningBanner()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer(minLength: 8)

                ClockFaceView(activeOctant: model.kineticPreviewOctant)
                    .padding(.horizontal, 36)
                    .frame(maxHeight: 280)
                    .padding(.bottom, 8)

                if let octant = model.kineticPreviewOctant,
                   let label = ClockOctant(rawValue: octant)?.label {
                    Text("Live · \(label) o’clock")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.bottom, 8)
                }

                VStack(spacing: 12) {
                    Text(setupHint)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 12) {
                        Button("Calibrate Watch") { model.calibrateWatch() }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .disabled(model.isWatchCalibrating || !model.isWatchConnected)
                        Button("Start") { model.startKineticSession() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var setupHint: String {
        if model.isWatchCalibrating {
            return "Hold still · face phone · arms neutral (10s)"
        }
        let arm = model.kineticArmSide.label.lowercased()
        if model.isWatchConnected {
            return "Point your \(arm) at spokes (camera). Calibrate Watch for strike IMU quality."
        }
        return "Point your \(arm) at spokes — face mesh + arm work without Watch. Connect Watch for strikes."
    }

    private var trackingChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(trackingOK ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(trackingLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(trackingOK ? Color.green : Color.orange)
        }
    }

    private var trackingOK: Bool {
        model.faceTracker.isTracking || model.faceTracker.isArmTracking
    }

    private var trackingLabel: String {
        if model.faceTracker.armOctant != nil { return "Cam arm" }
        if model.faceTracker.isArmTracking { return "Arm" }
        return model.faceTracker.isTracking ? "Face" : "Seek"
    }
}

struct KineticLiveView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                ModuleChrome(title: "Debug Kinetic", model: model) {
                    model.stopKineticSession()
                }

                if !model.isWatchConnected {
                    WatchWarningBanner()
                        .padding(.horizontal, 24)
                }

                KineticArmSideToggle(selection: $model.kineticArmSide)
                    .padding(.horizontal, 24)

                if let acc = model.kineticEngine.spatialAccuracyPercent {
                    Text(String(format: "Spatial accuracy %.0f%%", acc))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.cyan)
                }

                ClockFaceView(
                    activeOctant: model.kineticEngine.activeOctant,
                    lastDetectedOctant: model.lastDetectedOctant ?? model.kineticPreviewOctant,
                    spatialMatch: model.kineticEngine.lastSpatialMatch
                )
                .padding(.horizontal, 28)
                .frame(maxHeight: 360)

                spatialHUD

                Button("Stop") { model.stopKineticSession() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 28)
            }

            // Corner PIP: face mesh + arm skeleton while punching spokes.
            FaceARPreviewView(
                session: model.faceTracker.session,
                isTracked: model.faceTracker.isTracking,
                saccadeFlashToken: model.faceTracker.saccadeFlashToken,
                armJoints: model.faceTracker.armJoints,
                armBones: model.faceTracker.armBones,
                onAttached: { model.faceTracker.refreshPreviewAnchors() }
            )
            .frame(width: 120, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            )
            .padding(.trailing, 16)
            .padding(.bottom, 96)
            .allowsHitTesting(false)
        }
    }

    private var spatialHUD: some View {
        let target = model.kineticEngine.activeOctant
            .flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
        let detected = model.lastDetectedOctant
            .flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
        let matchLabel: String = {
            guard let m = model.kineticEngine.lastSpatialMatch else { return "—" }
            return m ? "match" : "miss"
        }()
        return Text("Target: \(target) · Detected: \(detected) · \(matchLabel)")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(model.kineticEngine.lastSpatialMatch == false ? Color.orange : Color.green)
            .padding(.horizontal, 24)
    }
}

// MARK: - Shared chrome

struct ModuleChrome: View {
    let title: String
    @Bindable var model: AppModel
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: back) {
                    Label("Hub", systemImage: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(model.hudMessage)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.green)
            if model.isKineticRoute {
                KineticTrackingChip(model: model)
            } else {
                FaceQualityChip(model: model)
            }
            Text(model.phoneSession.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

struct FaceQualityChip: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.faceTracker.isTracking ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(model.faceTracker.isTracking ? "Tracked" : "Lost")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.faceTracker.isTracking ? Color.green : Color.red)
            if let meters = model.faceTracker.estimatedDistanceMeters {
                Text(String(format: "· %.0f cm", Double(meters) * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            if model.gazeMapper.isCalibrated {
                Text("· calib")
                    .font(.caption2)
                    .foregroundStyle(.cyan.opacity(0.8))
            }
        }
    }
}

struct KineticTrackingChip: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            FaceQualityChip(model: model)
            if model.faceTracker.isArmTracking {
                Text("· Arm")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if let octant = model.kineticPreviewOctant ?? model.lastDetectedOctant,
               let label = ClockOctant(rawValue: octant)?.label {
                Text("· \(label)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            if !model.isWatchConnected {
                Text("· No Watch")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if let bpm = model.phoneSession.lastHeartRateBpm {
                Text(String(format: "· HR %.0f", bpm))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }
}

struct TrackingMetersView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            meter("Blink", value: model.faceTracker.eyeBlink)
            meter("Arousal", value: model.faceTracker.lastArousal ?? model.faceTracker.eyeWide)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saccade")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text(saccadeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var saccadeLabel: String {
        guard let onset = model.faceTracker.lastSaccade?.onset else { return "—" }
        let ageMs = (PhoneTime.now().seconds - onset.seconds) * 1000
        if ageMs < 2_000 {
            return String(format: "%.0f ms ago", ageMs)
        }
        return "seen"
    }

    private func meter(_ title: String, value: Float) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            ProgressView(value: Double(min(1, max(0, value))))
                .tint(.cyan)
            Text(String(format: "%.2f", value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
