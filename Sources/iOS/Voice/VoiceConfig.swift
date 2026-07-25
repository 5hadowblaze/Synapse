import Foundation

/// API keys for voice assistant. Prefer scheme env vars, then Info.plist, then local secrets plist.
/// Never commit real keys — see AGENTS.md / VoiceSecrets.plist.example.
enum VoiceConfig {
    static var openAIKey: String {
        string(for: "OPENAI_API_KEY")
    }

    static var elevenLabsKey: String {
        string(for: "ELEVENLABS_API_KEY")
    }

    /// Default ElevenLabs voice; override with ELEVENLABS_VOICE_ID.
    static var elevenLabsVoiceID: String {
        let id = string(for: "ELEVENLABS_VOICE_ID")
        return id.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : id // Rachel
    }

    /// Realtime model id (override with OPENAI_REALTIME_MODEL).
    static var realtimeModel: String {
        let id = string(for: "OPENAI_REALTIME_MODEL")
        return id.isEmpty ? "gpt-4o-realtime-preview" : id
    }

    static var isConfigured: Bool {
        !openAIKey.isEmpty && !elevenLabsKey.isEmpty
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

    /// Optional local file: put `VoiceSecrets.plist` in the app container Documents
    /// (or rely on scheme env / Info.plist). Bundle lookup is best-effort only.
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
