import SwiftUI

enum AppRoute: Equatable, Hashable {
    case hub
    case visionSetup
    case visionLive
    /// Production Kinetic: cinematic front preview + 3D Batak clock.
    case kineticMainSetup
    case kineticMainLive
    /// Settings → Debug Kinetic (today’s mesh / arm / 2D clock UI).
    case kineticDebugSetup
    case kineticDebugLive
    /// Post Kinetic Clock summary (main or debug).
    case kineticRecap
    /// Lab: sit-tall baseline + live upper-body posture drift.
    case postureSetup
    case postureLive
    case focusSetup
    /// 60s tap-response PVT — bookends a Focus block, or runs on its own.
    case focusReactionCheck
    case focusLive
    case focusBreak
    case focusRecap
}

/// Why a reaction check is on screen.
enum ReactionCheckContext: Equatable {
    case bookendPre
    case bookendPost
    case standalone

    var stage: TapPVTStage {
        switch self {
        case .bookendPre: return .pre
        case .bookendPost: return .post
        case .standalone: return .standalone
        }
    }
}

enum KineticUIMode: Equatable {
    case main
    case debug
}

@Observable
@MainActor
final class AppModel {
    let phoneSession = PhoneSessionManager()
    let faceTracker = FaceTracker()
    let gazeMapper = GazeScreenMapper()
    let visionEngine = VisionPVTEngine()
    let kineticEngine = KineticClockEngine()
    let focusEngine = FocusEngine()
    let breathingCoach = BreathingCoach()
    let patternStore = FocusPatternStore()
    let tapPVTEngine = TapPVTEngine()
    let pvtStore = TapPVTStore()
    let writer = SessionWriter()
    /// Rolling live / last-session samples for the Signals charts screen.
    let signalStore = FocusSignalStore()
    /// Phone HealthKit history (last 24h by default). Context for Signals — not the live fade path.
    let historicalHeartRate = HistoricalHeartRateStore()
    /// Recovery / activity trends (resting HR, HRV, sleep, steps…). Display only — not fade input.
    let healthTrends = HealthTrendsStore()

    /// Hallway-demo display name (UserDefaults). Empty → sessions use `athlete-1`.
    var athleteDisplayName: String = UserDefaults.standard.string(forKey: AthleteIdentity.displayNameKey) ?? "" {
        didSet {
            UserDefaults.standard.set(athleteDisplayName, forKey: AthleteIdentity.displayNameKey)
        }
    }

    /// Recent display names for fast venue switching (max 8).
    var recentAthleteNames: [String] = UserDefaults.standard.stringArray(forKey: AthleteIdentity.recentNamesKey) ?? [] {
        didSet {
            UserDefaults.standard.set(recentAthleteNames, forKey: AthleteIdentity.recentNamesKey)
        }
    }

    /// Stable Firestore `athleteId` — slug of `athleteDisplayName`, or `athlete-1` if empty.
    /// SCHEMA has no displayName field; only this id is written on sessions.
    var athleteId: String {
        AthleteIdentity.athleteId(forDisplayName: athleteDisplayName)
    }

    var hudMessage = "Synapse"
    var showBreakPointFlash = false
    var route: AppRoute = .hub
    var lastDetectedOctant: Int?
    var isWatchCalibrating = false
    /// True after a successful Calibrate Watch on this phone session.
    var watchIMUCalibrated = false
    /// Live Watch pointing octant (optional corroboration / strike spatial).
    var watchLiveOctant: Int?
    var showSettings = false
    /// Live / last-session Signals charts sheet (Hub + Focus entry).
    var showSignals = false
    /// Which Kinetic surface is active (main vs debug) for start/stop routing.
    private(set) var kineticUIMode: KineticUIMode = .main
    /// Last Focus recap (shown on focusRecap).
    var lastFocusRecap: FocusRecap?
    /// Last Kinetic Clock recap (shown on kineticRecap).
    var lastKineticRecap: KineticRecap?
    var selectedFocusPreset: FocusPreset = .standard
    /// Wall-clock start of the current Focus block (for pattern hour).
    private(set) var focusSessionStartedAt: Date?
    /// Show Lock-in CTA after a completed breathing reset.
    var showLockInTenCTA = false
    /// Pre-block reaction check, held until the post check closes the pair.
    private(set) var pendingPreReaction: TapPVTResult?
    /// Pre/post pair for the current recap.
    private(set) var lastReactionComparison: TapPVTComparison?
    /// Most recent standalone check (voice / Lab entry point).
    private(set) var lastStandaloneReaction: TapPVTResult?
    private(set) var reactionContext: ReactionCheckContext = .standalone
    private var reactionReturnRoute: AppRoute = .hub
    /// Floating voice assistant (ElevenLabs Conversational Agent).
    let voiceAssistant = VoiceAssistantController()

    private static let kineticArmSideKey = "synapse.kineticArmSide"
    private static let showFaceMeshOnMainKey = "synapse.showFaceMeshOnMain"
    private static let showDemoFocusPresetKey = "synapse.showDemoFocusPreset"
    private static let reactionBookendKey = "synapse.reactionCheckBookend"
    private static let postureRemindersKey = "synapse.postureReminders"
    private static let postureBaselineKey = "synapse.postureBaseline"
    private static let focusCameraModeKey = "synapse.focusCameraMode"
    private static let previewCameraEnabledKey = "synapse.previewCameraEnabled"
    private static let previewOriginXKey = "synapse.previewOriginNormX"
    private static let previewOriginYKey = "synapse.previewOriginNormY"

