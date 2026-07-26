import SwiftUI

/// Motion tokens mirrored from `web/src/motion/tokens.ts` — strong ease-out, short UI, longer chart draw.
enum SynapseMotion {
    /// Web `easeOut` ≈ cubic-bezier(0.23, 1, 0.32, 1)
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.enter)
    static let easeOutFast = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.press)
    static let easeOutHover = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.hover)
    static let chartDraw = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.chart)
    static let chartEnter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.chartPanel)
    static let page = Animation.timingCurve(0.23, 1, 0.32, 1, duration: Duration.enter)

    enum Duration {
        static let press: TimeInterval = 0.12
        static let hover: TimeInterval = 0.18
        static let enter: TimeInterval = 0.28
        static let exit: TimeInterval = 0.18
        static let chart: TimeInterval = 0.85
        static let chartPanel: TimeInterval = 0.45
        static let stagger: TimeInterval = 0.055
        static let staggerDelay: TimeInterval = 0.04
    }

    /// Soft rise + fade — matches web `pageTransition` / `ChartReveal` (no hard scale-from-zero).
    static var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 12))
                .combined(with: .scale(scale: 0.985, anchor: .bottom)),
            removal: .opacity
                .combined(with: .offset(y: -8))
        )
    }

    static var paneTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity.combined(with: .offset(y: -6))
        )
    }
}

// MARK: - Button press

/// Subtle press — 0.97 scale, ease-out (Emil: buttons must feel responsive).
struct SoftPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? (reduceMotion ? 1 : 0.97) : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : SynapseMotion.easeOutFast, value: configuration.isPressed)
    }
}

// MARK: - Reveal / chart

private struct SynapseRevealModifier: ViewModifier {
    let ready: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = SynapseMotion.Duration.staggerDelay + Double(index) * SynapseMotion.Duration.stagger
        content
            .opacity(ready || reduceMotion ? 1 : 0)
            .offset(y: ready || reduceMotion ? 0 : 14)
            .scaleEffect(ready || reduceMotion ? 1 : 0.98)
            .animation(
                reduceMotion ? nil : SynapseMotion.easeOut.delay(delay),
                value: ready
            )
    }
}

private struct SynapseChartRevealModifier: ViewModifier {
    let replayKey: String
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 16)
            .scaleEffect(visible ? 1 : 0.985)
            .onAppear { reveal(animated: !reduceMotion) }
            .onChange(of: replayKey) { _, _ in
                if reduceMotion {
                    visible = true
                } else {
                    visible = false
                    reveal(animated: true)
                }
            }
    }

    private func reveal(animated: Bool) {
        if animated {
            withAnimation(SynapseMotion.chartEnter) { visible = true }
        } else {
            visible = true
        }
    }
}

/// Scales chart values 0→1 on appear so the line draws up like the web stroke reveal.
private struct SynapseChartDrawModifier: ViewModifier {
    let replayKey: String
    @Binding var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear { run() }
            .onChange(of: replayKey) { _, _ in run(reset: true) }
    }

    private func run(reset: Bool = false) {
        if reduceMotion {
            progress = 1
            return
        }
        if reset { progress = 0 }
        // Next runloop so Charts sees the zero baseline first.
        DispatchQueue.main.async {
            withAnimation(SynapseMotion.chartDraw) { progress = 1 }
        }
    }
}

extension View {
    /// Staggered hub / list entrance — web `staggerItem`.
    func synapseReveal(ready: Bool, index: Int) -> some View {
        modifier(SynapseRevealModifier(ready: ready, index: index))
    }

    /// Soft panel entrance for chart cards — web `ChartReveal`.
    func synapseChartReveal(replayKey: String) -> some View {
        modifier(SynapseChartRevealModifier(replayKey: replayKey))
    }

    func synapseChartDraw(replayKey: String, progress: Binding<Double>) -> some View {
        modifier(SynapseChartDrawModifier(replayKey: replayKey, progress: progress))
    }
}
