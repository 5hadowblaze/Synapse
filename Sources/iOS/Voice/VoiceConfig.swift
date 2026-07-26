import Foundation

/// Voice agent config. Prefer scheme env vars, then Info.plist, then local secrets plist.
/// Never commit real keys — see AGENTS.md / VoiceSecrets.plist.example.
/// Full dashboard setup: docs/ELEVENLABS_AGENT.md
enum VoiceConfig {
    /// Public Conversational Agent ID (required for voice).
    static var elevenLabsAgentID: String {
        string(for: "ELEVENLABS_AGENT_ID")
    }

    /// Optional TTS voice override (Aerisita). Override with ELEVENLABS_VOICE_ID.
    static var elevenLabsVoiceID: String {
        let id = string(for: "ELEVENLABS_VOICE_ID")
        return id.isEmpty ? "03vEurziQfq3V8WZhQvn" : id
    }

    /// Optional — not required for public-agent WebRTC. Kept for future token backends.
    static var elevenLabsKey: String {
        string(for: "ELEVENLABS_API_KEY")
    }

    /// Optional — Focus pattern tip polish only; not used by the voice agent.
    static var openAIKey: String {
        string(for: "OPENAI_API_KEY")
    }

    /// Voice is ready when a public agent ID is present.
    static var isConfigured: Bool {
        !elevenLabsAgentID.isEmpty
    }

    private static func string(for key: String) -> String {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String, !plist.isEmpty {
            return plist
        }
        if let secrets = loadSecretsPlist()?[key] as? String, !secrets.isEmpty {
            return secrets
        }
        return ""
    }

    private static func loadSecretsPlist() -> [String: Any]? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "VoiceSecrets", withExtension: "plist"),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("VoiceSecrets.plist"),
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            return dict
        }
        return nil
    }
}
