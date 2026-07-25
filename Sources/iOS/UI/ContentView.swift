import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                HUDView(model: model)

                TargetGridView(
                    activeCell: model.trialEngine.activeCell,
                    gridSize: TrialEngine.gridSize
                )
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button(model.trialEngine.isRunning ? "Stop" : "Start") {
                        if model.trialEngine.isRunning {
                            model.stopLiveSession()
                        } else {
                            model.startLiveSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Canned Replay") {
                        model.runCannedReplay()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 24)
            }

            if model.showBreakPointFlash {
                Color.red.opacity(0.55)
                    .ignoresSafeArea()
                    .overlay {
                        Text("BREAK-POINT")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TargetGridView: View {
    let activeCell: Int?
    let gridSize: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<gridSize, id: \.self) { index in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(index == activeCell ? Color.green : Color.white.opacity(0.12))
                    .overlay {
                        Text("\(index)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .animation(.easeOut(duration: 0.05), value: activeCell)
            }
        }
    }
}

struct HUDView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SYNAPSE")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text(model.hudMessage)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.green)
            Text(model.faceTracker.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(model.phoneSession.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(firebaseLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.5))
            if let gap = model.trialEngine.lastCognitiveMotorGapMs {
                Text(String(format: "Last gap: %.0f ms", gap))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var firebaseLine: String {
        let mode = model.writer.isFirebaseReady ? "Firebase" : "Stub"
        return "\(mode) · pending \(model.writer.pendingWrites) · session \(model.writer.sessionId?.prefix(8) ?? "—")"
    }
}
