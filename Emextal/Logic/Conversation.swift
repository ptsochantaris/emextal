import AVFoundation
import Foundation
import MLXAudioCore
import MLXAudioSTT
import MLXLLM
import MLXLMCommon
import MLXVLM
import SwiftUI
import WebKit

@Observable final class Conversation {
    private let messageLog = MessageLog()
    private let engine = AVAudioEngine()
    private let speaker: Speaker
    private let mic: Mic

    private(set) var micPermission = false
    private(set) var activationState = ActivationState.button
    private(set) var recognitionLoop: Task<Void, Never>?

    var prompt = ""
    var attachedImage: NSImage?
    var textOnly = true
    let memoryStats = MemoryStats()

    var mode = ConversationMode.loading(progress: 0, status: []) {
        didSet {
            if oldValue != mode {
                Task {
                    await mic.setIgnoreMic(mode.shouldIgnoreMic)
                }
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

    let model: Model

    init(model: Model) {
        self.model = model

        nonisolated(unsafe) let engineRef = engine
        unsafe speaker = Speaker(engine: engineRef)
        unsafe mic = Mic(engine: engineRef)

        Task {
            micPermission = await AVCaptureDevice.requestAccess(for: .audio)
        }

        Task {
            await boot()
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }

    var displayName: String {
        model.variant.displayName
    }

    var supportsImageInputs: Bool {
        model.variant.architecture.supportsImageInputs
    }

    func setWebView(_ webView: WKWebView) async {
        await messageLog.setWebView(webView)
    }

    func getMode() -> ConversationMode {
        mode
    }

    func setMode(_ newMode: ConversationMode) {
        mode = newMode
    }

    func getSession() -> FinalWrapper<ChatSession?> {
        FinalWrapper(mode.session)
    }

    func playEffect(_ effect: SoundEffect) {
        speaker.playEffect(effect)
    }

    private var statusComponents = [
        LoadingProgressDisplay.Status(phase: .loading, text: "Text-to-Speech"),
        LoadingProgressDisplay.Status(phase: .loading, text: "Voice Recognition"),
        LoadingProgressDisplay.Status(phase: .loading, text: "Language Model"),
        LoadingProgressDisplay.Status(phase: .waiting, text: "Ready")
    ]

    private var addedChild = false

    private func setStatus(_ text: String, to _: LoadingProgressDisplay.Status.Phase, loadProgress: Progress) {
        if let index = statusComponents.firstIndex(where: { $0.text == text }) {
            statusComponents[index] = .init(phase: .done, text: statusComponents[index].text)
            mode = .loading(progress: loadProgress.fractionCompleted, status: statusComponents)
        }
    }

    private func boot() async {
        await mic.setModeDelegate(self)

        do {
            let logTask = Task {
                try await messageLog.loadHistory(from: model.modelHistoryPath)
            }

            let loadProgress = Progress(totalUnitCount: 1000)
            let observer = loadProgress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, change in
                if let fraction = change.newValue {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        mode = .loading(progress: fraction, status: statusComponents)
                    }
                }
            }

            let speakerTask = Task {
                try await speaker.boot()
                loadProgress.completedUnitCount += 50
                setStatus("Text-to-Speech", to: .warmup, loadProgress: loadProgress)
            }

            let micTask = Task {
                try await mic.boot()
                loadProgress.completedUnitCount += 50
                setStatus("Voice Recognition", to: .warmup, loadProgress: loadProgress)
            }

            let warmupTask = Task {
                try await speakerTask.value
                try await micTask.value

                engine.inputNode.volume = 1.0
                try engine.start()

                loadProgress.completedUnitCount += 50

                try await speaker.warmup()
                setStatus("Text-to-Speech", to: .done, loadProgress: loadProgress)

                try await mic.warmup()
                setStatus("Voice Recognition", to: .done, loadProgress: loadProgress)

                loadProgress.completedUnitCount += 50

                try await logTask.value
            }

            let modelConfiguration = ModelConfiguration(id: model.variant.repoId)
            let modelContainer: ModelContainer
            let progressHandler = { @Sendable [weak self] (progress: Progress) in
                _ = Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !addedChild {
                        loadProgress.addChild(progress, withPendingUnitCount: 800)
                        addedChild = true
                    }
                }
            }

            switch model.variant.architecture {
            case .llm:
                modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration, progressHandler: progressHandler)
            case .vlm:
                modelContainer = try await VLMModelFactory.shared.loadContainer(configuration: modelConfiguration, progressHandler: progressHandler)
            }

            setStatus("Language Model", to: .done, loadProgress: loadProgress)

            try? await Task.sleep(for: .seconds(0.3))

            try await warmupTask.value

            withExtendedLifetime(observer) {
                $0.invalidate()
            }

            mode = .loaded(modelContainer: modelContainer)
        } catch {
            mode = .error(error)
        }
    }

