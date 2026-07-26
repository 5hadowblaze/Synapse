import SwiftUI

/// Plays one Clawd animation state from the atlas at the clip's FPS.
struct ClawdSpriteView: View {
    let state: ClawdAnimState
    var displayHeight: CGFloat = 88

    @State private var frameIndex = 0
    @State private var lastTick: Date = .distantPast

    private var atlas: ClawdAtlas { .shared }
    private var clip: ClawdAnimClip { atlas.clip(for: state) }

    private var aspect: CGFloat { 192.0 / 208.0 }
    private var displayWidth: CGFloat { displayHeight * aspect }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / max(clip.fps, 1), paused: false)) { context in
            let image = atlas.frameImage(state: state, index: frameIndex)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: displayWidth, height: displayHeight)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: displayWidth, height: displayHeight)
                        .overlay {
                            Text("?")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .onChange(of: context.date) { _, date in
                advanceIfNeeded(at: date)
            }
        }
        .frame(width: displayWidth, height: displayHeight)
        .onChange(of: state) { _, _ in
            frameIndex = 0
            lastTick = .distantPast
        }
        .accessibilityHidden(true)
    }

    private func advanceIfNeeded(at date: Date) {
        let interval = 1.0 / max(clip.fps, 1)
        guard date.timeIntervalSince(lastTick) >= interval else { return }
        lastTick = date
        if clip.loop {
            frameIndex = (frameIndex + 1) % max(clip.frames, 1)
        } else if frameIndex < clip.frames - 1 {
            frameIndex += 1
        }
    }
}
