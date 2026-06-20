import AVFoundation
import EmextalAudio
import MLX
import MLXLMCommon

private extension AVAudioPlayerNode {
    /// `stop()` synchronously blocks on the audio engine's default-QoS render thread.
    /// Calling it from a higher-QoS executor causes a priority inversion, so hop to a
    /// default-QoS queue and suspend the caller instead of blocking the thread.
    func stopOffActor() async {
        await withCheckedContinuation { continuation in
            // `.async` blocks inherit the submitting context's QoS, so a block submitted from
            // the high-QoS actor executor would be boosted back to User-initiated. Enforce the
            // Default QoS explicitly so `stop()` runs at the same level as the render thread it
            // blocks on, avoiding the priority inversion.
            DispatchQueue.global(qos: .default).async(qos: .default, flags: .enforceQoS) {
                self.stop()
                continuation.resume()
            }
        }
    }
}

final actor Speaker {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    // Each queued line carries the speaking-session token (`active`) captured when it was enqueued.
    // `stopSpeaking()` rotates that token, so any lines still buffered in the stream become stale and
    // the consumer skips them — otherwise a cancel/reset mid-reply keeps speaking the backlog.
    private let speechStream: AsyncStream<(text: String, token: UUID?)>
    private let spechContinuation: AsyncStream<(text: String, token: UUID?)>.Continuation

    private let speechPlayer = AVAudioPlayerNode()

    private let effectPlayer = AVAudioPlayerNode()
    private let effectContinuation: AsyncStream<SoundEffect>.Continuation

    init(engine: AVAudioEngine) {
        (speechStream, spechContinuation) = AsyncStream.makeStream(of: (text: String, token: UUID?).self, bufferingPolicy: .unbounded)

        engine.attach(speechPlayer)
        let speechFormat = AVAudioFormat(standardFormatWithSampleRate: 32000, channels: 1)
        engine.connect(speechPlayer, to: engine.mainMixerNode, format: speechFormat)

        engine.attach(effectPlayer)
        let effectFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: effectFormat)

        let pair = AsyncStream.makeStream(of: SoundEffect.self, bufferingPolicy: .bufferingNewest(2))
        let stream = pair.stream
        effectContinuation = pair.continuation

        Task { [weak self] in
            for await effect in stream {
                guard let self else { return }
                await handleEffect(effect)
            }
            log("Effect player queue done")
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }

    nonisolated func playEffect(_ effect: SoundEffect) {
        effectContinuation.yield(effect)
    }

    private func handleEffect(_ effect: SoundEffect) async {
        effectPlayer.volume = effect.preferredVolume
        effectPlayer.play()
        await effectPlayer.scheduleFile(effect.audioFile, at: nil)
        try? await Task.sleep(for: .seconds(1))
        await effectPlayer.stopOffActor()
    }

    func stopSpeaking() async {
        active = UUID()
        // Abort an in-flight TTS render too — SopranoModel.generate honours task cancellation — so a
        // cancel/barge-in doesn't have to wait for the current line to finish generating.
        generationTask?.cancel()
        generationTask = nil
        countInQueue = 0
        playingLatestBuffer = false
        if speechPlayer.isPlaying {
            await speechPlayer.stopOffActor()
        }
    }

    func shutdown() async {
        await stopSpeaking()
        effectContinuation.finish()
        spechContinuation.finish()
    }

    let loadingProgress = Progress(totalUnitCount: 1000)

    func boot() async throws {
        let ttsId = "mlx-community/Soprano-1.1-80M-bf16"
        async let ttsDirectory = Model.installModel(id: ttsId, parentProgress: loadingProgress, progressCount: 800)
        let model = try await SopranoModel.fromModelDirectory(ttsDirectory, repo: ttsId)
        loadingProgress.completedUnitCount += 200

        let stream = speechStream

        #if os(macOS)
            log("Speech model warmup...")
            _ = try? await model.generate(text: "This is a warmup!")
            log("Speech model warmup done")
        #endif

        active = UUID()

        Task { [weak self] in
            log("Speech queue starting")
            do {
                for await (line, token) in stream {
                    guard let self else { return }
                    // Skip lines queued before the current speaking session (e.g. before a
                    // cancel/reset/barge-in rotated the token).
                    guard let token, await active == token else { continue }
                    try await speak(line, using: model, startedInActive: token)
                }
            } catch {
                log("Speech generation failed: \(error)")
            }
            log("Speech queue done")
        }
    }

    private var active: UUID?

    func waitForBoot() async {
        while active == nil {
            try? await Task.sleep(for: .seconds(0.1))
        }
    }

    private var countInQueue = 0 {
        didSet {
            log("Speech audio queue: \(countInQueue)")
        }
    }

    func queue(_ text: String) {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "*<>-()")))
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "...", with: "…")
            .filter { !$0.isSymbol }
        if trimmed.count <= 1 {
            return
        }

        if !speechPlayer.isPlaying {
            speechPlayer.play()
        }

        countInQueue += 1
        spechContinuation.yield((trimmed, active))
    }

    func waitUntilDone() async {
        while countInQueue > 0 {
            try? await Task.sleep(for: .seconds(0.1))
        }
        await speechPlayer.stopOffActor()
    }

    private let voiceParams = GenerateParameters(
        maxTokens: 1200,
        temperature: 0.75,
        topP: 0.95,
        repetitionPenalty: 1.3,
        repetitionContextSize: 64
    )

    private var playingLatestBuffer = false
    private var generationTask: Task<[Float], Error>?

    /// Isolated to this actor so the (interruptible) render stays on the same executor the inline
    /// call used, rather than hopping to the global pool and racing the STT model's MLX work.
    private func renderSamples(_ text: String, using speechModel: SopranoModel) async throws -> [Float] {
        try await speechModel.generate(text: text, parameters: voiceParams).asArray(Float.self)
    }

    private func speak(_ text: String, using speechModel: SopranoModel, startedInActive: UUID) async throws {
        guard startedInActive == active else { return }

        log("Rendering: \(text)")

        // Render in a cancellable task so `stopSpeaking()` can abort it mid-generation (the render
        // runs on this actor via the isolated `renderSamples`, same as before, just interruptible).
        let task = Task { try await renderSamples(text, using: speechModel) }
        generationTask = task
        let samples: [Float]
        do {
            samples = try await task.value
        } catch {
            if !(error is CancellationError) {
                log("Speech generation error, skipping line: \(error)")
            }
            return
        }
        generationTask = nil

        guard startedInActive == active else { return }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(speechModel.sampleRate), channels: 1, interleaved: false)!

        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = unsafe buffer.floatChannelData![0]
        for i in 0 ..< samples.count {
            unsafe channel[i] = samples[i]
        }

        while playingLatestBuffer {
            try? await Task.sleep(for: .seconds(0.2))
        }

        guard startedInActive == active else { return }

        playingLatestBuffer = true

        Task {
            defer {
                playingLatestBuffer = false
            }

            guard startedInActive == active else { return }

            log("Playing: \(text)")
            await speechPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack)
            try? await Task.sleep(for: .seconds(0.5))
            if countInQueue > 0 {
                countInQueue -= 1
            }
        }
    }
}
