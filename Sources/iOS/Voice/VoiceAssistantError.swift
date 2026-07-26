import Foundation

enum VoiceAssistantError: LocalizedError {
    case missingAgentID
    case speechPermissionDenied
    case badURL
    case agentError(String)

    var errorDescription: String? {
        switch self {
        case .missingAgentID:
            return "Set ELEVENLABS_AGENT_ID in scheme env, Info.plist, or VoiceSecrets.plist."
        case .speechPermissionDenied:
            return "Microphone permission is required for the voice coach."
        case .badURL:
            return "Invalid voice endpoint URL."
        case .agentError(let message):
            return message
        }
    }
}
