import Foundation
import WatchConnectivity

@Observable
@MainActor
final class WatchSessionManager: NSObject {
    var isReachable = false
    var statusText = "Idle"
    var lastOffsetMs: Double?
    var lastRttMs: Double?
    var lastDetectedOctant: Int?
    var isCalibrating = false
    /// True after `startMonitoring()`; display sleep must not clear this.
    private(set) var isMonitoring = false

    let clockSync = ClockSyncClient()
    let motion: MotionMonitor
    let workout: WorkoutKeepAlive

    private let transport: any WatchConnectivityTransport
    private let haptics: any WatchHapticPlaying
    private var pendingSyncContinuations: [UUID: CheckedContinuation<ClockSyncSample?, Never>] = [:]
    /// One-slot retry: last punch dropped for missing sync, flushed after offset arrives.
    private var pendingStrikeAfterSync: (watchTime: WatchTime, peakG: Double, octant: Int?)?
    private var calibrationTimeoutTask: Task<Void, Never>?
    private var didWireCallbacks = false

    override init() {
        let transport = LiveWatchConnectivityTransport()
        self.transport = transport
        self.motion = MotionMonitor()
        self.workout = WorkoutKeepAlive()
        self.haptics = LiveWatchHapticPlayer()
        super.init()
        wireCallbacks()
        guard transport.isSupported else {
            statusText = "WC unsupported"
            return
        }
        transport.activate(delegate: self)
    }

    init(
        transport: any WatchConnectivityTransport,
        motion: MotionMonitor,
        workout: WorkoutKeepAlive,
        haptics: any WatchHapticPlaying
    ) {
        self.transport = transport
        self.motion = motion
        self.workout = workout
        self.haptics = haptics
        super.init()
        wireCallbacks()
        guard transport.isSupported else {
            statusText = "WC unsupported"
            return
        }
        transport.activate(delegate: self)
    }

    private func wireCallbacks() {
        guard !didWireCallbacks else { return }
        didWireCallbacks = true
        clockSync.attach(roundTrip: self)
        clockSync.onSyncUpdated = { [weak self] sample in
            guard let self else { return }
            self.lastOffsetMs = sample.offsetMs
            self.lastRttMs = sample.rttMs
            self.statusText = String(format: "sync RTT %.0fms", sample.rttMs)
            self.reportSyncQuality(sample)
            self.flushPendingStrikeIfPossible()
        }
        motion.onStrike = { [weak self] watchTime, peakG, octant in
            self?.sendStrike(watchTime: watchTime, peakG: peakG, detectedOctant: octant)
        }
        motion.onLiveDirection = { [weak self] octant in
            self?.sendLiveDirection(octant)
        }
        motion.onCalibrationFinished = { [weak self] success in
            self?.handleCalibrationFinished(success: success)
        }
    }

