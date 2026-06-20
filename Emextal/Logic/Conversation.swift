import AVFoundation
import Foundation
import MLXLMCommon
import SwiftUI
import WebKit

@Observable final class Conversation {
    private let messageLog = MessageLog()
    private let speaker: Speaker
    private let mic: Mic

    private(set) var micPermission = false
    private(set) var activationState = ActivationState.button
    private(set) var recognitionLoop: Task<Void, Never>?

    var prompt = ""
    var attachedImage: ImageClass?
    let memoryStats = MemoryStats()

    var textOnly = Persisted.textOnly {
        didSet {
            Persisted.textOnly = textOnly
        }
    }

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

    init(model: Model, speaker: Speaker, mic: Mic) {
        self.model = model
        self.speaker = speaker
        self.mic = mic

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

    func playEffect(_ effect: SoundEffect) {
        speaker.playEffect(effect)
    }

    func setListeningTalkingMode() {
        guard let session = mode.session else {
            return
        }
        setMode(.listening(state: .talking, session: session))
    }

    func setTranscribingMode() {
        guard let session = mode.session else {
            return
        }
        setMode(.transcribing(session: session))
    }

    func setListeningQuietMode() {
        guard let session = mode.session else {
            return
        }
        setMode(.listening(state: .quiet, session: session))
    }

    func setWaitingMode() {
        guard let session = mode.session else {
            return
        }
        setMode(.waiting(session: session))
    }

    private var statusComponents = [
        LoadingProgressDisplay.Status(phase: .loading, text: "Text-to-Speech"),
        LoadingProgressDisplay.Status(phase: .loading, text: "Voice Recognition"),
        LoadingProgressDisplay.Status(phase: .loading, text: "Language Model"),
        LoadingProgressDisplay.Status(phase: .waiting, text: "Ready")
    ]

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
            nonisolated(unsafe) var lastFraction: Double = 0
            let observer = loadProgress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, change in
                if let fraction = change.newValue {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if unsafe fraction > lastFraction {
                            unsafe lastFraction = fraction
                            mode = .loading(progress: fraction, status: statusComponents)
                        }
                    }
                }
            }

            let warmupTask = Task {
                let t1 = Task {
                    loadProgress.addChild(speaker.loadingProgress, withPendingUnitCount: 150)
                    await speaker.waitForBoot()
                    setStatus("Text-to-Speech", to: .done, loadProgress: loadProgress)
                }

                let t2 = Task {
                    loadProgress.addChild(mic.loadingProgress, withPendingUnitCount: 150)
                    await mic.waitForBoot()
                    setStatus("Voice Recognition", to: .done, loadProgress: loadProgress)
                }

                try await logTask.value
                await t1.value
                await t2.value
            }

            try await model.install(parentProgress: loadProgress, progressCount: 700)

            setStatus("Language Model", to: .done, loadProgress: loadProgress)

            try? await Task.sleep(for: .seconds(0.1))

            try await warmupTask.value

            withExtendedLifetime(observer) {
                $0.invalidate()
            }

            mode = .loaded
        } catch {
            mode = .error(error)
        }
    }

    func start() {
        Task {
            await mainLoop()
        }
    }

    private func mainLoop() async {
        guard let modelContainer = model.modelContainer else {
            log("Warning: The model is not installed.")
            return
        }

        let asHistory = await messageLog.asSessionHistory

        let session = ChatSession(
            modelContainer,
            history: asHistory.data(),
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

    private func respond(session: ChatSession) {
        guard mode.canRespond else { return }

        let trimmedText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let attached = attachedImage
        messageLog.prompt(text: trimmedText, image: attached)
        if attached != nil {
            attachedImage = nil
        }
        prompt = ""

        let tokenIngestion = TokenIngestion(initialBuffer: model.variant.injectThinkingTag ? "<think>" : "")

        let textProcessor = TextProcessor(harmony: model.variant.usesHarmony ? .idle : .notApplicable)

        let responseTask = Task {

            var speechBuffer = ""
            speechBuffer.reserveCapacity(1024)

            var first = true
            let images = [attached]
                .compactMap { $0?.cgImage }
                .map { CIImage(cgImage: $0) }
                .map { UserInput.Image.ciImage($0) }

            let tokenTask = Task {
                defer {
                    tokenIngestion.done()
                }
                for try await item in session.streamResponse(to: trimmedText, images: images, videos: []) {
                    tokenIngestion.ingest(text: item)
                }
            }

            let processorTask = Task {
                defer {
                    textProcessor.done()
                }
                for await item in tokenIngestion.output {
                    textProcessor.ingest(token: item)
                }
            }

            for await token in textProcessor.output {
                switch token {
                case let .text(item):
                    appendText(item, session: session, first: &first)
                    speechBuffer.append(item)
                    switch speechBuffer.last {
                    case ":", "!", "?", ".", ")", "\n":
                        if !textOnly {
                            await speaker.queue(speechBuffer)
                        }
                        speechBuffer.removeAll(keepingCapacity: true)
                    default: break
                    }

                case let .tag(token):
                    appendText(token, session: session, first: &first)
                    speechBuffer.append(token)
                }
            }

            _ = await processorTask.value
            _ = try await tokenTask.value

            await responseEnd(speechBuffer: speechBuffer, session: session)
        }

        mode = .processingPrompt(session: session, task: responseTask)
    }

    private func responseEnd(speechBuffer: String, session: ChatSession) async {
        if !textOnly, !speechBuffer.isEmpty {
            await speaker.queue(speechBuffer)
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
        await speaker.stopSpeaking()
        await mic.stop()

        if let task = mode.task {
            task.cancel()
            try? await task.value
        }

        if let session = FinalWrapper(mode.session).data() {
            await session.synchronize()
            await session.clear()
        }

        messageLog.shutdown()

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
            await speaker.stopSpeaking()
            if let task = mode.task {
                task.cancel()
                try? await task.value
            }
            messageLog.reset()
            try? await messageLog.save(to: model.modelHistoryPath)
            if let session = FinalWrapper(mode.session).data() {
                await session.clear()
            }
        }
    }
}
