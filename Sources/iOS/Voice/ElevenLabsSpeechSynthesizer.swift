import AVFoundation
import Foundation

/// ElevenLabs text-to-speech for the floating assistant voice.
@MainActor
final class ElevenLabsSpeechSynthesizer {
    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?

    var isSpeaking: Bool { player?.isPlaying == true }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
    }

    func speak(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = VoiceConfig.elevenLabsKey
        guard !key.isEmpty else {
            throw VoiceAssistantError.missingElevenLabsKey
        }

        stop()

        let voiceID = VoiceConfig.elevenLabsVoiceID
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128") else {
            throw VoiceAssistantError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": trimmed,
            "model_id": "eleven_turbo_v2_5",
            "voice_settings": [
                "stability": 0.45,
                "similarity_boost": 0.75,
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw VoiceAssistantError.elevenLabsHTTP(body)
        }

        try configureSessionForPlayback()
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        self.player = player
        player.play()

        // Wait until playback finishes (or cancel).
        while player.isPlaying {
            try await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
        }
    }

    /// Prefer spokenAudio over aggressive session flips so ARKit face tracking stays alive.
    /// Does not deactivate the shared session after playback (deactivation can kill AR audio I/O).
    /// Residual risk: category/mode changes may still briefly interrupt ARKit on some devices.
    private func configureSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true)
    }
}

enum VoiceAssistantError: LocalizedError {
    case missingOpenAIKey
    case missingElevenLabsKey
    case badURL
    case elevenLabsHTTP(String)
    case realtimeNotConnected
    case realtimeError(String)
    case speechPermissionDenied

    var errorDescription: String? {
        switch self {
        case .missingOpenAIKey: return "Set OPENAI_API_KEY in Info.plist or scheme env."
        case .missingElevenLabsKey: return "Set ELEVENLABS_API_KEY in Info.plist or scheme env."
        case .badURL: return "Invalid voice API URL."
        case .elevenLabsHTTP(let body): return "ElevenLabs error: \(body.prefix(160))"
        case .realtimeNotConnected: return "Realtime session not connected."
        case .realtimeError(let msg): return "Realtime: \(msg.prefix(160))"
        case .speechPermissionDenied: return "Microphone / speech recognition permission denied."
        }
    }
}
