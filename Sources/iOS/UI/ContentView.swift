import simd
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            routeLayer
                .id(model.route)
                .transition(reduceMotion ? .opacity : SynapseMotion.pageTransition)

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

            // Clawd floats everywhere except reaction check + Focus live
            // (during Focus live Clawd sits inside the timer ring at 50% opacity).
            if model.route != .focusReactionCheck {
                FloatingCameraPreviewView(model: model)
                if model.route != .focusLive {
                    ClawdPetOverlayView(voice: model.voiceAssistant, route: model.route)
                }
            }
        }
        .animation(reduceMotion ? nil : SynapseMotion.page, value: model.route)
        .animation(reduceMotion ? nil : SynapseMotion.easeOutHover, value: model.showBreakPointFlash)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showSettings) {
            SettingsSheet(model: model)
        }
        .sheet(isPresented: $model.showSignals) {
            SignalsView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var routeLayer: some View {
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
        case .kineticRecap:
            KineticRecapView(model: model)
        case .postureSetup:
            PostureSetupView(model: model)
        case .postureLive:
            PostureLiveView(model: model)
        case .focusSetup:
            FocusSetupView(model: model)
        case .focusReactionCheck:
            ReactionCheckView(model: model)
        case .focusLive:
            FocusLiveView(model: model)
        case .focusBreak:
            FocusBreakView(model: model)
        case .focusRecap:
            FocusRecapView(model: model)
        }
    }
}

// MARK: - Hub

struct HubView: View {
    @Bindable var model: AppModel
    @State private var revealReady = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image("BrandMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityHidden(true)
                            Text("SYNAPSE")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                        }
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
                .synapseReveal(ready: revealReady, index: 0)

                AthleteNameField(model: model)
                    .synapseReveal(ready: revealReady, index: 1)

                ModuleCard(
                    title: "Focus",
                    subtitle: "Health-aware Pomodoro · face + HR",
                    accent: .teal
                ) {
                    model.openFocus()
                }
                .synapseReveal(ready: revealReady, index: 2)

                SignalsHubCard(model: model) {
                    model.showSignals = true
                }
                .synapseReveal(ready: revealReady, index: 3)

                FocusPatternTipsCard(tips: model.patternStore.tips)
                    .synapseReveal(ready: revealReady, index: 4)

