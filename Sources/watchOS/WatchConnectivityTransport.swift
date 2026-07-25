import Foundation
import WatchConnectivity

/// Thin testable wrapper around `WCSession` for the Watch.
protocol WatchConnectivityTransport: AnyObject {
    var isSupported: Bool { get }
    var isActivated: Bool { get }
    var isReachable: Bool { get }

    func activate(delegate: WCSessionDelegate)
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    )
    func transferUserInfo(_ userInfo: [String: Any])
}

final class LiveWatchConnectivityTransport: WatchConnectivityTransport {
    private let session: WCSession

    init(session: WCSession = .default) {
        self.session = session
    }

    var isSupported: Bool { WCSession.isSupported() }
    var isActivated: Bool { session.activationState == .activated }
    var isReachable: Bool { session.isReachable }

    func activate(delegate: WCSessionDelegate) {
        guard isSupported else { return }
        session.delegate = delegate
        session.activate()
    }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) {
        session.sendMessage(message, replyHandler: replyHandler, errorHandler: errorHandler)
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        session.transferUserInfo(userInfo)
    }
}
