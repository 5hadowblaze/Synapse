import SwiftUI

/// Floating tap-to-talk orb — brand-visible, calm teal language matching Focus.
/// Hit target stays a fixed circle; never let rings expand to fill the overlay.
struct VoiceAssistantOrbView: View {
    @Bindable var voice: VoiceAssistantController

    private let orbSize: CGFloat = 58

    var body: some View {
        // Alignment overlay only — empty regions must not intercept Focus / Hub taps.
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    if showsSnippet {
                        Text(snippetText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: 200, alignment: .trailing)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                    }

                    Button {
                        voice.toggleListen()
                    } label: {
                        ZStack {
                            // Soft wash — clipped to orb bounds so it cannot steal taps.
                            Circle()
                                .fill(orbFill.opacity(0.35))
                                .frame(width: orbSize + 10, height: orbSize + 10)
                                .blur(radius: 8)
                                .opacity(phase == .idle ? 0.35 : 0.7)

                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [orbFill, orbFill.opacity(0.72)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: orbSize, height: orbSize)

                            // Inner quiet ring — brand, not stock chrome.
                            Circle()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                .frame(width: orbSize - 10, height: orbSize - 10)

                            Image(systemName: orbIcon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .symbolEffect(.pulse, isActive: phase == .listening || phase == .speaking || phase == .connecting)
                        }
                        // Hard bound: prior full-screen Circle bug swallowed taps.
                        .frame(width: orbSize + 12, height: orbSize + 12)
                        .clipped()
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: orbSize + 12, height: orbSize + 12)
                    .contentShape(Circle())
                    .accessibilityLabel(accessibilityLabel)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 28)
                .allowsHitTesting(true)
            }
    }

    private var phase: VoiceAssistantPhase { voice.phase }

    private var showsSnippet: Bool {
        switch phase {
        case .listening, .thinking, .speaking, .connecting, .error:
            return !snippetText.isEmpty || phase == .connecting || phase == .error
        case .idle:
            return false
        }
    }

    private var snippetText: String {
        if phase == .connecting {
            return "Connecting…"
        }
        if phase == .error, let err = voice.lastError, !err.isEmpty {
            return err
        }
        return voice.transcriptSnippet
    }

    /// Teal family for idle/listen/speak; sand for thinking; warm amber for error.
    private var orbFill: Color {
        switch phase {
        case .idle:
            return Color(red: 0.28, green: 0.62, blue: 0.60)
        case .connecting:
            return Color(red: 0.32, green: 0.58, blue: 0.62)
        case .listening:
            return Color(red: 0.35, green: 0.72, blue: 0.68)
        case .thinking:
            return Color(red: 0.85, green: 0.70, blue: 0.42)
        case .speaking:
            return Color(red: 0.42, green: 0.68, blue: 0.78)
        case .error:
            return Color(red: 0.93, green: 0.56, blue: 0.30)
        }
    }

    private var orbIcon: String {
        switch phase {
        case .idle: return "waveform"
        case .connecting: return "ellipsis"
        case .listening: return "mic.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "Voice assistant, tap to talk"
        case .connecting: return "Connecting, tap to cancel"
        case .listening: return "Listening, tap to end"
        case .thinking: return "Thinking, tap to cancel"
        case .speaking: return "Speaking, tap to cancel"
        case .error: return "Voice error, tap to retry"
        }
    }
}
