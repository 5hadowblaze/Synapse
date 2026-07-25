import SwiftUI

@main
struct SynapseWatchApp: App {
    @State private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView(session: session)
                // Start once; do NOT stop on disappear — wrist-down / nav must keep
                // workout + 100Hz motion + clock sync alive for the demo.
                .onAppear { session.startMonitoring() }
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
            if let bpm = session.lastHeartRateBpm {
                Text(String(format: "%.0f BPM", bpm))
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.red.opacity(0.9))
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
