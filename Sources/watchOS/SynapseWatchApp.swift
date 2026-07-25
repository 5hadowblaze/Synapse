import SwiftUI

@main
struct SynapseWatchApp: App {
    @State private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: session)
                .onAppear { session.startMonitoring() }
                .onDisappear { session.stopMonitoring() }
        }
    }
}

struct WatchContentView: View {
    @Bindable var session: WatchSessionManager

    var body: some View {
        VStack(spacing: 8) {
            Text(session.statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let rtt = session.lastRttMs {
                Text(String(format: "RTT %.0f ms", rtt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
