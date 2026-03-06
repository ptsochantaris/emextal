import AVFoundation
import MLXAudioTTS
import MLXLMCommon
import MLX

final actor SpeechQueue {
    let speechStream: AsyncStream<String>

    private let spechContinuation: AsyncStream<String>.Continuation
    private let engine: AVAudioEngine
    private let speechPlayer = AVAudioPlayerNode()

    init(engine: AVAudioEngine) {
        self.engine = engine
        (speechStream, spechContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)

        engine.attach(speechPlayer)
        let speechFormat = AVAudioFormat(standardFormatWithSampleRate: 32000, channels: 1)
        engine.connect(speechPlayer, to: engine.mainMixerNode, format: speechFormat)
    }

    func shutdown() {
        spechContinuation.finish()
    }

    deinit {
        log("\(Self.self) deinit")
    }

    func boot() async throws {
        let model = try await Task {
            try await SopranoModel.fromPretrained("mlx-community/Soprano-80M-8bit")
        }.value

        let stream = speechStream

        Task { @LowPriorityActor [weak self] in
            #if os(macOS)
                log("Speech model warmup...")
                _ = try? await model.generate(text: "This is a warmup!")
                log("Speech model warmup done")
            #endif
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
