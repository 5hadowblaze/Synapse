import SwiftUI

/// Persistent floating specular camera preview — desk-accessory chrome, not Focus-only.
/// Shares `FaceTracker.session`; never starts a second ARSession.
struct FloatingCameraPreviewView: View {
    @Bindable var model: AppModel

    private let bubbleWidth: CGFloat = 108
    private let bubbleHeight: CGFloat = 144

    /// Accent teal matching Focus / voice orb (calm dark teal — not purple).
    private let accent = Color(red: 0.35, green: 0.72, blue: 0.68)
    private let glassFill = Color(red: 0.06, green: 0.10, blue: 0.11).opacity(0.82)

    var body: some View {
        // Alignment overlay only — empty regions must not intercept Hub / Focus taps.
        Color.clear
            .allowsHitTesting(false)
            .overlay {
                GeometryReader { geo in
                    let origin = clampedOrigin(in: geo)
                    bubble
                        .frame(width: bubbleWidth, height: bubbleHeight)
                        .position(
                            x: origin.x + bubbleWidth / 2,
                            y: origin.y + bubbleHeight / 2
                        )
                        .gesture(dragGesture(in: geo))
                        .allowsHitTesting(true)
                }
            }
    }

    private var bubble: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(glassFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    accent.opacity(0.22),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.1
                        )
                }
                .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
                .shadow(color: accent.opacity(0.12), radius: 8, y: 2)

            if model.isPreviewCameraActive {
                FaceARPreviewView(
                    session: model.faceTracker.session,
                    isTracked: model.faceTracker.isTracking,
                    saccadeFlashToken: 0,
                    faceMeshOpacity: 0.22,
                    showGazeRay: false,
                    showTrackingRing: false,
                    onAttached: { model.faceTracker.refreshPreviewAnchors() }
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(3)
                .allowsHitTesting(false)

                // Soft top specular — premium glass, not a neon glow.
                VStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 36)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(3)
                .allowsHitTesting(false)
            } else {
                cameraOffContent
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            model.togglePreviewCamera()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera preview")
        .accessibilityValue(model.isPreviewCameraActive ? "On" : "Off")
        .accessibilityHint(
            model.isPreviewCameraActive
                ? "Double tap to turn camera off"
                : "Double tap to turn camera on"
        )
        .accessibilityAddTraits(.isButton)
    }

    private var cameraOffContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent.opacity(0.85))
            Text("Camera off")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text("Tap to enable")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 10)
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let base = model.previewDragBaseOrigin ?? clampedOrigin(in: geo)
                if model.previewDragBaseOrigin == nil {
                    model.previewDragBaseOrigin = base
                }
                let next = CGPoint(
                    x: base.x + value.translation.width,
                    y: base.y + value.translation.height
                )
                model.setPreviewOrigin(next, in: geo.size, safe: geo.safeAreaInsets)
            }
            .onEnded { _ in
                model.previewDragBaseOrigin = nil
                model.persistPreviewOrigin()
            }
    }

    private func clampedOrigin(in geo: GeometryProxy) -> CGPoint {
        model.previewOrigin(in: geo.size, safe: geo.safeAreaInsets, bubble: CGSize(width: bubbleWidth, height: bubbleHeight))
    }
}
