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

    func completeSession() {
        guard let sessionId else { return }
        enqueue { [weak self] in
            self?.patchSession(sessionId, fields: ["status": "complete"])
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
}
