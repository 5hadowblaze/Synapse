import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    /// Configure Firebase if a real `GoogleService-Info.plist` is present.
    /// Missing/placeholder plist → stub mode; builds still succeed.
    @discardableResult
    static func configureIfPossible() -> Bool {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() != nil {
            isConfigured = true
            return true
        }
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path),
            let apiKey = dict["API_KEY"] as? String,
            apiKey != "REPLACE_ME",
            !apiKey.isEmpty
        else {
            isConfigured = false
            return false
        }
        FirebaseApp.configure()
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let settings = db.settings
        // Offline persistence queues writes through outages (p4-offline).
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: NSNumber(value: FirestoreCacheSizeUnlimited)
        )
        db.settings = settings
        #endif
        isConfigured = true
        return true
        #else
        isConfigured = false
        return false
        #endif
    }
}

/// Default/demo id shared with web (`VITE_DEFAULT_SESSION_ID`) and seed scripts.
enum SynapseSessionIDs {
    static let demo = "demo-session-001"
}

/// Optional post-block spoken check-in (self-report only — never inferred physiology).
struct FocusCheckIn: Equatable, Sendable {
    var skipped: Bool
    var feltEnergy: Int?
    var feltClarity: Int?
    var nudgeMatched: Bool?
    var wouldStopEarlier: Bool?
    var summary: String?

    static let skipped = FocusCheckIn(skipped: true)
}

/// Buffered fire-and-forget Firestore writer. Never await inside the game loop.
@Observable
@MainActor
final class SessionWriter {
    var sessionId: String?
    var lastError: String?
    var pendingWrites = 0
    var isFirebaseReady = false
    var stubWriteCount = 0
    var activeModule: SessionModule?

    private var writeQueue: [() -> Void] = []
    private var isFlushing = false

    #if canImport(FirebaseFirestore)
    private var db: Firestore? { FirebaseBootstrap.isConfigured ? Firestore.firestore() : nil }
    #endif

    init() {
        isFirebaseReady = FirebaseBootstrap.configureIfPossible()
    }

    @discardableResult
    func startSession(
        athleteId: String,
        module: SessionModule,
        clockOffsetMs: Double?,
        clockRttMs: Double?,
        sessionId preferredId: String? = nil
    ) -> String {
        let id = preferredId ?? UUID().uuidString
        sessionId = id
        activeModule = module
        enqueue { [weak self] in
            self?.writeSessionCreate(
                id: id,
                athleteId: athleteId,
                module: module,
                clockOffsetMs: clockOffsetMs,
                clockRttMs: clockRttMs
            )
        }
        return id
    }

