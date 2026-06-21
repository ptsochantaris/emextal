import AVFoundation
import Foundation
import MLXLMCommon
import SwiftUI
import WebKit
import MLX

// TODO: configurable context size

@Observable final class Conversation {
    private let messageLog = MessageLog()
    private let speaker: Speaker
    private let mic: Mic
    private let brain: Brain

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

    var mode = ConversationMode.loading(progress: 0, status: [])

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

    let displayName: String
    let supportsImageInputs: Bool
    private let historyPath: URL

    init(model: Model, speaker: Speaker, mic: Mic) {
        self.speaker = speaker
        self.mic = mic
        brain = Brain(model: model)
        displayName = model.variant.displayName
        supportsImageInputs = model.variant.architecture.supportsImageInputs
        historyPath = model.modelHistoryPath

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

    // Barge-in: invoked by the mic the moment the user starts speaking. If the assistant is
    // generating or speaking a reply, cancel it and silence the speaker so the user's new
    // utterance takes over. The mic stays live throughout, so this is only reachable in
    // voice-activated mode (the only mode where the VAD runs during a reply).
    func userDidStartSpeaking() {
        guard activationState == .voiceActivated else {
            return
        }
        switch mode {
        case .processingPrompt, .replying:
            mode.task?.cancel()
            Task {
                await speaker.stopSpeaking()
            }
        case .booting, .error, .listening, .loaded, .loading, .shutdown, .startup, .transcribing, .transcribingDone, .waiting, .warmup:
            break
        }
    }

    private var statusComponents = [
        LoadingProgressDisplay.Status(phase: .waiting, text: "Text-to-Speech"),
        LoadingProgressDisplay.Status(phase: .waiting, text: "Voice Recognition"),
        LoadingProgressDisplay.Status(phase: .waiting, text: "Language Model"),
        LoadingProgressDisplay.Status(phase: .waiting, text: "Ready")
    ]

    private func setStatus(_ text: String, to phase: LoadingProgressDisplay.Status.Phase, loadProgress: Progress) {
        if let index = statusComponents.firstIndex(where: { $0.text == text }) {
            statusComponents[index] = .init(phase: phase, text: statusComponents[index].text)
            mode = .loading(progress: loadProgress.fractionCompleted, status: statusComponents)
        } else {
            log("Warning: could not find status for \(text)")
        }
    }

    private func boot() async {
        await mic.setModeDelegate(self)

        Memory.cacheLimit = 1024 * 1024 * 16 // 16Mb

        do {
            let logTask = Task {
                try await messageLog.loadHistory(from: historyPath)
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
                    setStatus("Text-to-Speech", to: .loading, loadProgress: loadProgress)
                    await speaker.waitForBoot()
                    setStatus("Text-to-Speech", to: .done, loadProgress: loadProgress)
                }

                let t2 = Task {
                    loadProgress.addChild(mic.loadingProgress, withPendingUnitCount: 150)
                    setStatus("Voice Recognition", to: .loading, loadProgress: loadProgress)
                    await mic.waitForBoot()
                    setStatus("Voice Recognition", to: .done, loadProgress: loadProgress)
                }

                try await logTask.value
                await t1.value
                await t2.value
            }

            setStatus("Language Model", to: .loading, loadProgress: loadProgress)
            try await brain.install(parentProgress: loadProgress, progressCount: 700)
            setStatus("Language Model", to: .done, loadProgress: loadProgress)

            setStatus("Ready", to: .warmup, loadProgress: loadProgress)

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
        let asHistory = await messageLog.asSessionHistory

        guard let session = brain.makeSession(history: asHistory.data()) else {
            return
        }

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
                // The autodetect loop is already running continuously; just return to
                // quietly listening for the next utterance.
                setListeningQuietMode()
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

        let images = [attached]
            .compactMap { $0?.cgImage }
            .map { CIImage(cgImage: $0) }
            .map { UserInput.Image.ciImage($0) }

        let responseTask = Task {
            var speechBuffer = ""
            speechBuffer.reserveCapacity(1024)

            var first = true

            for await token in brain.reply(in: session, to: trimmedText, images: images) {
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

            await responseEnd(speechBuffer: speechBuffer, session: session)
        }

        mode = .processingPrompt(session: session, task: responseTask)
    }

    private func responseEnd(speechBuffer: String, session: ChatSession) async {
        // A cancelled task means the user barged in: the mic is already capturing their new
        // utterance, so don't speak the trailing buffer, wait on the speaker, or touch the mode.
        if Task.isCancelled {
            messageLog.commitTurn()
            try? await messageLog.save(to: historyPath)
            return
        }

        if !textOnly, !speechBuffer.isEmpty {
            await speaker.queue(speechBuffer)
        }

        messageLog.commitTurn()

        do {
            try await messageLog.save(to: historyPath)
        } catch {
            log("Warning: Failed to save message log: \(error)")
        }

        if !textOnly {
            await speaker.waitUntilDone()
        }

        // A barge-in may have arrived while we waited for the speaker to finish.
        if Task.isCancelled {
            return
        }

        switch activationState {
        case .button:
            setMode(.waiting(session: session))

        case .voiceActivated:
            // The autodetect loop keeps running continuously; only return to quiet listening
            // if a barge-in hasn't already moved us into capturing a new utterance.
            switch mode {
            case .processingPrompt, .replying:
                setListeningQuietMode()
            case .booting, .error, .listening, .loaded, .loading, .shutdown, .startup, .transcribing, .transcribingDone, .waiting, .warmup:
                break
            }
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
            await task.value
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
        let task = mode.task
        let session = mode.session

        // Cancel and return to the idle/listening state synchronously, before any awaits. A
        // cancelled response task early-returns from `responseEnd` without restoring the mode, so
        // doing it here is what unsticks the UI — waiting on teardown first would leave it stuck in
        // the interrupted reply. The restored `.waiting`/`.listening` modes carry no task, so a late
        // token can't re-enter `.replying` (`appendText` only changes mode when `mode.task` exists).
        task?.cancel()
        switch activationState {
        case .button:
            setWaitingMode()
        case .voiceActivated:
            setListeningQuietMode()
        }

        Task {
            await speaker.stopSpeaking()
            await task?.value
            messageLog.reset()
            try? await messageLog.save(to: historyPath)
            if let session = FinalWrapper(session).data() {
                await session.clear()
            }
        }
    }
}