    func start(modelContainer: ModelContainer) {
        Task {
            await _start(modelContainer: modelContainer)
        }
    }

    private func _start(modelContainer: ModelContainer) async {
        let asHistory = await messageLog.asSessionHistory

        let session = ChatSession(
            modelContainer,
            history: asHistory.data,
            generateParameters: model.params.mlx,
            additionalContext: model.additionalContext
        )

        mode = .waiting(session: session)

        recognitionLoop = Task {
            for await text in mic.phraseStream {
                receivedPhrase(text, in: session)
            }
        }
    }

    private func receivedPhrase(_ text: String, in session: ChatSession) {
        if text.isEmpty {
            switch activationState {
            case .button:
                mode = .waiting(session: session)
            case .voiceActivated:
                Task {
                    await mic.startAutodetect()
                }
            }
        } else {
            mode = .transcribingDone(session: session)
            prompt = text
            respond(session: session)
        }
    }

    private func appendText(_ text: String, session: ChatSession, first: inout Bool) {
        messageLog.appendResponse(text: text)
        if first, let task = mode.task {
            mode = .replying(session: session, task: task)
            first = false
        }
    }

    private func respond(session safeSession: ChatSession) {
        guard mode.canRespond else { return }

        let session = FinalWrapper(safeSession)

        let trimmedText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = attachedImage
        messageLog.prompt(text: trimmedText, image: attached)
        if attached != nil {
            attachedImage = nil
        }
        prompt = ""

        let responseTask = Task { @DefaultQueueActor in
            var charBuffer = await model.variant.injectThinkingTag ? "<think>" : ""
            charBuffer.reserveCapacity(1024)

            var lineBuffer = ""
            lineBuffer.reserveCapacity(1024)

            var first = true
            let images = [attached]
                .compactMap { unsafe $0?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .map { CIImage(cgImage: $0) }
                .map { UserInput.Image.ciImage($0) }

            for try await item in session.data.streamResponse(to: trimmedText, images: images, videos: []) {
                for char in item {
                    switch char {
                    case ",", ":", "!", "?", ".", ")", "\n":
                        charBuffer.append(char)
                        await appendText(charBuffer, session: session.data, first: &first)
                        charBuffer.removeAll(keepingCapacity: true)
                        if char == "\n" {
                            if await !textOnly {
                                await speaker.queue(lineBuffer)
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else {
                            lineBuffer.append(char)
                        }

                    default:
                        charBuffer.append(char)
                        lineBuffer.append(char)
                    }
                }
            }

            await appendText(charBuffer, session: session.data, first: &first)

            await responseEnd(lineBuffer: lineBuffer, session: session.data)
        }

        mode = .processingPrompt(session: session.data, task: responseTask)
    }

    private func responseEnd(lineBuffer: String, session: ChatSession) async {
        if !textOnly, !lineBuffer.isEmpty {
            await speaker.queue(lineBuffer)
        }

        messageLog.commitTurn()

        do {
            try await messageLog.save(to: model.modelHistoryPath)
        } catch {
            log("Warning: Failed to save message log: \(error)")
        }

        if !textOnly {
            await speaker.waitUntilDone()
        }

        switch activationState {
        case .button:
            setMode(.waiting(session: session))

        case .voiceActivated:
            await mic.startAutodetect()
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
            await mic.stop()
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
            await mic.startAutodetect()
        }
    }

    func shutdown() async {
        if let task = mode.task {
            task.cancel()
            try? await task.value
        }

        if let session = FinalWrapper(mode.session).data {
            await session.synchronize()
            await session.clear()
        }

        messageLog.shutdown()
        await mic.shutdown()
        await speaker.shutdown()

        mode = .shutdown
    }

    private func buttonDown() {
        guard activationState == .button else {
            return
        }
        Task {
            await mic.startManual()
        }
    }

    private func buttonUp() {
        guard activationState == .button else {
            return
        }
        Task {
            await mic.stop()
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
            // TODO: stop speaking
            messageLog.reset()
            try? await messageLog.save(to: model.modelHistoryPath)
            if let session = FinalWrapper(mode.session).data {
                await session.clear()
            }
        }
    }
}
