import AVFoundation
import MLX
import MLXAudioTTS
import MLXLMCommon

final actor Speaker {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private let speechStream: AsyncStream<String>
    private let spechContinuation: AsyncStream<String>.Continuation

    private let engine: AVAudioEngine
    private let speechPlayer = AVAudioPlayerNode()

    private let effectPlayer = AVAudioPlayerNode()
    private let effectContinuation: AsyncStream<SoundEffect>.Continuation

    init(engine: AVAudioEngine) {
        self.engine = engine
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

    func shutdown() {
        effectContinuation.finish()
        spechContinuation.finish()
    }

    deinit {
        log("\(Self.self) deinit")
    }

    func warmup() async throws {
        #if os(macOS)
            log("Speech model warmup...")
            _ = try await loadedModel?.generate(text: "This is a warmup!")
            log("Speech model warmup done")
        #endif
    }

    private var loadedModel: SopranoModel?

    func boot() async throws {
        let model = try await Task {
            try await SopranoModel.fromPretrained("mlx-community/Soprano-80M-8bit")
        }.value

        loadedModel = model

        let stream = speechStream

        Task { [weak self] in
            do {
                for await line in stream {
                    guard let self else { return }
                    try await speak(line, using: model)
                }
            } catch {
                log("Speech generation failed: \(error)")
            }
            log("Speech queue done")
        }
    }

    private var countInQueue = 0 {
        didSet {
            log("Speech audio queue: \(countInQueue)")
        }
    }

    func queue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "*<>"))).replacingOccurrences(of: "**", with: "")
        if trimmed.isEmpty {
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
        maxTokens: 2400,
        temperature: 0.7,
        topP: 0.95,
        repetitionPenalty: 1.3,
        repetitionContextSize: 30
    )

    private var playingLatestBuffer = false

    private func speak(_ text: String, using speechModel: SopranoModel) async throws {
        log("Rendering: \(text)")

        let samples = try await speechModel.generate(text: text).asArray(Float.self)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(speechModel.sampleRate), channels: 1, interleaved: false)!

        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for i in 0 ..< samples.count {
            channel[i] = samples[i]
        }

        while playingLatestBuffer {
            try? await Task.sleep(for: .seconds(0.2))
        }

        playingLatestBuffer = true
        Task {
            await speechPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack)
            countInQueue -= 1
            try? await Task.sleep(for: .seconds(0.5))
            playingLatestBuffer = false
        }
    }
}
