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
        VStack(spacing: 6) {
            Text(session.statusText)
                .font(.headline)
                .multilineTextAlignment(.center)
            if session.isCalibrating {
                Text("Hold still · face phone")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if let octant = session.lastDetectedOctant,
               let label = ClockOctant(rawValue: octant)?.label {
                Text("Octant \(label)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }
            if let rtt = session.lastRttMs {
                Text(String(format: "RTT %.0f ms", rtt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