    func beginCalibration(durationSeconds: Double = 10) {
        calibrationTimeoutTask?.cancel()
        isCalibrating = true
        motion.startCalibration(durationSeconds: durationSeconds)
        statusText = "Calibrating…"
        // MotionMonitor finishes on its own deadline; this is a safety net for UI.
        calibrationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((durationSeconds + 0.5) * 1_000_000_000))
            guard !Task.isCancelled, self.isCalibrating else { return }
            self.motion.stopCalibration()
        }
    }

    func startLiveDirectionStream() {
        if !motion.isRunning { motion.start() }
        motion.isStreamingLiveDirection = true
        statusText = "Live direction on"
    }

    func stopLiveDirectionStream() {
        motion.isStreamingLiveDirection = false
        statusText = motion.isCalibrated ? "Calibrated" : "Armed"
    }

    /// Idempotent — safe to call from `onAppear` after display wake.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        Task {
            do {
                try await workout.start()
            } catch {
                statusText = "Workout denied"
            }
            motion.start()
            clockSync.startPeriodicSync()
            if clockSync.offsetSeconds == nil {
                statusText = "Syncing…"
            } else {
                statusText = "Armed"
            }
        }
    }

    /// Explicit teardown only (not display sleep / `onDisappear`).
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        motion.stop()
        clockSync.stop()
        calibrationTimeoutTask?.cancel()
        pendingStrikeAfterSync = nil
        Task { await workout.stop() }
        statusText = "Stopped"
    }

    func performSyncRoundTrip() async -> ClockSyncSample? {
        guard transport.isActivated, transport.isReachable else { return nil }
        let t1 = WatchTime.now()
        let payload = WatchOutboundMessage.syncPing(t1: t1.seconds)

        return await withCheckedContinuation { continuation in
            let id = UUID()
            pendingSyncContinuations[id] = continuation
            transport.sendMessage(payload, replyHandler: { [weak self] reply in
                let t4 = WatchTime.now()
                let sample: ClockSyncSample?
                if let t2 = reply[WCMessageKey.t2] as? Double,
                   let t3 = reply[WCMessageKey.t3] as? Double {
                    sample = ClockSyncSample.cristian(
                        t1: t1,
                        t2: PhoneTime(seconds: t2),
                        t3: PhoneTime(seconds: t3),
                        t4: t4
                    )
                } else {
                    sample = nil
                }
                Task { @MainActor in
                    if let self {
                        self.finishSync(id: id, sample: sample)
                    } else {
                        continuation.resume(returning: sample)
                    }
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    if let self {
                        self.finishSync(id: id, sample: nil)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            })
        }
    }

    private func finishSync(id: UUID, sample: ClockSyncSample?) {
        pendingSyncContinuations.removeValue(forKey: id)?.resume(returning: sample)
    }

    private func reportSyncQuality(_ sample: ClockSyncSample) {
        let payload = WatchOutboundMessage.syncQuality(offsetMs: sample.offsetMs, rttMs: sample.rttMs)
        sendOrTransfer(payload)
    }

    private func sendLiveDirection(_ octant: Int) {
        lastDetectedOctant = octant
        let payload = WatchOutboundMessage.liveDirection(octant: octant)
        if transport.isReachable {
            transport.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        }
        // Skip transferUserInfo for live stream — too chatty when unreachable.
    }

    private func sendStrike(watchTime: WatchTime, peakG: Double, detectedOctant: Int?) {
        switch StrikeDelivery.prepare(
            watchTime: watchTime,
            peakG: peakG,
            detectedOctant: detectedOctant,
            offsetSeconds: clockSync.offsetSeconds
        ) {
        case .needsClockSync:
            pendingStrikeAfterSync = (watchTime, peakG, detectedOctant)
            statusText = "Punch held — syncing"
            haptics.playFailure()
            // Urgent resync so the held punch (and next ones) can score.
            Task { await clockSync.runBurst() }
            return
        case .deliver(let event):
            dispatchStrikeEvent(event, detectedOctant: detectedOctant, peakG: peakG)
        }
    }

    private func flushPendingStrikeIfPossible() {
        guard let pending = pendingStrikeAfterSync else { return }
        guard clockSync.offsetSeconds != nil else { return }
        pendingStrikeAfterSync = nil
        sendStrike(
            watchTime: pending.watchTime,
            peakG: pending.peakG,
            detectedOctant: pending.octant
        )
    }

    private func dispatchStrikeEvent(_ event: StrikeEvent, detectedOctant: Int?, peakG: Double) {
        let message = event.asMessage()
        if transport.isReachable {
            transport.sendMessage(message, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.statusText = "Send fail: \(error.localizedDescription)"
                }
            }
        } else {
            transport.transferUserInfo(message)
        }
        lastDetectedOctant = detectedOctant
        if let octant = detectedOctant, let label = ClockOctant(rawValue: octant)?.label {
            statusText = String(format: "Strike %.1fg · %@", peakG, label)
        } else {
            statusText = String(format: "Strike %.1fg", peakG)
        }
        haptics.playClick()
    }

    private func handleCalibrationFinished(success: Bool) {
        calibrationTimeoutTask?.cancel()
        isCalibrating = false
        statusText = success ? "Calibrated" : "Calib failed"
        sendOrTransfer(WatchOutboundMessage.calibrateResult(success: success))
    }

    private func sendOrTransfer(_ payload: [String: Any]) {
        if transport.isReachable {
            transport.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        } else {
            transport.transferUserInfo(payload)
        }
    }

    func playBreakPointHaptic() {
        haptics.playBreakPointSequence()
        statusText = "BREAK-POINT"
    }

    func handleInbound(_ message: [String: Any]) {
        guard let command = WatchInboundCommand.parse(message) else { return }
        switch command {
        case .breakPointHaptic:
            playBreakPointHaptic()
        case .calibrateStart(let duration):
            beginCalibration(durationSeconds: duration)
        case .calibrateStop:
            motion.stopCalibration()
            // `onCalibrationFinished` reports result to phone.
        case .liveDirectionStart:
            startLiveDirectionStream()
        case .liveDirectionStop:
            stopLiveDirectionStream()
        }
    }
}

extension WatchSessionManager: ClockSyncRoundTripPerforming {
    // `performSyncRoundTrip` already defined above.
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isReachable = session.isReachable
            if let error {
                statusText = error.localizedDescription
            } else if activationState == .activated {
                statusText = isMonitoring ? statusText : "Phone linked"
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            if session.isReachable, clockSync.offsetSeconds == nil, isMonitoring {
                Task { await clockSync.runBurst() }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleInbound(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleInbound(userInfo)
        }
    }
}