                Text("Lab")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 4)
                    .synapseReveal(ready: revealReady, index: 5)

                ModuleCard(
                    title: "Vision PVT",
                    subtitle: "Peripheral-flash oculomotor · TrueDepth saccade & arousal",
                    accent: .cyan
                ) {
                    model.openVision()
                }
                .synapseReveal(ready: revealReady, index: 6)

                ModuleCard(
                    title: "Kinetic Clock",
                    subtitle: "3D Batak · air-punch the lit pad · Watch strikes",
                    accent: .green
                ) {
                    model.openKinetic()
                }
                .synapseReveal(ready: revealReady, index: 7)

                ModuleCard(
                    title: "Posture Check",
                    subtitle: "Sit-tall baseline · front-camera upper-body drift",
                    accent: Color(red: 0.72, green: 0.78, blue: 0.62)
                ) {
                    model.openPosture()
                }
                .synapseReveal(ready: revealReady, index: 8)

                Text(firebaseLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.4))
                    .synapseReveal(ready: revealReady, index: 9)

                if let bpm = model.phoneSession.lastHeartRateBpm {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 8, height: 8)
                        Text(String(format: "Watch HR %.0f bpm", bpm))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.red.opacity(0.9))
                            .contentTransition(.numericText())
                        if !model.isWatchConnected {
                            Text("· stale?")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .synapseReveal(ready: revealReady, index: 10)
                } else if model.isWatchConnected {
                    Text("Watch HR · waiting for workout sample…")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .synapseReveal(ready: revealReady, index: 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .onAppear {
            revealReady = false
            DispatchQueue.main.async {
                revealReady = true
            }
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
        .buttonStyle(SoftPressButtonStyle())
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
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel("Settings")
    }
}

/// Hub + Settings: display name → stable `athleteId` for venue evidence logging.
struct AthleteNameField: View {
    @Bindable var model: AppModel
    var showsRecent: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Athlete")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))

            TextField("Display name", text: $model.athleteDisplayName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
                .onSubmit { model.commitAthleteDisplayName() }

            Text("Sessions write id · \(model.athleteId)")
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.4))

            if showsRecent, !model.recentAthleteNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.recentAthleteNames, id: \.self) { name in
                            Button {
                                model.selectRecentAthleteName(name)
                            } label: {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(
                                                name.caseInsensitiveCompare(model.athleteDisplayName) == .orderedSame
                                                    ? 0.22 : 0.1
                                            ))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Venue evidence") {
                    TextField("Display name", text: $model.athleteDisplayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { model.commitAthleteDisplayName() }

                    LabeledContent("athleteId") {
                        Text(model.athleteId)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if !model.recentAthleteNames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.recentAthleteNames, id: \.self) { name in
                                    Button(name) {
                                        model.selectRecentAthleteName(name)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Button("Save name") {
                        model.commitAthleteDisplayName()
                    }
                }

                Section {
                    Text("Ask before recording. Name stays on-device; Firestore sessions only get the slug athleteId (empty → athlete-1).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Focus sensing") {
                    Picker("Camera", selection: $model.focusCameraMode) {
                        ForEach(FocusCameraMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .disabled(model.focusEngine.isRunning)

                    Text(model.focusCameraMode.honestyLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Health data") {
                    LabeledContent("Heart rate history") {
                        Text(model.historicalHeartRate.statusSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Recovery · activity") {
                        Text(model.healthTrends.statusSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    Button {
                        Task {
                            _ = await model.requestHealthReadAccess()
                            await model.refreshHistoricalHeartRate()
                            await model.refreshHealthTrends()
                        }
                    } label: {
                        Label(
                            model.healthTrends.hasPromptedAuthorization
                                || model.historicalHeartRate.hasPromptedAuthorization
                                ? "Refresh from Health"
                                : "Enable Health",
                            systemImage: "heart.text.square"
                        )
                    }
                }

                Section {
                    Text("Reads resting heart rate, HRV (SDNN), sleep, steps, active energy, stand hours, and recent heart rate from Apple Health for Signals (Live · Recovery · Activity). Live Focus still prefers Watch workout samples. Wellness context for pacing — not a diagnosis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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

                Section("Demo & judging") {
                    Button {
                        model.runCannedReplay()
                        dismiss()
                    } label: {
                        Label("Seed dashboard demo session", systemImage: "square.and.arrow.up")
                    }

                    Toggle("Show 2 / 1 stage block", isOn: $model.showDemoFocusPreset)
                }

                Section {
                    Text("Seeding writes a pre-recorded Vision session to Firestore so the judge dashboard has data if the room network or Watch drops. The stage block adds a compressed 2 / 1 Focus preset to the picker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        model.commitAthleteDisplayName()
                        dismiss()
                    }
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
                         ? "Calibrated · fixate center, then Start — flashes appear in the outer pads."
                         : "Look at phone center (cell 4), then Calibrate.")
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

            VisionPVTFieldView(engine: model.visionEngine, gazeUV: model.gazeMapper.screenUV)
                .padding(.horizontal, 28)
                .padding(.vertical, 120)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                ModuleChrome(title: "Vision PVT", model: model) {
                    model.stopVisionSession()
                }
                TrackingMetersView(model: model)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                Text(model.visionEngine.statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)

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

/// 3×3 lab field: dim center fixation + peripheral flash pads (row-major cells 0…8).
struct VisionPVTFieldView: View {
    @Bindable var engine: VisionPVTEngine
    var gazeUV: SIMD2<Float>?

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 14
            let side = min(geo.size.width, geo.size.height)
            let cell = (side - gap * 2) / 3
            let originX = (geo.size.width - side) / 2
            let originY = (geo.size.height - side) / 2

            ZStack(alignment: .topLeading) {
                ForEach(0..<9, id: \.self) { index in
                    let col = index % 3
                    let row = index / 3
                    let isCenter = index == VisionPVTLayout.centerCell
                    let isFlash = engine.flashVisible && engine.activeCell == index
                    let showFixation = isCenter && engine.fixationVisible && !isFlash

                    Circle()
                        .fill(padFill(isFlash: isFlash, showFixation: showFixation, isCenter: isCenter))
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    padStroke(isFlash: isFlash, showFixation: showFixation),
                                    lineWidth: isFlash ? 2.5 : 1
                                )
                        }
                        .shadow(color: isFlash ? Color.green.opacity(0.75) : .clear, radius: isFlash ? 22 : 0)
                        .frame(width: isFlash ? cell * 0.78 : cell * (isCenter ? 0.42 : 0.55))
                        .position(
                            x: originX + CGFloat(col) * (cell + gap) + cell / 2,
                            y: originY + CGFloat(row) * (cell + gap) + cell / 2
                        )
                        .animation(.easeOut(duration: 0.07), value: isFlash)
                }

                if let uv = gazeUV, engine.isRunning {
                    Circle()
                        .fill(Color.cyan.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .shadow(color: .cyan.opacity(0.6), radius: 6)
                        .position(
                            x: originX + CGFloat(uv.x) * side,
                            y: originY + CGFloat(uv.y) * side
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func padFill(isFlash: Bool, showFixation: Bool, isCenter: Bool) -> Color {
        if isFlash { return Color.green.opacity(0.95) }
        if showFixation { return Color.white.opacity(0.55) }
        if isCenter { return Color.white.opacity(0.08) }
        return Color.white.opacity(0.06)
    }

    private func padStroke(isFlash: Bool, showFixation: Bool) -> Color {
        if isFlash { return Color.green.opacity(0.95) }
        if showFixation { return Color.white.opacity(0.7) }
        return Color.cyan.opacity(0.28)
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

                if !model.phoneSession.isConnected {
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
                            .disabled(model.isWatchCalibrating || !model.canMessageWatch)
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

    private var framingPrompt: String? {
        KineticFramingGuidance.prompt(
            facePositionCamera: model.faceTracker.facePositionCamera,
            distanceMeters: model.faceTracker.estimatedDistanceMeters
        )
    }

    private var setupHint: String {
        if model.isWatchCalibrating {
            return "Hold still · face phone · arms neutral (10s)"
        }
        if let framingPrompt {
            return framingPrompt
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

                if !model.phoneSession.isConnected {
                    WatchWarningBanner()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer()

                if let framingPrompt {
                    Text(framingPrompt)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }

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

    private var framingPrompt: String? {
        KineticFramingGuidance.prompt(
            facePositionCamera: model.faceTracker.facePositionCamera,
            distanceMeters: model.faceTracker.estimatedDistanceMeters
        )
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

                if !model.phoneSession.isConnected {
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
                            .disabled(model.isWatchCalibrating || !model.canMessageWatch)
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

                if !model.phoneSession.isConnected {
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
            if !model.phoneSession.isConnected {
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
