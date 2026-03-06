import AVFoundation
import HTMLString
import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXLLM
import MLXLMCommon
import SwiftUI

/// Only for reference passing
extension ChatSession: @unchecked @retroactive Sendable {}

@Observable final class ViewModel {
    private let modelConfiguration = LLMRegistry.llama3_8B_4bit
    private let engine = AVAudioEngine()

    private let speechQueue: SpeechQueue
    private let speakerDetector: SpeakerDetection

    private(set) var statusMessage: String?
    private(set) var micPermission = false

    let messageLog = MessageLog()

    var prompt = ""
    var activationState = ActivationState.button
    var textOnly = true
    var recognitionLoop: Task<Void, Never>?

    var mode = AppMode.loading(progress: 0) {
        didSet {
            if oldValue != mode {
                speakerDetector.ignoreMic = mode.shouldIgnoreMic
            }
        }
    }

    var buttonPushed = false {
        didSet {
            if oldValue != buttonPushed {
                if buttonPushed {
                    buttonDown()
                } else {
                    buttonUp()
                }
            }
        }
    }

    init() {
        Memory.cacheLimit = 200 * 1024 * 1024

        nonisolated(unsafe) let engineRef = engine
        speechQueue = SpeechQueue(engine: engineRef)
        speakerDetector = SpeakerDetection(engine: engineRef)

        Task {
            micPermission = await AVCaptureDevice.requestAccess(for: .audio)
        }

        Task {
            await boot()
        }
    }

    var displayName: String {
        modelConfiguration.name
    }

    func getMode() -> AppMode {
        mode
    }

    func setMode(_ newMode: AppMode) {
        mode = newMode
    }

    func getSession() -> ChatSession? {
        mode.session
    }

    private func boot() async {
        await speakerDetector.setModeDelegate(self)

        do {
            var utilProgress: Double = 0
            var modelProgress: Double = 0

            let t1 = Task {
                try await speechQueue.boot()
                utilProgress += 0.5
                mode = .loading(progress: (utilProgress * 0.3) + (modelProgress * 0.7))

                try await speakerDetector.boot()
                utilProgress += 0.5
                mode = .loading(progress: (utilProgress * 0.3) + (modelProgress * 0.7))
            }

            let model = try await Task {
                try await loadModelContainer(configuration: modelConfiguration) { value in
                    Task { @MainActor in
                        modelProgress = value.fractionCompleted
                        self.mode = .loading(progress: (utilProgress * 0.3) + (modelProgress * 0.7))
                    }
                }
            }.value

            let session = ChatSession(model, generateParameters: GenerateParameters(
                temperature: 0.6,
                topP: 0.95
            ))

            try await t1.value

            engine.inputNode.volume = 1.0
            try engine.start()

            mode = .waiting(session: session)

            recognitionLoop = Task {
                for await text in speakerDetector.phraseStream {
                    receivedPhrase(text, in: session)
                }
            }

        } catch {
            mode = .error(error)
        }
    }

    private func receivedPhrase(_ text: String, in session: ChatSession) {
        if text.isEmpty {
            switch activationState {
            case .button:
                mode = .waiting(session: session)
            case .voiceActivated:
                Task {
                    await speakerDetector.startAutodetect()
                }
            }
        } else {
            mode = .transcribingDone(session: session)
            prompt = text
            respond(session: session)
        }
    }

    private func appendText(_ text: String, session: ChatSession, first: inout Bool) {
        messageLog.appendText(text)
        if first, let task = mode.task {
            mode = .replying(session: session, task: task)
            first = false
        }
    }

    private func respond(session: ChatSession) {
        guard mode.canRespond else { return }

        let trimmedText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        messageLog.appendText("\n#### \(trimmedText.addingUnicodeEntities())\n")
        prompt = ""
        messageLog.commitNewText()

        let responseTask = Task { @UtilityActor in
            var buffer = ""
            var lineBuffer = ""
            var first = true
            for try await item in session.streamResponse(to: trimmedText) {
                for char in item {
                    buffer.append(char)
                    switch char {
                    case "!", "?", ".":
                        lineBuffer.append(char)
                        await appendText(buffer, session: session, first: &first)
                        buffer.removeAll(keepingCapacity: true)

                    case "\n":
                        if await !textOnly {
                            await speechQueue.queue(lineBuffer)
                        }
                        lineBuffer.removeAll(keepingCapacity: true)

                    default:
                        lineBuffer.append(char)
                    }
                }
            }
            await appendText(buffer, session: session, first: &first)

            await responseEnd(lineBuffer: lineBuffer, session: session)
        }

        mode = .processingPrompt(session: session, task: responseTask)
    }

    private func responseEnd(lineBuffer: String, session: ChatSession) async {
        if !textOnly, !lineBuffer.isEmpty {
            await speechQueue.queue(lineBuffer)
        }

        if !textOnly {
            await speechQueue.waitUntilDone()
        }

        switch activationState {
        case .button:
            setMode(.waiting(session: session))

        case .voiceActivated:
            await speakerDetector.startAutodetect()
        }
    }

    func respondToTypedPrompt() {
        if let session = mode.session {
            respond(session: session)
        }
    }

    func switchToPushButton() {
        guard activationState == .voiceActivated else {
            return
        }
        activationState = .button
        Task {
            await speakerDetector.stop()
            if let session = mode.session {
                mode = .waiting(session: session)
            }
        }
    }

    func switchToVoiceActivated() {
        guard activationState == .button else {
            return
        }
        activationState = .voiceActivated
        Task {
            await speakerDetector.startAutodetect()
        }
    }

    func shutdown() async {
        if let task = mode.task {
            task.cancel()
            try? await task.value
        }

        if let session = mode.session {
            await session.clear()
        }

        messageLog.shutdown()
        await speakerDetector.shutdown()
        await speechQueue.shutdown()

        mode = .shutdown
    }

    private func buttonDown() {
        guard activationState == .button else {
            return
        }
        Task {
            await speakerDetector.startManual()
        }
    }

    private func buttonUp() {
        guard activationState == .button else {
            return
        }
        Task {
            await speakerDetector.stop()
            if let session = mode.session {
                mode = .waiting(session: session)
            }
        }
    }

    func reset() {
        Task {
            if let task = mode.task {
                task.cancel()
                try? await task.value
            }
            messageLog.reset()
            if let session = mode.session {
                await session.clear()
            }
        }
    }
}
