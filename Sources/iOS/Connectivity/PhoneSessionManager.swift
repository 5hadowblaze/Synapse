import Foundation
import WatchConnectivity

/// Phone-side WatchConnectivity session: answers Cristian sync pongs and receives strikes.
@Observable
@MainActor
final class PhoneSessionManager: NSObject {
    var isReachable = false
    var lastSyncOffsetMs: Double?
    var lastSyncRttMs: Double?
    var lastStrike: StrikeEvent?
    var statusText = "Watch: idle"

    var onStrike: ((StrikeEvent) -> Void)?
    var onSyncQuality: ((Double, Double) -> Void)?
    /// Live Watch pointing octant (Kinetic spoke lighting).
    var onLiveDirection: ((Int) -> Void)?
    /// Watch finished IMU calibration (`success` from Watch ACK).
    var onCalibrateResult: ((Bool) -> Void)?
    var lastLiveOctant: Int?
    var lastCalibrateSuccess: Bool?

    private let session: WCSession

    override init() {
        self.session = WCSession.default
        super.init()
        guard WCSession.isSupported() else {
            statusText = "WatchConnectivity unsupported"
            return
        }
        session.delegate = self
        session.activate()
    }

    func sendBreakPointHaptic() {
        let payload: [String: Any] = [WCMessageKey.type: WCMessageKey.breakPointHaptic]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.statusText = "Haptic send failed: \(error.localizedDescription)"
                }
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    /// Ask watch to capture gravity / attitude reference (~10s).
    func sendCalibrateStart(durationSeconds: Double = 10) {
        let payload: [String: Any] = [
            WCMessageKey.type: WCMessageKey.calibrateStart,
            WCMessageKey.duration: durationSeconds
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.statusText = "Calibrate send failed: \(error.localizedDescription)"
                }
            }
            statusText = "Watch calibrating…"
        } else {
            session.transferUserInfo(payload)
            statusText = "Watch calibrate queued"
        }
    }

    func sendCalibrateStop() {
        let payload: [String: Any] = [WCMessageKey.type: WCMessageKey.calibrateStop]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        } else {
            session.transferUserInfo(payload)
        }
    }

    func sendLiveDirectionStart() {
        let payload: [String: Any] = [WCMessageKey.type: WCMessageKey.liveDirectionStart]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
            statusText = "Watch live direction…"
        } else {
            session.transferUserInfo(payload)
            statusText = "Live direction queued"
        }
    }

    func sendLiveDirectionStop() {
        let payload: [String: Any] = [WCMessageKey.type: WCMessageKey.liveDirectionStop]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in })
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func handleSyncPing(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let t1 = message[WCMessageKey.t1] as? Double else { return }
        let t2 = PhoneTime.now().seconds
        let t3 = PhoneTime.now().seconds
        let reply: [String: Any] = [
            WCMessageKey.type: WCMessageKey.syncPong,
            WCMessageKey.t1: t1,
            WCMessageKey.t2: t2,
            WCMessageKey.t3: t3
        ]
        replyHandler?(reply)
    }

    private func handleStrike(_ message: [String: Any]) {
        guard let event = StrikeEvent.from(message: message) else { return }
        lastStrike = event
        if let octant = event.detectedOctant, let label = ClockOctant(rawValue: octant)?.label {
            statusText = String(format: "Strike %.1fg · %@", event.peakG, label)
        } else {
            statusText = String(format: "Strike %.1fg", event.peakG)
        }
        onStrike?(event)
    }

    private func handleLiveDirection(_ message: [String: Any]) {
        let octant: Int?
        if let i = message[WCMessageKey.detectedOctant] as? Int {
            octant = i
        } else if let d = message[WCMessageKey.detectedOctant] as? Double {
            octant = Int(d)
        } else {
            octant = nil
        }
        guard let octant else { return }
        lastLiveOctant = octant
        onLiveDirection?(octant)
        if let label = ClockOctant(rawValue: octant)?.label {
            statusText = "Watch aim · \(label)"
        }
    }

    private func handleSyncQuality(_ message: [String: Any]) {
        if let offset = message[WCMessageKey.offsetMs] as? Double {
            lastSyncOffsetMs = offset
        }
        if let rtt = message[WCMessageKey.rttMs] as? Double {
            lastSyncRttMs = rtt
            onSyncQuality?(lastSyncOffsetMs ?? 0, rtt)
            statusText = String(format: "Sync RTT %.0fms", rtt)
        }
    }

    private func handleCalibrateResult(_ message: [String: Any]) {
        let success: Bool
        if let b = message[WCMessageKey.success] as? Bool {
            success = b
        } else if let n = message[WCMessageKey.success] as? NSNumber {
            success = n.boolValue
        } else {
            return
        }
        lastCalibrateSuccess = success
        statusText = success ? "Watch calibrated" : "Watch calibrate failed"
        onCalibrateResult?(success)
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                statusText = "WC activate error: \(error.localizedDescription)"
            } else {
                isReachable = session.isReachable
                statusText = activationState == .activated ? "Watch session active" : "Watch session inactive"
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            statusText = session.isReachable ? "Watch reachable" : "Watch unreachable"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            guard let type = message[WCMessageKey.type] as? String else { return }
            switch type {
            case WCMessageKey.strike:
                handleStrike(message)
            case WCMessageKey.liveDirection:
                handleLiveDirection(message)
            case WCMessageKey.syncPing:
                handleSyncPing(message, replyHandler: nil)
            case WCMessageKey.syncQuality:
                handleSyncQuality(message)
            case WCMessageKey.calibrateResult:
                handleCalibrateResult(message)
            default:
                break
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            guard let type = message[WCMessageKey.type] as? String else {
                replyHandler([:])
                return
            }
            switch type {
            case WCMessageKey.syncPing:
                handleSyncPing(message, replyHandler: replyHandler)
            case WCMessageKey.strike:
                handleStrike(message)
                replyHandler([WCMessageKey.type: "ack"])
            case WCMessageKey.liveDirection:
                handleLiveDirection(message)
                replyHandler([WCMessageKey.type: "ack"])
            default:
                replyHandler([:])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            guard let type = userInfo[WCMessageKey.type] as? String else { return }
            switch type {
            case WCMessageKey.strike:
                handleStrike(userInfo)
            case WCMessageKey.liveDirection:
                handleLiveDirection(userInfo)
            case WCMessageKey.syncQuality:
                handleSyncQuality(userInfo)
            case WCMessageKey.calibrateResult:
                handleCalibrateResult(userInfo)
            default:
                break
            }
        }
    }
}
