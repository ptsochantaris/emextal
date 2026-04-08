import AVFoundation
import MLX
import MLXAudioTTS
import MLXLMCommon

final actor Speaker {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private let speechStream: AsyncStream<String>
    private let spechContinuation: AsyncStream<String>.Continuation

    private let speechPlayer = AVAudioPlayerNode()

    private let effectPlayer = AVAudioPlayerNode()
    private let effectContinuation: AsyncStream<SoundEffect>.Continuation

    init(engine: AVAudioEngine) {
        (speechStream, spechContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)

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
        effectPlayer.stop()
    }

    func stopSpeaking() {
        active = UUID()
        countInQueue = 0
        playingLatestBuffer = false
        if speechPlayer.isPlaying {
            speechPlayer.stop()
        }
    }

    func shutdown() {
        stopSpeaking()
        effectContinuation.finish()
        spechContinuation.finish()
    }

    func boot() async throws {
        let ttsId = "mlx-community/Soprano-1.1-80M-bf16"
        let model = try await SopranoModel.fromPretrained(ttsId, cache: Model.audioCache)
        Model.clearAudioCache(for: ttsId)

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
                for await line in stream {
                    guard let self else { return }
                    guard let active = await active else { continue }
                    try await speak(line, using: model, startedInActive: active)
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
        spechContinuation.yield(trimmed)
    }

    func waitUntilDone() async {
        while countInQueue > 0 {
            try? await Task.sleep(for: .seconds(0.1))
        }
        speechPlayer.stop()
    }

    private let voiceParams = GenerateParameters(
        maxTokens: 1200,
        temperature: 0.75,
        topP: 0.95,
        repetitionPenalty: 1.3,
        repetitionContextSize: 64
    )

    private var playingLatestBuffer = false

    private func speak(_ text: String, using speechModel: SopranoModel, startedInActive: UUID) async throws {
        guard startedInActive == active else { return }

        log("Rendering: \(text)")

        let samples = try await speechModel.generate(text: text, parameters: voiceParams).asArray(Float.self)

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