    /// Soft Focus posture reminders (parallel to fade — never weights break score).
    var postureRemindersEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "synapse.postureReminders") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "synapse.postureReminders")
    }() {
        didSet {
            UserDefaults.standard.set(postureRemindersEnabled, forKey: Self.postureRemindersKey)
        }
    }

    /// Shared Lab / Focus posture drift detector (front-camera upper-body proxy).
    private var postureDetector = PostureDriftDetector()
    /// Live Lab / Focus posture score 0…1.
    private(set) var postureLiveScore: Double = 0
    private(set) var postureBaselineReady = false
    private(set) var postureBaselineProgress: Double = 0
    /// Soft HUD flash while a posture nudge is showing (~5 s).
    private(set) var postureNudgeVisible = false
    private var postureNudgeClearTask: Task<Void, Never>?
    private var didAnnouncePostureBaseline = false
    /// One-shot sit-tall prompt while Focus/Lab posture baseline is collecting.
    private var didPromptPostureBaselineCollecting = false

    /// Floating specular preview preference (independent of `focusCameraMode`).
    /// Default on — desk accessory; chrome stays when toggled off.
    var previewCameraEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "synapse.previewCameraEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "synapse.previewCameraEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(previewCameraEnabled, forKey: Self.previewCameraEnabledKey)
            reconcileFaceTracker()
        }
    }

    /// Normalized top-leading origin (0…1) within the safe drag area. Default bottom-leading.
    var previewOriginNormX: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "synapse.previewOriginNormX") == nil { return 0 }
        return defaults.double(forKey: "synapse.previewOriginNormX")
    }()
    var previewOriginNormY: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "synapse.previewOriginNormY") == nil { return 1 }
        return defaults.double(forKey: "synapse.previewOriginNormY")
    }()

    /// Transient peek during a Watch-only Focus live block — does not rewrite `focusCameraMode`
    /// or the persistent `previewCameraEnabled` preference.
    private(set) var previewPeekDuringWatchOnly = false

    /// Drag gesture base (UI-only; not persisted).
    var previewDragBaseOrigin: CGPoint?

    /// Persist name into the recent list (call on submit / Done — not every keystroke).
    func commitAthleteDisplayName() {
        let trimmed = athleteDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        athleteDisplayName = trimmed
        recentAthleteNames = AthleteIdentity.updatedRecentNames(
            existing: recentAthleteNames,
            promoting: trimmed
        )
    }

    func selectRecentAthleteName(_ name: String) {
        athleteDisplayName = name
        commitAthleteDisplayName()
    }

    /// Bookend the Focus block with a 60s tap PVT. Opt-in at Focus setup.
    var reactionCheckBookendEnabled: Bool = UserDefaults.standard.bool(forKey: "synapse.reactionCheckBookend") {
        didSet {
            UserDefaults.standard.set(reactionCheckBookendEnabled, forKey: Self.reactionBookendKey)
        }
    }

    /// Focus camera policy. Default always-on for the demo; Watch-only is the accessibility path.
    var focusCameraMode: FocusCameraMode = {
        if let raw = UserDefaults.standard.string(forKey: "synapse.focusCameraMode"),
           let mode = FocusCameraMode(rawValue: raw) {
            return mode
        }
        return .alwaysOn
    }() {
        didSet {
            guard oldValue != focusCameraMode else { return }
            UserDefaults.standard.set(focusCameraMode.rawValue, forKey: Self.focusCameraModeKey)
            applyFocusCameraMode()
        }
    }

    /// Live chip: Camera on / Checking in / Camera off.
    private(set) var focusCameraPresence: FocusCameraPresence = .cameraOff
    private(set) var focusCameraScheduler = FocusCameraScheduler()
    private var focusCameraTickTask: Task<Void, Never>?
    /// Samples FocusEngine + Watch channels into `signalStore` while a block is live.
    private var signalSampleTask: Task<Void, Never>?

    /// Whether the live Focus HUD should attach the AR preview right now.
    var focusUsesCamera: Bool { focusCameraPresence.isAwake }

    /// Watch-only Focus block is live — camera policy owns presence; preview must not auto-start.
    var isWatchOnlyFocusLive: Bool {
        focusEngine.isRunning && focusCameraMode == .watchOnly
    }

    /// Preview wants a face session (persistent pref, or mid-block Watch-only peek).
    var isPreviewFaceRequested: Bool {
        if isWatchOnlyFocusLive {
            return previewPeekDuringWatchOnly
        }
        return previewCameraEnabled
    }

    /// Floating bubble shows live camera chrome when the user requested preview on.
    var isPreviewCameraActive: Bool { isPreviewFaceRequested }

    /// Surfaces the compressed 2 / 1 stage block in the Focus picker. Off by default so the
    /// shipping picker only shows blocks worth saying out loud.
    var showDemoFocusPreset: Bool = UserDefaults.standard.bool(forKey: "synapse.showDemoFocusPreset") {
        didSet {
            UserDefaults.standard.set(showDemoFocusPreset, forKey: Self.showDemoFocusPresetKey)
            if !showDemoFocusPreset, selectedFocusPreset == .demo {
                selectedFocusPreset = .quick
            }
        }
    }

    /// Presets offered on the Focus setup screen.
    var availableFocusPresets: [FocusPreset] {
        showDemoFocusPreset ? FocusPreset.allIncludingDemo : FocusPreset.all
    }

    /// Athlete arm for Kinetic overlay + camera pointing (persisted). Default: right.
    var kineticArmSide: KineticArmSide = {
        if let raw = UserDefaults.standard.string(forKey: "synapse.kineticArmSide"),
           let side = KineticArmSide(rawValue: raw) {
            return side
        }
        return .right
    }() {
        didSet {
            guard oldValue != kineticArmSide else { return }
            UserDefaults.standard.set(kineticArmSide.rawValue, forKey: Self.kineticArmSideKey)
            faceTracker.setPreferredArmSide(kineticArmSide)
        }
    }

    /// Low-opacity face mesh on main Kinetic (persisted). Full white mesh stays in Debug.
    var showFaceMeshOnMain: Bool = UserDefaults.standard.object(forKey: "synapse.showFaceMeshOnMain") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showFaceMeshOnMain, forKey: Self.showFaceMeshOnMainKey)
        }
    }

    /// Spoke highlight — prefer front-camera arm; Watch is optional fallback.
    var kineticPreviewOctant: Int? {
        faceTracker.armOctant ?? watchLiveOctant ?? phoneSession.lastLiveOctant
    }

    /// Watch companion linked for strikes (reachability + recent WC traffic / app context).
    var isWatchConnected: Bool {
        phoneSession.isConnected
    }

    /// Paired Watch app present — calibrate / live-direction can be queued even if not reachable yet.
    var canMessageWatch: Bool {
        phoneSession.canMessageWatch
    }

    var isKineticRoute: Bool {
        switch route {
        case .kineticMainSetup, .kineticMainLive, .kineticDebugSetup, .kineticDebugLive:
            return true
        default:
            return false
        }
    }

    var isKineticLiveRoute: Bool {
        route == .kineticMainLive || route == .kineticDebugLive
    }

    var isVisionRoute: Bool {
        route == .visionSetup || route == .visionLive
    }

    var isVisionLiveRoute: Bool {
        route == .visionLive
    }

    var isFocusRoute: Bool {
        switch route {
        case .focusSetup, .focusReactionCheck, .focusLive, .focusBreak, .focusRecap:
            return true
        default:
            return false
        }
    }

    func bootstrap() {
        wireCallbacks()
        voiceAssistant.attach(to: self)
        faceTracker.setPreferredArmSide(kineticArmSide)
        reconcileFaceTracker()
        breathingCoach.onComplete = { [weak self] in
            guard let self else { return }
            self.showLockInTenCTA = true
            self.hudMessage = "Reset complete · lock in 10?"
            // Natural complete left the break paused for breathing — resume so the timer continues.
            if self.focusEngine.phase == .onBreak, self.focusEngine.isPaused {
                self.focusEngine.resume()
            }
        }
    }

    // MARK: - Hub

    /// Stop Focus/breathing before leaving so fade/break/complete callbacks cannot hijack another module.
    private func stopFocusBeforeRouteChange() {
        breathingCoach.stop()
        showLockInTenCTA = false
        tapPVTEngine.cancel()
        pendingPreReaction = nil
        stopFocusSession(returnToSetup: false)
    }

    func openVision() {
        stopFocusBeforeRouteChange()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.setPostureEnabled(false)
        faceTracker.ensureStarted()
        route = .visionSetup
        hudMessage = "Vision PVT"
        voiceAssistant.handleRouteChange(route)
    }

    /// Production Kinetic (cinematic Batak clock).
    func openKinetic() {
        stopFocusBeforeRouteChange()
        kineticUIMode = .main
        faceTracker.setPostureEnabled(false)
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.refreshSessionState()
        phoneSession.sendLiveDirectionStart()
        route = .kineticMainSetup
        hudMessage = isWatchConnected
            ? "Punch the lit pad · Watch for strikes"
            : "Punch the lit pad · connect Watch for strikes"
        voiceAssistant.handleRouteChange(route)
    }

    /// Settings → Debug Kinetic (unchanged mesh / arm / 2D clock UI).
    func openKineticDebug() {
        stopFocusBeforeRouteChange()
        showSettings = false
        kineticUIMode = .debug
        faceTracker.setPostureEnabled(false)
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.refreshSessionState()
        phoneSession.sendLiveDirectionStart()
        route = .kineticDebugSetup
        hudMessage = isWatchConnected
            ? "Debug · face + arm · Watch for strikes"
            : "Debug · face + arm · Watch optional for strikes"
        voiceAssistant.handleRouteChange(route)
    }

    func openPosture() {
        stopFocusBeforeRouteChange()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.setPostureEnabled(true)
        faceTracker.ensureStarted()
        route = .postureSetup
        hudMessage = "Posture Check · sit tall"
        voiceAssistant.handleRouteChange(route)
    }

    func openFocus() {
        stopFocusBeforeRouteChange()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.setPostureEnabled(false)
        phoneSession.sendLiveDirectionStop()
        route = .focusSetup
        applyFocusCameraMode()
        switch focusCameraMode {
        case .watchOnly:
            hudMessage = "Focus · Watch only"
        case .briefCheckIns:
            hudMessage = "Focus · brief camera"
        case .alwaysOn:
            hudMessage = "Focus · health-aware Pomodoro"
        }
        voiceAssistant.handleRouteChange(route)
    }

    /// Start / stop FaceTracker to match `focusCameraMode` while on Focus setup (not live).
    func applyFocusCameraMode() {
        faceTracker.setArmPoseEnabled(false)
        if !focusEngine.isRunning {
            faceTracker.setPostureEnabled(false)
        }
        // Live brief scheduling owns the camera — don't fight it from setup apply.
        if focusEngine.isRunning, focusCameraMode == .briefCheckIns {
            syncFaceTrackerToPresence()
            return
        }
        switch focusCameraMode {
        case .alwaysOn:
            focusCameraPresence = .cameraOn
        case .briefCheckIns, .watchOnly:
            focusCameraPresence = .cameraOff
            if focusEngine.isRunning {
                focusEngine.ingestArousal(nil)
            }
        }
        reconcileFaceTracker()
    }

    /// Voice / Settings entry — rejects mid-block flips so sensing mid-session stays coherent.
    @discardableResult
    func setFocusCameraMode(_ mode: FocusCameraMode) -> Bool {
        if focusEngine.isRunning, mode != focusCameraMode {
            hudMessage = "End focus to change camera mode"
            return false
        }
        focusCameraMode = mode
        return true
    }

    /// Tap on the floating preview — toggles preview camera without rewriting Focus policy.
    func togglePreviewCamera() {
        if isWatchOnlyFocusLive {
            previewPeekDuringWatchOnly.toggle()
        } else {
            previewCameraEnabled.toggle()
            return // didSet already reconciles
        }
        reconcileFaceTracker()
    }

    func previewOrigin(in size: CGSize, safe: EdgeInsets, bubble: CGSize) -> CGPoint {
        let pad: CGFloat = 16
        let minX = safe.leading + pad
        let minY = safe.top + pad
        // Keep clear of the voice orb (bottom-trailing).
        let maxX = size.width - safe.trailing - pad - bubble.width
        let maxY = size.height - safe.bottom - pad - bubble.height - 12
        let spanX = max(0, maxX - minX)
        let spanY = max(0, maxY - minY)
        let x = minX + spanX * CGFloat(min(1, max(0, previewOriginNormX)))
        let y = minY + spanY * CGFloat(min(1, max(0, previewOriginNormY)))
        return CGPoint(x: x, y: y)
    }

    func setPreviewOrigin(_ origin: CGPoint, in size: CGSize, safe: EdgeInsets) {
        let bubble = CGSize(width: 108, height: 144)
        let pad: CGFloat = 16
        let minX = safe.leading + pad
        let minY = safe.top + pad
        let maxX = size.width - safe.trailing - pad - bubble.width
        let maxY = size.height - safe.bottom - pad - bubble.height - 12
        let spanX = max(1, maxX - minX)
        let spanY = max(1, maxY - minY)
        let clampedX = min(max(origin.x, minX), maxX)
        let clampedY = min(max(origin.y, minY), maxY)
        previewOriginNormX = Double((clampedX - minX) / spanX)
        previewOriginNormY = Double((clampedY - minY) / spanY)
    }

    func persistPreviewOrigin() {
        UserDefaults.standard.set(previewOriginNormX, forKey: Self.previewOriginXKey)
        UserDefaults.standard.set(previewOriginNormY, forKey: Self.previewOriginYKey)
    }

    private func startFocusCameraRuntime() {
        stopFocusCameraRuntime()
        let now = ProcessInfo.processInfo.systemUptime
        focusCameraScheduler.start(mode: focusCameraMode, now: now)
        focusCameraPresence = focusCameraScheduler.presence
        if focusCameraMode == .watchOnly {
            // Don't auto-start face against Watch-only policy; user may peek via preview.
            previewPeekDuringWatchOnly = false
        }
        syncFaceTrackerToPresence()
        if focusCameraMode == .alwaysOn {
            faceTracker.resetDetectors()
        }

        guard focusCameraMode == .briefCheckIns else { return }
        focusCameraTickTask = Task { @MainActor [weak self] in
            while let self, self.focusEngine.isRunning, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, self.focusEngine.isRunning else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if self.focusCameraScheduler.tick(now: now) {
                    self.focusCameraPresence = self.focusCameraScheduler.presence
                    self.syncFaceTrackerToPresence()
                }
            }
        }
    }

    private func stopFocusCameraRuntime() {
        focusCameraTickTask?.cancel()
        focusCameraTickTask = nil
        focusCameraScheduler.stop()
        previewPeekDuringWatchOnly = false
        if !focusEngine.isRunning {
            // Presence restored by applyFocusCameraMode on setup return.
        }
    }

    private func syncFaceTrackerToPresence() {
        faceTracker.setArmPoseEnabled(false)
        let postureOn = focusEngine.isRunning
            && postureRemindersEnabled
            && focusCameraMode != .watchOnly
            && focusCameraPresence.isAwake
        faceTracker.setPostureEnabled(postureOn)
        if focusCameraPresence.isAwake {
            if focusCameraPresence == .checkingIn {
                faceTracker.resetDetectors()
            }
        } else if focusEngine.isRunning {
            // Keep fade math honest when Focus presence is asleep — even if preview holds the session.
            focusEngine.ingestArousal(nil)
        }
        reconcileFaceTracker()
    }

    /// Single owner for FaceTracker start/stop across Focus presence, floating preview, and lab routes.
    func reconcileFaceTracker() {
        if shouldRunFaceTracker {
            faceTracker.ensureStarted()
        } else {
            faceTracker.stop()
        }
    }

    private var shouldRunFaceTracker: Bool {
        if focusCameraPresence.isAwake { return true }
        if isPreviewFaceRequested { return true }
        switch route {
        case .visionSetup, .visionLive,
             .kineticMainSetup, .kineticMainLive,
             .kineticDebugSetup, .kineticDebugLive,
             .postureSetup, .postureLive:
            // Lab modules need the shared face session regardless of preview chrome.
            return true
        default:
            return false
        }
    }

    private func noteFocusHeartRateForCamera(_ bpm: Double) {
        guard focusEngine.isRunning, focusCameraMode == .briefCheckIns else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if focusCameraScheduler.ingestHeartRate(
            bpm: bpm,
            anchorBpm: focusEngine.hrAnchorBpm,
            now: now
        ) {
            focusCameraPresence = focusCameraScheduler.presence
            syncFaceTrackerToPresence()
        }
    }

    func returnToHub() {
        visionEngine.stopSession()
        kineticEngine.stopSession()
        clearPostureNudge()
        breathingCoach.stop()
        showLockInTenCTA = false
        tapPVTEngine.cancel()
        pendingPreReaction = nil
        stopFocusSession(returnToSetup: false)
        phoneSession.sendLiveDirectionStop()
        phoneSession.sendMotionEnergyStop()
        watchLiveOctant = nil
        faceTracker.setArmPoseEnabled(false)
        faceTracker.setPostureEnabled(false)
        faceTracker.ensureStarted()
        route = .hub
        hudMessage = "Synapse"
        voiceAssistant.handleRouteChange(route)
        reconcileFaceTracker()
    }

    // MARK: - Posture Check (Lab)

    func startPostureSession() {
        commitAthleteDisplayName()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.setPostureEnabled(true)
        faceTracker.ensureStarted()
        // Lab keeps the short ~10 s baseline (80 samples @ ~8 Hz) + Lab sustain/cooldown.
        postureDetector.reset(
            baselineSamples: PostureDriftDetector.labBaselineSamples,
            cooldownSeconds: PostureDriftDetector.defaultCooldownSeconds,
            samplesToFire: PostureDriftDetector.defaultSamplesToFire
        )
        didAnnouncePostureBaseline = false
        didPromptPostureBaselineCollecting = false
        clearPostureNudge()
        postureLiveScore = 0
        postureBaselineReady = false
        postureBaselineProgress = 0
        route = .postureLive
        hudMessage = "Sit tall · learning baseline"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Posture Check")
    }

    func stopPostureSession() {
        clearPostureNudge()
        faceTracker.setPostureEnabled(false)
        route = .postureSetup
        hudMessage = "Posture Check"
        voiceAssistant.handleRouteChange(route)
    }

    /// Fresh Focus-length sit-tall baseline — never silently reuse a short Lab snapshot.
    private func preparePostureForFocus() {
        clearPostureNudge()
        didAnnouncePostureBaseline = false
        didPromptPostureBaselineCollecting = false
        postureDetector.reset(
            baselineSamples: PostureDriftDetector.focusBaselineSamples,
            cooldownSeconds: PostureDriftDetector.focusCooldownSeconds,
            samplesToFire: PostureDriftDetector.focusSamplesToFire
        )
        postureBaselineReady = false
        postureBaselineProgress = 0
        postureLiveScore = 0
    }

    /// Speak sit-tall once when Focus starts collecting (camera awake, reminders on, not Watch-only).
    private func maybePromptPostureBaselineCollectingForFocus() {
        guard postureRemindersEnabled else { return }
        guard focusCameraMode != .watchOnly else { return }
        guard focusUsesCamera else { return }
        guard !postureBaselineReady else { return }
        guard !didPromptPostureBaselineCollecting else { return }
        didPromptPostureBaselineCollecting = true
        voiceAssistant.notifyPostureBaselineCollecting()
    }

    private func ingestPostureFeatures(
        _ features: PostureFeatures?,
        joints: [PostureOverlayJoint],
        bones: [(CGPoint, CGPoint)]
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let wasReady = postureDetector.isBaselineReady
        let result = postureDetector.ingest(
            now: now,
            features: features,
            joints: joints,
            bones: bones
        )
        postureLiveScore = result.sample.postureScore
        postureBaselineReady = postureDetector.isBaselineReady
        postureBaselineProgress = postureDetector.baselineProgress

        let inLab = route == .postureLive
        let inFocus = focusEngine.isRunning
            && postureRemindersEnabled
            && focusUsesCamera
            && focusCameraMode != .watchOnly

        // Brief check-ins: camera may wake after Focus start — prompt once when collecting begins.
        if inFocus, !wasReady, !postureBaselineReady {
            maybePromptPostureBaselineCollectingForFocus()
        }

        if !wasReady, postureDetector.isBaselineReady {
            persistPostureBaseline()
            if !didAnnouncePostureBaseline {
                didAnnouncePostureBaseline = true
                if inLab {
                    hudMessage = "Baseline set · watching drift"
                    voiceAssistant.notifyPostureBaselineSet()
                } else if inFocus {
                    voiceAssistant.notifyPostureBaselineSet()
                }
            }
        }

        guard inLab || inFocus else { return }

        if result.fired {
            showPostureNudge()
            voiceAssistant.notifyPostureDrift()
        }
    }

    private func showPostureNudge() {
        postureNudgeVisible = true
        if route == .postureLive || route == .focusLive {
            hudMessage = "Ease your posture"
        }
        postureNudgeClearTask?.cancel()
        postureNudgeClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.postureNudgeVisible = false
        }
    }

    private func clearPostureNudge() {
        postureNudgeClearTask?.cancel()
        postureNudgeClearTask = nil
        postureNudgeVisible = false
    }

    private func persistPostureBaseline() {
        guard let snap = postureDetector.exportedBaseline else { return }
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.postureBaselineKey)
        }
    }

    // MARK: - Vision PVT

    func startVisionSession() {
        commitAthleteDisplayName()
        faceTracker.setArmPoseEnabled(false)
        faceTracker.ensureStarted()
        _ = writer.startSession(
            athleteId: athleteId,
            module: .visionPvt,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        faceTracker.resetDetectors()
        visionEngine.startSession()
        route = .visionLive
        hudMessage = "Vision live"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Vision PVT")
    }

    func stopVisionSession() {
        visionEngine.stopSession()
        writer.completeSession()
        route = .visionSetup
        hudMessage = "Vision stopped"
        voiceAssistant.handleRouteChange(route)
    }

    func calibrateGaze() {
        guard let lookAt = faceTracker.latestGaze?.lookAt else {
            hudMessage = "Calibrate needs face"
            return
        }
        gazeMapper.calibrateToCenter(lookAt: lookAt)
        hudMessage = "Gaze calibrated"
    }

    // MARK: - Kinetic Clock

    func calibrateWatch() {
        isWatchCalibrating = true
        watchIMUCalibrated = false
        phoneSession.sendCalibrateStart(durationSeconds: 10)
        hudMessage = "Watch calibrating 10s — face phone, arms neutral"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard self.isWatchCalibrating else { return }
            // No ACK from Watch — do not falsely mark success.
            self.isWatchCalibrating = false
            self.hudMessage = "Watch calibrate timed out — retry"
        }
    }

    func startKineticSession() {
        commitAthleteDisplayName()
        lastKineticRecap = nil
        faceTracker.ensureStarted()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        _ = writer.startSession(
            athleteId: athleteId,
            module: .kineticClock,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        kineticEngine.startSession()
        route = kineticUIMode == .debug ? .kineticDebugLive : .kineticMainLive
        hudMessage = "Kinetic live"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Kinetic Clock")
    }

    func stopKineticSession() {
        let hadTrials = !kineticEngine.trials.isEmpty
        let recap = kineticEngine.makeRecap(completedNaturally: false)
        kineticEngine.stopSession()
        writer.completeSession()
        faceTracker.setArmPoseEnabled(true)
        phoneSession.sendLiveDirectionStart()
        if hadTrials {
            finishKineticToRecap(recap)
        } else {
            route = kineticUIMode == .debug ? .kineticDebugSetup : .kineticMainSetup
            hudMessage = kineticUIMode == .debug
                ? "Kinetic stopped · camera arm lights spokes"
                : "Kinetic stopped · air-punch the lit pad"
            voiceAssistant.handleRouteChange(route)
        }
    }

    /// Done → hub; Run again → matching Kinetic setup (main or debug).
    func runKineticAgainFromRecap() {
        if kineticUIMode == .debug {
            openKineticDebug()
        } else {
            openKinetic()
        }
    }

    private func finishKineticToRecap(_ recap: KineticRecap) {
        lastKineticRecap = recap
        route = .kineticRecap
        let acc = recap.accuracyLabel
        hudMessage = "Kinetic complete · spatial \(acc)"
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionComplete(summary: recap.voiceSummary)
    }

    // MARK: - Reaction check (tap PVT bookend)

    /// Focus setup CTA. With the bookend on, the pre-block check runs first.
    func beginFocusFlow() {
        guard reactionCheckBookendEnabled, !focusEngine.isRunning else {
            startFocusSession()
            return
        }
        pendingPreReaction = nil
        lastReactionComparison = nil
        startReactionCheck(context: .bookendPre)
    }

    /// Standalone check from voice or the Lab. Refused while a Focus block is live so it
    /// can never interrupt a running session.
    @discardableResult
    func startStandaloneReactionCheck() -> Bool {
        guard !focusEngine.isRunning else { return false }
        reactionReturnRoute = route == .focusReactionCheck ? .hub : route
        startReactionCheck(context: .standalone)
        return true
    }

    /// Whole-screen tap during a check.
    func registerReactionTap() {
        tapPVTEngine.registerTap()
    }

    /// User backed out. Skipping the check never blocks the Focus flow.
    func cancelReactionCheck() {
        tapPVTEngine.cancel()
        switch reactionContext {
        case .bookendPre:
            pendingPreReaction = nil
            startFocusSession()
        case .bookendPost:
            pendingPreReaction = nil
            finalizeFocusRecap(lastFocusRecap ?? focusEngine.makeRecap())
        case .standalone:
            route = reactionReturnRoute
            hudMessage = "Reaction check skipped"
            voiceAssistant.handleRouteChange(route)
        }
    }

    private func startReactionCheck(context: ReactionCheckContext) {
        reactionContext = context
        breathingCoach.stop()
        showLockInTenCTA = false
        // The coach stays silent for 60 seconds — the test is the measurement.
        voiceAssistant.cancel()
        route = .focusReactionCheck
        hudMessage = context.stage.title
        voiceAssistant.handleRouteChange(route)
        tapPVTEngine.start(stage: context.stage)
    }

    private func handleReactionResult(_ result: TapPVTResult) {
        switch reactionContext {
        case .bookendPre:
            pendingPreReaction = result
            if startFocusSession() {
                // Session doc exists only after the Focus start — write the pre check into it.
                writer.writeTapPVT(result)
            } else {
                route = .focusSetup
                voiceAssistant.handleRouteChange(route)
            }

        case .bookendPost:
            let recap = lastFocusRecap ?? focusEngine.makeRecap()
            if let pre = pendingPreReaction {
                let comparison = TapPVTComparison(pre: pre, post: result)
                lastReactionComparison = comparison
                pvtStore.recordBookend(pre: pre, post: result)
                writer.writeTapPVT(result)
                writer.writeTapPVTComparison(comparison)
            }
            pendingPreReaction = nil
            finalizeFocusRecap(recap)

        case .standalone:
            lastStandaloneReaction = result
            pvtStore.recordStandalone(result)
            route = reactionReturnRoute
            hudMessage = "Reaction \(result.medianLabel) ms · \(result.lapseCount) lapses"
            voiceAssistant.handleRouteChange(route)
            voiceAssistant.notifySessionComplete(
                summary: "Reaction check done. Median \(result.medianLabel) milliseconds, \(result.lapseCount) lapses."
            )
        }
    }

    // MARK: - Focus (desk Pomodoro)

    /// Starts Focus. Returns `false` if a session is already live (no restart / no orphaned Firestore write).
    @discardableResult
    func startFocusSession(focusMinutes: Int? = nil, breakMinutes: Int? = nil) -> Bool {
        if focusEngine.isRunning {
            hudMessage = "Focus already live"
            return false
        }
        commitAthleteDisplayName()
        breathingCoach.stop()
        showLockInTenCTA = false
        faceTracker.setArmPoseEnabled(false)
        phoneSession.sendLiveDirectionStop()
        phoneSession.sendMotionEnergyStart()

        let focus = focusMinutes ?? selectedFocusPreset.focusMinutes
        let brk = breakMinutes ?? selectedFocusPreset.breakMinutes
        // Explicit minutes (voice / lock-in) have no preset, so infer the baseline length.
        let samples = focusMinutes == nil
            ? selectedFocusPreset.baselineSamples
            : FocusEngine.inferredBaselineSamples(focusMinutes: focus)
        focusEngine.configure(focusMinutes: focus, breakMinutes: brk, baselineSamples: samples)

        preparePostureForFocus()

        _ = writer.startSession(
            athleteId: athleteId,
            module: .focusDesk,
            clockOffsetMs: phoneSession.lastSyncOffsetMs,
            clockRttMs: phoneSession.lastSyncRttMs
        )
        if let sid = writer.sessionId {
            writer.publishLiveFocusPointer(sessionId: sid)
        }
        // Seed session doc with the last Watch sample so the dashboard isn't blank until the next WC tick.
        if let event = phoneSession.lastHeartRateEvent {
            writer.updateHeartRate(event)
        } else if let bpm = phoneSession.lastHeartRateBpm {
            let now = ProcessInfo.processInfo.systemUptime
            writer.updateHeartRate(
                HeartRateEvent(
                    bpm: bpm,
                    watchTimestamp: now,
                    phoneTimestamp: now,
                    hkStart: nil,
                    hkEnd: nil,
                    source: "phoneCache"
                )
            )
        }
        lastFocusRecap = nil
        focusSessionStartedAt = Date()
        focusEngine.startSession(focusMinutes: focus, breakMinutes: brk, baselineSamples: samples)
        startFocusCameraRuntime()
        // After presence sync: enable posture when camera is awake and reminders are on.
        if postureRemindersEnabled, focusCameraMode != .watchOnly, focusCameraPresence.isAwake {
            faceTracker.setPostureEnabled(true)
        }
        beginSignalSampling()
        if !focusCameraPresence.isAwake {
            focusEngine.ingestArousal(nil)
        }
        if let bpm = phoneSession.lastHeartRateBpm {
            focusEngine.ingestHeartRate(bpm)
            noteFocusHeartRateForCamera(bpm)
        }
        route = .focusLive
        switch focusCameraMode {
        case .watchOnly:
            hudMessage = "Focus live · Watch only"
        case .briefCheckIns:
            hudMessage = "Focus live · brief camera"
        case .alwaysOn:
            hudMessage = "Focus live"
        }
        // Cancel agent session for Focus quiet — then one-shot sit-tall if baseline is collecting.
        voiceAssistant.handleRouteChange(route)
        voiceAssistant.notifySessionStarted(module: "Focus")
        maybePromptPostureBaselineCollectingForFocus()
        return true
    }

    func stopFocusSession(returnToSetup: Bool = true) {
        breathingCoach.stop()
        showLockInTenCTA = false
        clearPostureNudge()
        faceTracker.setPostureEnabled(false)
        phoneSession.sendMotionEnergyStop()
        stopFocusCameraRuntime()
        endSignalSampling()
        if focusEngine.isRunning || focusEngine.phase == .complete {
            // Suppress recap when leaving to hub / setup cancel.
            focusEngine.onComplete = nil
            focusEngine.stopSession(emitComplete: false)
            writer.completeSession()
            wireFocusCallbacks()
        }
        if returnToSetup {
            route = .focusSetup
            applyFocusCameraMode()
            hudMessage = "Focus stopped"
            voiceAssistant.handleRouteChange(route)
        }
    }

    /// Ends a live Focus block into recap. No-ops if nothing is running (avoids fake-zero recaps).
    @discardableResult
    func endFocusToRecap() -> Bool {
        breathingCoach.stop()
        showLockInTenCTA = false
        phoneSession.sendMotionEnergyStop()
        stopFocusCameraRuntime()
        endSignalSampling()
        guard focusEngine.isRunning else {
            hudMessage = "No focus session"
            return false
        }
        focusEngine.stopSession(emitComplete: true)
        return true
    }

    func acceptFocusBreak() {
        focusEngine.startBreak()
    }

    func skipFocusBreak() {
        breathingCoach.stop()
        focusEngine.skipBreak()
    }

    func extendFocusBlock() {
        breathingCoach.stop()
        showLockInTenCTA = false
        let wasBreak = focusEngine.phase == .onBreak
        if focusEngine.extendFocus() {
            if wasBreak || route == .focusBreak {
                route = .focusLive
                voiceAssistant.handleRouteChange(route)
            }
            hudMessage = "Extended +5m"
        }
    }

    func pauseFocus() {
        focusEngine.pause()
        hudMessage = "Paused"
    }

    func resumeFocus() {
        focusEngine.resume()
        hudMessage = focusEngine.phase == .onBreak ? "Break" : "Focus live"
    }

    /// Agent-guided inhale/hold/exhale on the break screen (~2–3 min).
    /// - Parameter startAgent: when true (user CTA), start breath-mode conversation.
    ///   Tool `start_breathing` passes false so the agent already speaking isn't restarted.
    func startBreathingReset(startAgent: Bool = true, cycles: Int? = nil) {
        if focusEngine.phase == .focusing || focusEngine.phase == .breakSuggested {
            acceptFocusBreak()
        }
        guard focusEngine.phase == .onBreak || route == .focusBreak else { return }
        route = .focusBreak
        showLockInTenCTA = false
        focusEngine.pause()
        let cycleCount = cycles ?? BreathingCoach.defaultCycles
        if startAgent {
            voiceAssistant.cancel()
            breathingCoach.prepareForAgent(cycles: cycleCount)
            voiceAssistant.startBreathMode()
        } else {
            breathingCoach.prepareForAgent(cycles: cycleCount)
        }
        hudMessage = "Breathing reset"
    }

    func stopBreathingReset() {
        breathingCoach.stop()
        if focusEngine.phase == .onBreak, focusEngine.isPaused {
            focusEngine.resume()
        }
    }

    /// Finish current Focus stats, then start a fresh 10-minute block.
    func lockInTenMinutes() {
        breathingCoach.stop()
        showLockInTenCTA = false
        if focusEngine.isRunning {
            focusEngine.onComplete = nil
            focusEngine.stopSession(emitComplete: false)
            endSignalSampling()
            let recap = focusEngine.makeRecap()
            let started = focusSessionStartedAt ?? Date()
            patternStore.record(recap: recap, startedAt: started)
            writer.writeFocusRecap(recap)
            writer.completeSession()
            wireFocusCallbacks()
        }
        startFocusSession(focusMinutes: 10, breakMinutes: 5)
        // Carry an open bookend into the new session doc so the post check still has a pair.
        if let pre = pendingPreReaction {
            writer.writeTapPVT(pre)
        }
        hudMessage = "Locked in · 10 min"
    }

    func finishFocusToRecap(_ recap: FocusRecap) {
        breathingCoach.stop()
        showLockInTenCTA = false
        lastFocusRecap = recap
        phoneSession.sendMotionEnergyStop()
        stopFocusCameraRuntime()
        endSignalSampling()
        // Bookend: the post check runs before the recap so the delta is ready to show.
        // Driven by an open pre result, not the toggle — a mid-block flip must not orphan it.
        if pendingPreReaction != nil {
            startReactionCheck(context: .bookendPost)
            return
        }
        finalizeFocusRecap(recap)
    }

    private func finalizeFocusRecap(_ recap: FocusRecap) {
        lastFocusRecap = recap
        let started = focusSessionStartedAt ?? Date()
        patternStore.record(recap: recap, startedAt: started)
        writer.writeFocusRecap(recap)
        writer.completeSession()
        phoneSession.sendMotionEnergyStop()
        route = .focusRecap
        hudMessage = "Focus complete"
        voiceAssistant.resetCheckInState()
        voiceAssistant.handleRouteChange(route)
        let hr = recap.meanHrBpm.map { String(format: "%.0f bpm mean HR", $0) } ?? "no HR"
        var summary = "Focus done. \(recap.focusedMinutesLabel) focused, \(recap.fadeCount) fades, \(hr)."
        if let comparison = lastReactionComparison {
            summary += " \(comparison.headline) \(comparison.lapseLine)"
        }
        voiceAssistant.notifySessionComplete(summary: summary)
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
            guard let self else { return }
            // Spatial: prefer camera arm octant, then Watch strike octant, then live aim.
            let spatial = self.faceTracker.armOctant
                ?? event.detectedOctant
                ?? self.watchLiveOctant
                ?? self.phoneSession.lastLiveOctant
            let enriched = StrikeEvent(
                watchTimestamp: event.watchTimestamp,
                peakG: event.peakG,
                phoneTimestamp: event.phoneTimestamp,
                detectedOctant: spatial
            )
            self.lastDetectedOctant = spatial
            if self.kineticEngine.isRunning {
                self.kineticEngine.ingestStrike(enriched)
            }
        }

        phoneSession.onLiveDirection = { [weak self] octant in
            guard let self else { return }
            self.watchLiveOctant = octant
            self.watchIMUCalibrated = true
        }

        phoneSession.onCalibrateResult = { [weak self] success in
            guard let self else { return }
            self.isWatchCalibrating = false
            self.watchIMUCalibrated = success
            if success {
                self.phoneSession.sendLiveDirectionStart()
                self.hudMessage = "Watch calibrate done — strikes use IMU"
            } else {
                self.hudMessage = "Watch calibrate failed — retry"
            }
        }

        phoneSession.onSyncQuality = { [weak self] offsetMs, rttMs in
            self?.writer.updateClockQuality(offsetMs: offsetMs, rttMs: rttMs)
        }

        phoneSession.onHeartRate = { [weak self] event in
            guard let self else { return }
            self.writer.updateHeartRate(event)
            if self.focusEngine.isRunning {
                self.focusEngine.ingestHeartRate(event.bpm)
                self.noteFocusHeartRateForCamera(event.bpm)
                self.recordSignalSample()
            }
            if self.route == .hub || self.isKineticRoute {
                // Soft HUD — don't clobber trial result lines during live kinetic scoring.
                if !self.isKineticLiveRoute || self.hudMessage.hasPrefix("HR") || self.hudMessage == "Kinetic live" {
                    self.hudMessage = String(format: "HR %.0f bpm", event.bpm)
                }
            }
        }

        phoneSession.onMotionEnergy = { [weak self] energy in
            guard let self, self.focusEngine.isRunning else { return }
            self.focusEngine.ingestMotionEnergy(energy)
            self.recordSignalSample()
        }

        faceTracker.onGaze = { [weak self] sample in
            guard let self else { return }
            self.gazeMapper.update(lookAt: sample.lookAt)
            if self.visionEngine.isRunning {
                self.visionEngine.ingestGaze(sample)
                if let saccade = self.faceTracker.lastSaccade {
                    self.visionEngine.ingestSaccade(saccade)
                }
                if let arousal = self.faceTracker.lastArousal {
                    self.visionEngine.ingestArousal(arousal)
                }
            }
            if self.focusEngine.isRunning, self.focusUsesCamera {
                // Passed through unwrapped: nil is the signal that the face was lost, and
                // the detector needs it to drop the arousal channel.
                self.focusEngine.ingestArousal(self.faceTracker.lastArousal)
            }
        }

        faceTracker.onPostureFeatures = { [weak self] features, joints, bones in
            self?.ingestPostureFeatures(features, joints: joints, bones: bones)
        }

        visionEngine.onTrialCompleted = { [weak self] trial, gaze, t0 in
            guard let self else { return }
            self.writer.writeTrial(trial, gaze: gaze, t0Ms: t0)
            self.hudMessage = trial.valid
                ? String(format: "Cell %d · Visual RT %.0f ms", trial.targetCell, trial.visualRtMs ?? 0)
                : "Invalid: \(trial.invalidReason ?? "?")"
        }

        visionEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }

        visionEngine.onBreakPoint = { [weak self] index, mean, std in
            guard let self else { return }
            self.writer.writeBreakPoint(
                trialIndex: index,
                baselineGapMs: mean,
                baselineStdMs: std
            )
            self.phoneSession.sendBreakPointHaptic()
            self.flashBreakPoint(trial: index)
        }

        kineticEngine.onTrialCompleted = { [weak self] trial in
            guard let self else { return }
            self.writer.writeTrial(trial)
            let target = trial.targetOctant.flatMap { ClockOctant(rawValue: $0)?.label } ?? "?"
            let detected = trial.detectedOctant.flatMap { ClockOctant(rawValue: $0)?.label } ?? "—"
            let match = trial.spatialMatch == true ? "match" : "miss"
            if let motor = trial.motorRtMs {
                self.hudMessage = String(
                    format: "Target: %@ · Detected: %@ · %@ · %.0f ms",
                    target, detected, match, motor
                )
            } else {
                self.hudMessage = "Target: \(target) · Detected: \(detected) · \(match)"
            }
        }

        kineticEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
        }

        kineticEngine.onBreakPoint = { [weak self] index, mean, std in
            guard let self else { return }
            self.writer.writeBreakPoint(
                trialIndex: index,
                baselineGapMs: mean,
                baselineStdMs: std
            )
            self.phoneSession.sendBreakPointHaptic()
            self.flashBreakPoint(trial: index)
        }

        kineticEngine.onSessionComplete = { [weak self] in
            guard let self else { return }
            let recap = self.kineticEngine.makeRecap(completedNaturally: true)
            self.kineticEngine.stopSession()
            self.writer.completeSession()
            self.faceTracker.setArmPoseEnabled(true)
            self.phoneSession.sendLiveDirectionStart()
            self.finishKineticToRecap(recap)
        }

        wireFocusCallbacks()
    }

    private func wireFocusCallbacks() {
        focusEngine.onFadeSuggested = { [weak self] in
            guard let self else { return }
            self.phoneSession.sendBreakPointHaptic()
            self.hudMessage = "Fade · take a break?"
            self.voiceAssistant.notifyFocusFade()
            self.recordSignalSample(force: true)
            self.signalStore.markBreakSuggested()
        }

        focusEngine.onBreakStarted = { [weak self] in
            guard let self else { return }
            self.phoneSession.sendBreakPointHaptic()
            if self.route != .focusBreak {
                self.route = .focusBreak
                self.voiceAssistant.handleRouteChange(self.route)
                self.voiceAssistant.notifyFocusBreakStarted()
            }
            self.hudMessage = "Break"
        }

        focusEngine.onComplete = { [weak self] recap in
            self?.finishFocusToRecap(recap)
        }

        focusEngine.onEpoch = { [weak self] epoch in
            self?.writer.writeFocusEpoch(epoch)
            self?.recordSignalSample(force: true)
        }

        focusEngine.onBaselineReady = { [weak self] mean, std in
            self?.writer.writeBaseline(meanMs: mean, stdMs: std)
            self?.recordSignalSample(force: true)
            self?.signalStore.markBaselineReady()
        }

        tapPVTEngine.onComplete = { [weak self] result in
            self?.handleReactionResult(result)
        }
    }

    // MARK: - HealthKit read (history + trends — display only)

    /// System Health permission for all Signals read types. Prefer Signals / Settings — not cold launch.
    @discardableResult
    func requestHealthReadAccess() async -> Bool {
        let ok = await healthTrends.requestHealthReadAccess()
        historicalHeartRate.syncPromptedFromDefaults()
        healthTrends.syncPromptedFromDefaults()
        return ok
    }

    /// Re-query the last `windowHours` of HR samples from Apple Health on the phone.
    func refreshHistoricalHeartRate() async {
        await historicalHeartRate.refreshHistoricalHeartRate()
    }

    /// Re-query recovery + activity daily trends.
    func refreshHealthTrends() async {
        await healthTrends.refreshTrends()
    }

    /// Signals sheet entry: one authorize prompt, then refresh 24h HR + trends.
    func ensureHistoricalHeartRateForSignals() async {
        await ensureHealthDataForSignals()
    }

    /// Prompt once if needed, then refresh historical HR and recovery/activity trends.
    func ensureHealthDataForSignals() async {
        healthTrends.syncPromptedFromDefaults()
        historicalHeartRate.syncPromptedFromDefaults()
        if !healthTrends.hasPromptedAuthorization {
            _ = await requestHealthReadAccess()
        }
        async let hr: Void = historicalHeartRate.refreshHistoricalHeartRate()
        async let trends: Void = healthTrends.refreshTrends()
        _ = await (hr, trends)
    }

    // MARK: - Signals sampling

    private func beginSignalSampling() {
        signalSampleTask?.cancel()
        signalStore.beginSession(at: focusSessionStartedAt ?? Date())
        recordSignalSample(force: true)
        signalSampleTask = Task { @MainActor [weak self] in
            while let self, self.focusEngine.isRunning, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, self.focusEngine.isRunning else { return }
                self.recordSignalSample()
            }
        }
    }

    private func endSignalSampling() {
        signalSampleTask?.cancel()
        signalSampleTask = nil
        guard signalStore.isLive else { return }
        recordSignalSample(force: true)
        signalStore.endSession()
    }

    /// Snapshot current Focus / Watch / face channels into the Signals ring buffer.
    private func recordSignalSample(force: Bool = false) {
        guard signalStore.isLive || force else { return }
        // Presence only when Focus camera presence is awake — preview peek alone is not a fade channel.
        let cameraAwake = focusUsesCamera
        let presence: Float? = cameraAwake ? focusEngine.lastArousal : nil
        _ = signalStore.record(
            heartRateBpm: focusEngine.lastHrBpm ?? phoneSession.lastHeartRateBpm,
            paceScore: focusEngine.fadeScore,
            presenceProxy: presence,
            motionEnergy: focusEngine.lastMotionEnergy ?? phoneSession.lastMotionEnergy,
            signalState: focusEngine.signalState,
            cameraAwake: cameraAwake,
            force: force
        )
    }

    private func flashBreakPoint(trial: Int) {
        showBreakPointFlash = true
        hudMessage = "BREAK-POINT · trial \(trial + 1)"
        voiceAssistant.notifyBreakPoint(trial: trial)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showBreakPointFlash = false
        }
    }
}

@main
struct SynapseApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.phoneSession.refreshSessionState()
                    }
                }
        }
    }
}
