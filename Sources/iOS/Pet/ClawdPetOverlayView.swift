import SwiftUI

/// AssistiveTouch-style floating Clawd — replaces the voice orb.
/// Tap wakes/listens; tap again sleeps. Drag to move. Quiet during Focus live
/// (taps ignored) except when a proactive nudge wakes it.
struct ClawdPetOverlayView: View {
    @Bindable var voice: VoiceAssistantController
    var route: AppRoute

    @AppStorage("clawdPetOffsetX") private var storedX: Double = -1
    @AppStorage("clawdPetOffsetY") private var storedY: Double = -1

    @State private var position: CGPoint = .zero
    @State private var dragStart: CGPoint?
    @State private var isDragging = false
    @State private var dragDirection: ClawdAnimState = .runningRight
    @State private var hasPlaced = false

    private let petHeight: CGFloat = 92
    private let margin: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)

                VStack(alignment: .center, spacing: 6) {
                    if showsSnippet {
                        Text(snippetText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }

                    ClawdSpriteView(state: visualState, displayHeight: petHeight)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .opacity(focusQuiet && voice.phase == .idle && !voice.isAwakeForNudge ? 0.72 : 1)
                }
                .position(position)
                .gesture(dragOrTapGesture(in: size))
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
            }
            .onAppear {
                placeIfNeeded(in: size)
            }
            .onChange(of: size) { _, newSize in
                clampPosition(in: newSize)
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: - State mapping

    private var focusQuiet: Bool {
        route == .focusLive
    }

    private var visualState: ClawdAnimState {
        if isDragging {
            return dragDirection
        }
        switch voice.phase {
        case .idle:
            return .idle
        case .connecting:
            return .waving
        case .listening:
            return .waiting
        case .thinking:
            return .running
        case .speaking:
            return .review
        case .error:
            return .failed
        }
    }

    private var showsSnippet: Bool {
        switch voice.phase {
        case .connecting, .error:
            return true
        case .listening, .thinking, .speaking:
            return !snippetText.isEmpty
        case .idle:
            return false
        }
    }

    private var snippetText: String {
        if voice.phase == .connecting { return "Waking…" }
        if voice.phase == .error, let err = voice.lastError, !err.isEmpty {
            return err
        }
        return voice.transcriptSnippet
    }

    private var accessibilityLabel: String {
        if focusQuiet && voice.phase == .idle {
            return "Clawd sleeping during focus"
        }
        switch voice.phase {
        case .idle: return "Clawd, tap to talk"
        case .connecting: return "Clawd connecting, tap to cancel"
        case .listening: return "Clawd listening, tap to sleep"
        case .thinking: return "Clawd thinking, tap to cancel"
        case .speaking: return "Clawd speaking, tap to sleep"
        case .error: return "Clawd error, tap to retry"
        }
    }

    // MARK: - Interaction

    private func handleTap() {
        guard !isDragging else { return }
        // During Focus live, ignore taps while asleep — only proactive nudges wake.
        if focusQuiet && voice.phase == .idle {
            return
        }
        voice.toggleListen()
    }

    private func dragOrTapGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 6 {
                    if dragStart == nil {
                        dragStart = position
                        isDragging = true
                    }
                    guard let start = dragStart else { return }
                    let next = CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                    if value.translation.width < -2 {
                        dragDirection = .runningLeft
                    } else if value.translation.width > 2 {
                        dragDirection = .runningRight
                    }
                    position = clamped(next, in: size)
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                let wasDragging = isDragging
                dragStart = nil
                isDragging = false
                if wasDragging {
                    storedX = position.x
                    storedY = position.y
                } else if distance < 8 {
                    handleTap()
                }
            }
    }

    private func placeIfNeeded(in size: CGSize) {
        guard !hasPlaced else {
            clampPosition(in: size)
            return
        }
        hasPlaced = true
        if storedX > 0, storedY > 0 {
            position = clamped(CGPoint(x: storedX, y: storedY), in: size)
        } else {
            // Default: bottom-trailing, clear of home indicator.
            position = clamped(
                CGPoint(x: size.width - 56, y: size.height - 110),
                in: size
            )
            storedX = position.x
            storedY = position.y
        }
    }

    private func clampPosition(in size: CGSize) {
        position = clamped(position, in: size)
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let halfW: CGFloat = 48
        let halfH: CGFloat = petHeight / 2 + 24
        return CGPoint(
            x: min(max(point.x, margin + halfW), size.width - margin - halfW),
            y: min(max(point.y, margin + halfH + 40), size.height - margin - halfH)
        )
    }
}
