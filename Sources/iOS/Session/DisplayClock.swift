import Foundation
import QuartzCore

/// Stamps true target-presentation time from `CADisplayLink.targetTimestamp`
/// (same CACurrentMediaTime domain as PhoneTime), not SwiftUI state mutation.
@MainActor
final class DisplayClock: NSObject {
    private var displayLink: CADisplayLink?
    private var pendingOnsetHandler: ((PhoneTime) -> Void)?
    private var isArmed = false

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        pendingOnsetHandler = nil
        isArmed = false
    }

    /// Arm so the *next* displayed frame's `targetTimestamp` is reported as onset.
    func armOnsetCapture(_ handler: @escaping (PhoneTime) -> Void) {
        pendingOnsetHandler = handler
        isArmed = true
        start()
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard isArmed, let handler = pendingOnsetHandler else { return }
        isArmed = false
        pendingOnsetHandler = nil
        let onset = PhoneTime(seconds: link.targetTimestamp)
        handler(onset)
    }
}
