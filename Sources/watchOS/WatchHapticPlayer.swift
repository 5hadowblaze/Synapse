import Foundation
import WatchKit

protocol WatchHapticPlaying: AnyObject {
    func playClick()
    func playFailure()
    func playBreakPointSequence()
}

final class LiveWatchHapticPlayer: WatchHapticPlaying {
    func playClick() {
        WKInterfaceDevice.current().play(.click)
    }

    func playFailure() {
        WKInterfaceDevice.current().play(.failure)
    }

    func playBreakPointSequence() {
        WKInterfaceDevice.current().play(.notification)
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            WKInterfaceDevice.current().play(.directionUp)
            try? await Task.sleep(nanoseconds: 120_000_000)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
