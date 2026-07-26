import SwiftUI

// MARK: - Chrome (matches Focus calm dark teal)

private enum KineticRecapChrome {
    static let canvasTop = Color(red: 0.045, green: 0.07, blue: 0.085)
    static let canvasMid = Color(red: 0.025, green: 0.04, blue: 0.055)
    static let surface = Color.white.opacity(0.045)
    static let hairline = Color.white.opacity(0.10)
    static let label = Color.white.opacity(0.38)
    static let body = Color.white.opacity(0.55)
    static let accent = Color(red: 0.35, green: 0.72, blue: 0.68)
}

/// Post-session Kinetic Clock recap — median motor RT leads; spatial + miss rates underneath.
struct KineticRecapView: View {
    @Bindable var model: AppModel
    @State private var revealed = false

    private var recap: KineticRecap? { model.lastKineticRecap }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [KineticRecapChrome.canvasTop, KineticRecapChrome.canvasMid, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Recap")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .padding(.top, 28)

                    Text("Kinetic Clock")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.8)
                        .foregroundStyle(KineticRecapChrome.label)

                    if let recap {
                        heroBlock(recap)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 8)

                        statsCard(recap)
                            .opacity(revealed ? 1 : 0)

                        if let bp = recap.breakPointTrial {
                            Text("Shift from your baseline around trial \(bp + 1). A cue to ease up — not a diagnosis.")
                                .font(.subheadline)
                                .foregroundStyle(KineticRecapChrome.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .opacity(revealed ? 1 : 0)
                        }

                        if !recap.completedNaturally {
                            Text("Session stopped early · \(recap.trialsLabel) trials")
                                .font(.caption)
                                .foregroundStyle(KineticRecapChrome.label)
                        }
                    } else {
                        Text("No session data")
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    VStack(spacing: 12) {
                        Button {
                            model.returnToHub()
                        } label: {
                            Text("Done")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(KineticRecapChrome.accent.opacity(0.88))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.runKineticAgainFromRecap()
                        } label: {
                            Text("Run again")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(KineticRecapChrome.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(KineticRecapChrome.hairline, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 28)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.12)) { revealed = true }
        }
    }

    private func heroBlock(_ recap: KineticRecap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEDIAN MOTOR RT")
                .font(.caption2.weight(.semibold))
                .kerning(1.8)
                .foregroundStyle(KineticRecapChrome.label)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(recap.medianLabel)
                    .font(.system(size: 62, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("ms")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text(heroSubtitle(recap))
                .font(.subheadline)
                .foregroundStyle(KineticRecapChrome.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(KineticRecapChrome.accent.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func heroSubtitle(_ recap: KineticRecap) -> String {
        if recap.motorSampleCount == 0 {
            return "No timed punches this run"
        }
        let n = recap.motorSampleCount
        return "Across \(n) timed \(n == 1 ? "punch" : "punches") · mean \(recap.meanLabel) ms"
    }

    private func statsCard(_ recap: KineticRecap) -> some View {
        VStack(spacing: 0) {
            row("Trials", recap.trialsLabel)
            divider
            row("Spatial accuracy", recap.accuracyLabel)
            if recap.spatialScoredCount > 0 {
                divider
                row("Direction hits", "\(recap.spatialMatchCount)/\(recap.spatialScoredCount)")
            }
            divider
            row("Misses / timeouts", "\(recap.missCount)")
            divider
            row("Wrong direction", "\(recap.spatialMissCount)")
            if let mean = recap.baselineMeanMs {
                divider
                let std = recap.baselineStdMs.map { String(format: " ± %.0f", $0) } ?? ""
                row("Baseline", String(format: "%.0f ms%@", mean, std))
            }
            if let bp = recap.breakPointTrial {
                divider
                row("Baseline shift", "Trial \(bp + 1)")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KineticRecapChrome.surface)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(.white.opacity(0.48))
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
