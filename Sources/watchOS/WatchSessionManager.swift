import Foundation
import WatchConnectivity
import WatchKit

@Observable
@MainActor
final class WatchSessionManager: NSObject {
    var isReachable = false
    var statusText = "Idle"
    var lastOffsetMs: Double?
    var lastRttMs: Double?

    let clockSync = ClockSyncClient()
    let motion = MotionMonitor()
    let workout = WorkoutKeepAlive()

    private let session: WCSession
    private var pendingSyncContinuations: [UUID: CheckedContinuation<ClockSyncSample?, Never>] = [:]

    override init() {
        self.session = WCSession.default
        super.init()
        guard WCSession.isSupported() else {
            statusText = "WC unsupported"
            return
        }
        session.delegate = self
        session.activate()
        clockSync.attach(sessionManager: self)
        clockSync.onSyncUpdated = { [weak self] sample in
            self?.lastOffsetMs = sample.offsetMs
            self?.lastRttMs = sample.rttMs
            self?.statusText = String(format: "sync RTT %.0fms", sample.rttMs)
            self?.reportSyncQuality(sample)
        }
        motion.onStrike = { [weak self] watchTime, peakG in
            self?.sendStrike(watchTime: watchTime, peakG: peakG)
        }
    }

    func startMonitoring() {
        Task {
            do {
                try await workout.start()
                statusText = "Workout on"
            } catch {
                statusText = "Workout denied"
            }
            motion.start()
            clockSync.startPeriodicSync()
            statusText = "Armed"
        }
    }

    func stopMonitoring() {
        motion.stop()
        clockSync.stop()
        Task { await workout.stop() }
        statusText = "Stopped"
    }

    func performSyncRoundTrip() async -> ClockSyncSample? {
        guard session.activationState == .activated, session.isReachable else { return nil }
        let t1 = WatchTime.now()
        let payload: [String: Any] = [
            WCMessageKey.type: WCMessageKey.syncPing,
            WCMessageKey.t1: t1.seconds
        ]

        return await withCheckedContinuation { continuation in
            let id = UUID()
            pendingSyncContinuations[id] = continuation
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    let t4 = WatchTime.now()
                    guard
                        let t2 = reply[WCMessageKey.t2] as? Double,
                        let t3 = reply[WCMessageKey.t3] as? Double
                    else {
                        self.finishSync(id: id, sample: nil)
                        return
                    }
                    let sample = ClockSyncSample.cristian(
                        t1: t1,
                        t2: PhoneTime(seconds: t2),
                        t3: PhoneTime(seconds: t3),
                        t4: t4
                    )
                    self.finishSync(id: id, sample: sample)
                }
            }, errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.finishSync(id: id, sample: nil)
                }
            })
        }
    }

    private func finishSync(id: UUID, sample: ClockSyncSample?) {
        pendingSyncContinuations.removeValue(forKey: id)?.resume(returning: sample)
    }

    private func reportSyncQuality(_ sample: ClockSyncSample) {
        let payload: [String: Any] = [
            WCMessageKey.type: "syncQuality",
            "offsetMs": sample.offsetMs,
            "rttMs": sample.rttMs
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func sendStrike(watchTime: WatchTime, peakG: Double) {
        guard let offset = clockSync.offsetSeconds else {
            statusText = "Strike (no sync)"
            return
        }
        let phone = watchTime.toPhoneTime(offsetSeconds: offset)
        let event = StrikeEvent(
            watchTimestamp: watchTime.seconds,
            peakG: peakG,
            phoneTimestamp: phone.seconds
        )
        let message = event.asMessage()
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.statusText = "Send fail: \(error.localizedDescription)"
                }
            }
        } else {
            session.transferUserInfo(message)
        }
        statusText = String(format: "Strike %.1fg", peakG)
        WKInterfaceDevice.current().play(.click)
    }

    func playBreakPointHaptic() {
        WKInterfaceDevice.current().play(.notification)
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            WKInterfaceDevice.current().play(.directionUp)
            try? await Task.sleep(nanoseconds: 120_000_000)
            WKInterfaceDevice.current().play(.failure)
        }
        statusText = "BREAK-POINT"
    }
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
                statusText = "Phone linked"
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let type = message[WCMessageKey.type] as? String else { return }
            if type == WCMessageKey.breakPointHaptic {
                playBreakPointHaptic()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            guard let type = userInfo[WCMessageKey.type] as? String else { return }
            if type == WCMessageKey.breakPointHaptic {
                playBreakPointHaptic()
            }
        }
    }
}
