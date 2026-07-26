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
        VStack(spacing: 8) {
            if session.statusText == "Allow Health" {
                Text(session.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("iPhone → Health → Apps → Synapse")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.85))
                    .multilineTextAlignment(.center)
            } else {
                HeartRatePulseIndicator(
                    bpm: session.lastHeartRateBpm,
                    isMeasuring: session.workout.isActive && session.lastHeartRateBpm == nil,
                    measuredAt: session.lastHeartRateReceivedAt,
                    size: .hero
                )
            }

            if session.isCalibrating {
                Text("Hold still · face phone")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if let octant = session.lastDetectedOctant,
               let label = ClockOctant(rawValue: octant)?.label {
                Text("Octant \(label)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green.opacity(0.9))
            }

            // Status + RTT stay secondary under the Apple-style HR hero.
            if session.statusText != "Allow Health",
               !session.statusText.hasPrefix("HR ") {
                Text(session.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let rtt = session.lastRttMs {
                Text(String(format: "RTT %.0f ms", rtt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
    }
}
