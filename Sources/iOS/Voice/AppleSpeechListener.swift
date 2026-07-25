import AVFoundation
import Foundation
import Speech

/// On-device listen → transcript (Apple Speech). Feeds OpenAI Realtime as text.
@MainActor
final class AppleSpeechListener: NSObject {
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastPartial = ""
    private var finalContinuation: CheckedContinuation<String, Error>?

    private(set) var isListening = false
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        return await requestMicrophonePermission()
    }

    func start() throws {
        stop(cancelPending: true)
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw VoiceAssistantError.speechPermissionDenied
        }

        // Soften vs ARKit face tracking: avoid notifyOthersOnDeactivation and don't
        // deactivate on stop — category thrash can stall the front-camera session.
        // Residual risk: playAndRecord + voiceChat may still briefly reconfigure audio I/O.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try session.setActive(true)

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer = recognizer
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceAssistantError.speechPermissionDenied
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        lastPartial = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.lastPartial = text
                    if result.isFinal {
                        self.finish(with: text)
                    } else {
                        self.onPartial?(text)
                    }
                }
                if let error {
                    // Prefer last partial if user already stopped.
                    if !self.lastPartial.isEmpty, self.finalContinuation != nil || !self.isListening {
                        self.finish(with: self.lastPartial)
                    } else {
                        self.onError?(error)
                        self.finalContinuation?.resume(throwing: error)
                        self.finalContinuation = nil
                        self.stop(cancelPending: false)
                    }
                }
            }
        }
    }

    /// End audio capture and wait for a final (or last partial) transcript.
    func stopAndFinalize(timeoutSeconds: Double = 1.2) async throws -> String {
        guard isListening || request != nil else {
            let text = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw CancellationError() }
            return text
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        isListening = false

        return try await withCheckedThrowingContinuation { cont in
            self.finalContinuation = cont
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let pending = self.finalContinuation else { return }
                self.finalContinuation = nil
                let text = self.lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    pending.resume(throwing: CancellationError())
                } else {
                    self.onFinal?(text)
                    pending.resume(returning: text)
                }
                self.cleanupRecognition()
            }
        }
    }

    func stop() {
        stop(cancelPending: true)
    }

    private func stop(cancelPending: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        cleanupRecognition()
        isListening = false
        if cancelPending, let cont = finalContinuation {
            finalContinuation = nil
            cont.resume(throwing: CancellationError())
        }
    }

    private func finish(with text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onFinal?(trimmed)
        if let cont = finalContinuation {
            finalContinuation = nil
            cont.resume(returning: trimmed)
        }
        cleanupRecognition()
        isListening = false
    }

    private func cleanupRecognition() {
        task = nil
        request = nil
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}
