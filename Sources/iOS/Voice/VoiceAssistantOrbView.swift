import SwiftUI

/// Floating tap-to-talk orb overlay for the Synapse voice assistant.
struct VoiceAssistantOrbView: View {
    @Bindable var voice: VoiceAssistantController

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if showsSnippet {
                        Text(snippetText)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: 200, alignment: .trailing)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        voice.toggleListen()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(orbFill)
                                .frame(width: 58, height: 58)
                                .shadow(color: orbGlow, radius: phase == .listening || phase == .speaking ? 12 : 4)

                            Circle()
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)

                            Image(systemName: orbIcon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .symbolEffect(.pulse, isActive: phase == .listening || phase == .speaking)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 28)
            }
        }
        .allowsHitTesting(true)
    }

    private var phase: VoiceAssistantPhase { voice.phase }

    private var showsSnippet: Bool {
        switch phase {
        case .listening, .thinking, .speaking, .error:
            return !snippetText.isEmpty
        case .idle:
            return false
        }
    }

    private var snippetText: String {
        if phase == .error, let err = voice.lastError, !err.isEmpty {
            return err
        }
        return voice.transcriptSnippet
    }

    private var orbFill: Color {
        switch phase {
        case .idle: return Color.cyan.opacity(0.55)
        case .listening: return Color.green.opacity(0.75)
        case .thinking: return Color.orange.opacity(0.7)
        case .speaking: return Color.blue.opacity(0.75)
        case .error: return Color.red.opacity(0.75)
        }
    }

    private var orbGlow: Color {
        switch phase {
        case .listening: return .green.opacity(0.55)
        case .speaking: return .blue.opacity(0.5)
        case .error: return .red.opacity(0.45)
        default: return .cyan.opacity(0.25)
        }
    }

    private var orbIcon: String {
        switch phase {
        case .idle: return "waveform.circle.fill"
        case .listening: return "mic.fill"
        case .thinking: return "ellipsis"
        case .speaking: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "Voice assistant, tap to talk"
        case .listening: return "Listening, tap to send"
        case .thinking: return "Thinking, tap to cancel"
        case .speaking: return "Speaking, tap to cancel"
        case .error: return "Voice error, tap to retry"
        }
    }
}