    func updateClockQuality(offsetMs: Double, rttMs: Double) {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: [
                "clockOffsetMs": offsetMs,
                "clockRttMs": rttMs
            ])
        }
    }

    /// Latest discrete workout HR (Series 5 ~ every few seconds). Not fused to camera frames.
    func updateHeartRate(_ event: HeartRateEvent) {
        guard let sessionId else { return }
        let wallMs = Date().timeIntervalSince1970 * 1000
        var fields: [String: Any] = [
            "lastHeartRateBpm": event.bpm,
            // Uptime-domain (Cristian-aligned) — keep for fusion math; do not use for wall freshness.
            "lastHeartRatePhoneMs": event.phoneTimestamp * 1000,
            "lastHeartRateWatchMs": event.watchTimestamp * 1000,
            "lastHeartRateSource": event.source,
            // Wall-clock ms so the web HUD can show "HR live · Ns ago".
            "lastHeartRateReceivedAtMs": wallMs
        ]
        if let start = event.hkStart { fields["lastHeartRateHkStart"] = start }
        if let end = event.hkEnd { fields["lastHeartRateHkEnd"] = end }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
        }
    }

    /// Pitch/dashboard pointer — web "Find live" loads this without guessing a UUID.
    func publishLiveFocusPointer(sessionId: String) {
        enqueue { [weak self] in
            self?.writeLiveFocusPointer(sessionId: sessionId, clear: false)
        }
    }

    func clearLiveFocusPointer() {
        enqueue { [weak self] in
            self?.writeLiveFocusPointer(sessionId: nil, clear: true)
        }
    }

    func writeTrial(_ trial: TrialRecord, gaze: [GazeWindowSample], t0Ms: Double) {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.writeTrialDoc(sessionId: sessionId, trial: trial, gaze: gaze, t0Ms: t0Ms)
        }
    }

    /// Kinetic trials have no gaze window — write trial doc only.
    func writeTrial(_ trial: TrialRecord) {
        writeTrial(trial, gaze: [], t0Ms: (trial.targetOnsetMs ?? 0) - 200)
    }

    func writeBreakPoint(
        trialIndex: Int,
        baselineGapMs: Double?,
        baselineStdMs: Double?
    ) {
        guard let sessionId else { return }
        var fields: [String: Any] = ["breakPointTrial": trialIndex]
        if let baselineGapMs { fields["baselineGapMs"] = baselineGapMs }
        if let baselineStdMs { fields["baselineStdMs"] = baselineStdMs }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
        }
    }

    func writeBaseline(meanMs: Double, stdMs: Double) {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: [
                "baselineGapMs": meanMs,
                "baselineStdMs": stdMs
            ])
        }
    }

    /// Sparse Focus desk epoch (not a PVT/Kinetic trial). Stored under `epochs/{index}`.
    func writeFocusEpoch(_ epoch: FocusEpochSnapshot) {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.writeFocusEpochDoc(sessionId: sessionId, epoch: epoch)
        }
    }

    func writeFocusRecap(_ recap: FocusRecap) {
        guard let sessionId else { return }
        var fields: [String: Any] = [
            "focusFocusedSeconds": recap.focusedSeconds,
            "focusBreakSeconds": recap.breakSeconds,
            "focusFadeCount": recap.fadeCount,
            "focusExtendedOnce": recap.extendedOnce,
            "focusBaselineReady": recap.baselineReady
        ]
        if let mean = recap.meanHrBpm { fields["focusMeanHrBpm"] = mean }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
        }
    }

    /// Follow-up write after session complete — talk-through self-report (or skip).
    func writeFocusCheckIn(_ checkIn: FocusCheckIn) {
        guard let sessionId else { return }
        var fields: [String: Any] = [
            "checkInSkipped": checkIn.skipped,
            "checkInAt": Date().timeIntervalSince1970 * 1000
        ]
        if let v = checkIn.feltEnergy { fields["checkInFeltEnergy"] = v }
        if let v = checkIn.feltClarity { fields["checkInFeltClarity"] = v }
        if let v = checkIn.nudgeMatched { fields["checkInNudgeMatched"] = v }
        if let v = checkIn.wouldStopEarlier { fields["checkInWouldStopEarlier"] = v }
        if let v = checkIn.summary, !v.isEmpty { fields["checkInSummary"] = v }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
        }
    }

    /// Reaction check (tap PVT) for one stage. Summary lands on the session doc so the
    /// dashboard can read it without a join; full trials go to `pvt/{stage}`.
    func writeTapPVT(_ result: TapPVTResult) {
        guard let sessionId else { return }
        let prefix = "pvt\(result.stage.rawValue.capitalized)"
        var fields: [String: Any] = [
            "\(prefix)Lapses": result.lapseCount,
            "\(prefix)FalseStarts": result.falseStartCount,
            "\(prefix)ValidTrials": result.validCount
        ]
        if let median = result.medianRtMs { fields["\(prefix)MedianMs"] = median }
        if let mean = result.meanRtMs { fields["\(prefix)MeanMs"] = mean }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
            self?.writeTapPVTDoc(sessionId: sessionId, result: result)
        }
    }

    func writeTapPVTComparison(_ comparison: TapPVTComparison) {
        guard let sessionId else { return }
        var fields: [String: Any] = [
            "pvtLapseDelta": comparison.lapseDelta,
            "pvtDirection": comparison.direction.rawValue
        ]
        if let delta = comparison.medianDeltaMs { fields["pvtMedianDeltaMs"] = delta }
        if let pct = comparison.percentChange { fields["pvtPercentChange"] = pct }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: fields)
        }
    }

    func completeSession() {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: ["status": "complete"])
            self?.writeLiveFocusPointer(sessionId: nil, clear: true)
        }
    }

    /// Push a recorded session through the writer pipeline (one-tap fallback).
    func ingestCannedSession(_ canned: CannedSession) {
        _ = startSession(
            athleteId: canned.athleteId,
            module: canned.module,
            clockOffsetMs: canned.clockOffsetMs,
            clockRttMs: canned.clockRttMs,
            sessionId: canned.sessionId
        )
        writeBaseline(meanMs: canned.baselineGapMs, stdMs: canned.baselineStdMs)
        for item in canned.trials {
            writeTrial(item.trial, gaze: item.gaze, t0Ms: item.t0Ms)
        }
        if let bp = canned.breakPointTrial {
            writeBreakPoint(
                trialIndex: bp,
                baselineGapMs: canned.baselineGapMs,
                baselineStdMs: canned.baselineStdMs
            )
        }
        completeSession()
    }

    // MARK: - Queue (never blocks game loop)

    private func enqueue(_ work: @escaping () -> Void) {
        pendingWrites += 1
        writeQueue.append(work)
        flushSoon()
    }

    private func flushSoon() {
        guard !isFlushing else { return }
        isFlushing = true
        Task { @MainActor in
            while !self.writeQueue.isEmpty {
                let job = self.writeQueue.removeFirst()
                job()
                self.pendingWrites = max(0, self.pendingWrites - 1)
            }
            self.isFlushing = false
        }
    }

    // MARK: - Writes

    private func writeSessionCreate(
        id: String,
        athleteId: String,
        module: SessionModule,
        clockOffsetMs: Double?,
        clockRttMs: Double?
    ) {
        // Match docs/SCHEMA.md / web Session: clock fields required; baselines null until ready.
        let data: [String: Any] = [
            "athleteId": athleteId,
            "module": module.rawValue,
            "startedAt": Date().timeIntervalSince1970 * 1000,
            "status": "active",
            "clockOffsetMs": clockOffsetMs ?? 0,
            "clockRttMs": clockRttMs ?? 0,
            "baselineGapMs": NSNull(),
            "baselineStdMs": NSNull(),
            "breakPointTrial": NSNull()
        ]

        #if canImport(FirebaseFirestore)
        if let db {
            db.collection("sessions").document(id).setData(data) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error?.localizedDescription
                }
            }
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] create session \(id): \(data)")
    }

    private func patchSession(_ id: String, fields: [String: Any]) {
        #if canImport(FirebaseFirestore)
        if let db {
            db.collection("sessions").document(id).setData(fields, merge: true) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error?.localizedDescription
                }
            }
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] patch \(id): \(fields)")
    }

    private func writeTrialDoc(
        sessionId: String,
        trial: TrialRecord,
        gaze: [GazeWindowSample],
        t0Ms: Double
    ) {
        var data: [String: Any] = [
            "index": trial.index,
            "targetCell": trial.targetCell,
            "valid": trial.valid
        ]
        if let v = trial.targetOnsetMs { data["targetOnsetMs"] = v }
        if let v = trial.saccadeOnsetMs { data["saccadeOnsetMs"] = v }
        if let v = trial.gazeSettleMs { data["gazeSettleMs"] = v }
        if let v = trial.strikeMs { data["strikeMs"] = v }
        if let v = trial.visualRtMs { data["visualRtMs"] = v }
        if let v = trial.motorRtMs { data["motorRtMs"] = v }
        if let v = trial.cognitiveMotorGapMs { data["cognitiveMotorGapMs"] = v }
        if let v = trial.peakG { data["peakG"] = v }
        if let v = trial.arousalIndex { data["arousalIndex"] = Double(v) }
        if let v = trial.invalidReason { data["invalidReason"] = v }
        if let v = trial.targetOctant { data["targetOctant"] = v }
        if let v = trial.detectedOctant { data["detectedOctant"] = v }
        if let v = trial.spatialMatch { data["spatialMatch"] = v }

        // Plan path: sessions/{id}/trials/{index}/gaze → stored as subcollection doc "window".
        let gazeDoc: [String: Any] = [
            "t0Ms": t0Ms,
            "samples": gaze.map {
                ["dt": $0.dt, "x": Double($0.x), "y": Double($0.y), "z": Double($0.z)]
            }
        ]

        #if canImport(FirebaseFirestore)
        if let db {
            let trialRef = db.collection("sessions").document(sessionId)
                .collection("trials").document(String(trial.index))
            trialRef.setData(data) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error?.localizedDescription
                }
            }
            if !gaze.isEmpty {
                trialRef.collection("gaze").document("window").setData(gazeDoc) { [weak self] error in
                    Task { @MainActor in
                        self?.lastError = error?.localizedDescription
                    }
                }
            }
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] trial \(trial.index) gaze=\(gaze.count)")
    }

    private func writeTapPVTDoc(sessionId: String, result: TapPVTResult) {
        var data: [String: Any] = [
            "stage": result.stage.rawValue,
            "startedAt": result.startedAt.timeIntervalSince1970 * 1000,
            "durationSeconds": result.durationSeconds,
            "lapses": result.lapseCount,
            "falseStarts": result.falseStartCount,
            "validTrials": result.validCount,
            "attemptedTrials": result.attemptedCount,
            "lapseThresholdMs": TapPVTResult.lapseThresholdMs,
            "trials": result.trials.map { trial -> [String: Any] in
                var row: [String: Any] = [
                    "index": trial.index,
                    "isiMs": trial.isiMs,
                    "falseStart": trial.falseStart,
                    "timedOut": trial.timedOut,
                    "lapse": trial.isLapse
                ]
                if let rt = trial.reactionMs { row["reactionMs"] = rt }
                return row
            }
        ]
        if let v = result.medianRtMs { data["medianRtMs"] = v }
        if let v = result.meanRtMs { data["meanRtMs"] = v }
        if let v = result.fastestRtMs { data["fastestRtMs"] = v }
        if let v = result.slowestRtMs { data["slowestRtMs"] = v }

        #if canImport(FirebaseFirestore)
        if let db {
            db.collection("sessions").document(sessionId)
                .collection("pvt").document(result.stage.rawValue)
                .setData(data) { [weak self] error in
                    Task { @MainActor in
                        self?.lastError = error?.localizedDescription
                    }
                }
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] tap PVT \(result.stage.rawValue): \(data)")
    }

    private func writeFocusEpochDoc(sessionId: String, epoch: FocusEpochSnapshot) {
        let wallMs = Date().timeIntervalSince1970 * 1000
        var data: [String: Any] = [
            "index": epoch.index,
            "phase": epoch.phase,
            "remainingMs": epoch.remainingMs,
            "fadeSuggested": epoch.fadeSuggested,
            "writtenAtMs": wallMs
        ]
        if let v = epoch.fadeScore { data["fadeScore"] = v }
        if let v = epoch.hrBpm { data["hrBpm"] = v }
        if let v = epoch.arousal { data["arousalIndex"] = Double(v) }
        if let v = epoch.motionEnergy { data["motionEnergy"] = v }

        #if canImport(FirebaseFirestore)
        if let db {
            db.collection("sessions").document(sessionId)
                .collection("epochs").document(String(epoch.index))
                .setData(data) { [weak self] error in
                    Task { @MainActor in
                        self?.lastError = error?.localizedDescription
                    }
                }
            // Denormalise onto the session so the HUD can show "epochs live" without scanning the subcollection.
            patchSession(sessionId, fields: [
                "lastEpochIndex": epoch.index,
                "lastEpochAtMs": wallMs,
                "lastEpochPhase": epoch.phase
            ])
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] focus epoch \(epoch.index): \(data)")
    }

    private func writeLiveFocusPointer(sessionId: String?, clear: Bool) {
        #if canImport(FirebaseFirestore)
        if let db {
            let ref = db.collection("live").document("focus")
            if clear {
                ref.setData([
                    "sessionId": NSNull(),
                    "status": "idle",
                    "updatedAtMs": Date().timeIntervalSince1970 * 1000
                ]) { [weak self] error in
                    Task { @MainActor in
                        self?.lastError = error?.localizedDescription
                    }
                }
            } else if let sessionId {
                ref.setData([
                    "sessionId": sessionId,
                    "status": "active",
                    "module": SessionModule.focusDesk.rawValue,
                    "updatedAtMs": Date().timeIntervalSince1970 * 1000
                ]) { [weak self] error in
                    Task { @MainActor in
                        self?.lastError = error?.localizedDescription
                    }
                }
            }
            return
        }
        #endif
        stubWriteCount += 1
        print("[SessionWriter stub] live/focus → \(sessionId ?? "cleared")")
    }
}
