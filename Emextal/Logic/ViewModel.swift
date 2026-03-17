import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXLMCommon
import MLXVLM
import SwiftUI
import WebKit

/// Only for reference passing
extension ChatSession: @unchecked @retroactive Sendable {}
extension Chat.Message: @unchecked @retroactive Sendable {}

@Observable final class ViewModel {
    private let modelConfiguration = ModelConfiguration(
        // id: "mlx-community/Qwen3.5-27B-4bit"
        id: "mlx-community/Qwen3.5-35B-A3B-4bit"
    )

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

    var mode = AppMode.loading(progress: 0, status: []) {
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

    init() {
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

    var displayName: String {
        modelConfiguration.name
    }

    var supportsImageInputs: Bool {
        true
    }

    func setWebView(_ webView: WKWebView) async {
        await messageLog.setWebView(webView)
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

    func playEffect(_ effect: SoundEffect) {
        speaker.playEffect(effect)
    }

    private func boot() async {
        await mic.setModeDelegate(self)

        do {
            let logTask = Task {
                try await messageLog.loadHistory(from: sessionUrl)
            }

            var addedChild = false
            var statusComponents = ["Language Model", "Text-to-Speech", "Voice Recognition"].map { LoadingProgressDisplay.Status(loaded: false, text: $0) }

            let loadProgress = Progress(totalUnitCount: 1000)
            let observer = loadProgress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, change in
                if let fraction = change.newValue {
                    Task { @MainActor in
                        log("Progress: \(fraction)")
                        self?.mode = .loading(progress: fraction, status: statusComponents)
                    }
                }
            }

            let speakerTask = Task {
                try await speaker.boot()
                loadProgress.completedUnitCount += 100
                if let index = statusComponents.firstIndex(where: { $0.text == "Text-to-Speech" }) {
                    statusComponents[index] = .init(loaded: true, text: statusComponents[index].text)
                }
            }

            let micTask = Task {
                try await mic.boot()
                loadProgress.completedUnitCount += 100
                if let index = statusComponents.firstIndex(where: { $0.text == "Voice Recognition" }) {
                    statusComponents[index] = .init(loaded: true, text: statusComponents[index].text)
                }
            }

            let warmupTask = Task {
                try await speakerTask.value
                try await micTask.value

                engine.inputNode.volume = 1.0
                try engine.start()

                loadProgress.completedUnitCount += 50

                try await speaker.warmup()
                try await mic.warmup()

                loadProgress.completedUnitCount += 50

                try await logTask.value
            }

            let model = try await VLMModelFactory.shared.loadContainer(configuration: modelConfiguration) { progress in
                Task { @MainActor in
                    if !addedChild {
                        loadProgress.addChild(progress, withPendingUnitCount: 700)
                        addedChild = true
                    }
                }
            }

            if let index = statusComponents.firstIndex(where: { $0.text == "Language Model" }) {
                statusComponents[index] = .init(loaded: true, text: statusComponents[index].text)
                mode = .loading(progress: loadProgress.fractionCompleted, status: statusComponents)
            }

            try? await Task.sleep(for: .seconds(1.0))

            try await warmupTask.value

            /* Qwen 3.5:
             Thinking mode for general tasks: temperature=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0
             Thinking mode for precise coding tasks (e.g. WebDev): temperature=0.6, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=0.0, repetition_penalty=1.0
             Instruct (or non-thinking) mode for general tasks: temperature=0.7, top_p=0.8, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0
             Instruct (or non-thinking) mode for reasoning tasks: temperature=1.0, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0
             */

            let asHistory = await messageLog.asSessionHistory

            let session = ChatSession(
                model,
                history: asHistory,
                generateParameters: GenerateParameters(
                    temperature: 0.7,
                    topP: 0.8,
                    topK: 20,
                    minP: 0,
                    presencePenalty: 1.5,
                    frequencyPenalty: 1
                ),
                additionalContext: ["enable_thinking": false]
            )

            mode = .waiting(session: session)

            withExtendedLifetime(observer) {
                $0.invalidate()
            }

            recognitionLoop = Task {
                for await text in mic.phraseStream {
                    receivedPhrase(text, in: session)
                }
            }

            #if DEBUG
                Task {
                    let format = ByteCountFormatStyle(style: .memory, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: .autoupdatingCurrent)
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        print("""

                        Memory stats:
                              Active: \(format.format(Int64(Memory.activeMemory))) (Peak: \(format.format(Int64(Memory.peakMemory))))
                               Cache: \(format.format(Int64(Memory.cacheMemory))) (Limit: \(format.format(Int64(Memory.cacheLimit))))
                               Total: \(format.format(Int64(Memory.activeMemory + Memory.cacheMemory))) / \(format.format(Int64(Memory.memoryLimit)))

                        """)
                    }
                }
            #endif

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

        let responseTask = Task { @DefaultQueueActor in
            var charBuffer = ""
            charBuffer.reserveCapacity(1024)

            var lineBuffer = ""
            lineBuffer.reserveCapacity(1024)

            var first = true
            let images = [attached]
                .compactMap { unsafe $0?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .map { CIImage(cgImage: $0) }
                .map { UserInput.Image.ciImage($0) }

            for try await item in session.streamResponse(to: trimmedText, images: images, videos: []) {
                for char in item {
                    switch char {
                    case ",", ":", "!", "?", ".", ")", "\n":
                        charBuffer.append(char)
                        await appendText(charBuffer, session: session, first: &first)
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

            await appendText(charBuffer, session: session, first: &first)

            await responseEnd(lineBuffer: lineBuffer, session: session)
        }

        mode = .processingPrompt(session: session, task: responseTask)
    }

    private var sessionUrl: URL {
        get throws {
            let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return root.appendingPathComponent("messageLog.json", conformingTo: .json)
        }
    }

    private func responseEnd(lineBuffer: String, session: ChatSession) async {
        if !textOnly, !lineBuffer.isEmpty {
            await speaker.queue(lineBuffer)
        }

        messageLog.commitTurn()

        do {
            try await messageLog.save(to: sessionUrl)
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

        if let session = mode.session {
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
            try? await messageLog.save(to: sessionUrl)
            if let session = mode.session {
                await session.clear()
            }
        }
    }
}
