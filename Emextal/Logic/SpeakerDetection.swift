import AVFoundation
import Foundation
import MLX
import MLXAudioSTT
import MLXAudioVAD

extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}
extension SortformerModel: @unchecked @retroactive Sendable {}
extension Qwen3ASRModel: @unchecked @retroactive Sendable {}

final actor SpeakerDetection {
    weak var modeDelegate: ViewModel?

    let phraseStream: AsyncStream<String>

    // Accessed in mic Tap
    nonisolated(unsafe) var ignoreMic = false
    private nonisolated(unsafe) let engine: AVAudioEngine

    private var transcriber: Qwen3ASRModel?
    private var detector: SortformerModel?
    private let effectPlayer = AVAudioPlayerNode()
    private let effectQueue = AsyncStream.makeStream(of: SoundEffect.self, bufferingPolicy: .bufferingNewest(2))
    private let phraseContinuation: AsyncStream<String>.Continuation
    private let recorder: Recorder
    private var warmupTask1: Task<Void, Never>?
    private var warmupTask2: Task<Void, Never>?

    init(engine: AVAudioEngine) {
        self.engine = engine

        recorder = Recorder(engine: self.engine)

        engine.attach(effectPlayer)
        let effectFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: effectFormat)

        (phraseStream, phraseContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)

        let stream = effectQueue.stream

        Task { @LowPriorityActor [weak self] in
            for await effect in stream {
                guard let self else { return }
                await handleEffect(effect)
            }
            log("Effect player queue done")
        }
    }

    func setModeDelegate(_ delegate: ViewModel) {
        modeDelegate = delegate
    }

    private func handleEffect(_ effect: SoundEffect) async {
        effectPlayer.volume = effect.preferredVolume
        effectPlayer.play()
        await effectPlayer.scheduleFile(effect.audioFile, at: nil)
        try? await Task.sleep(for: .seconds(1))
        effectPlayer.stop()
    }

    func boot() async throws {
        let detectorTask = Task {
            try await SortformerModel.fromPretrained("mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16")
        }

        //transcriber = try await VoxtralRealtimeModel.fromPretrained("mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit")
        transcriber = try await Qwen3ASRModel.fromPretrained("mlx-community/Qwen3-ASR-1.7B-4bit")
        #if os(macOS)
            warmupTask2 = Task {
                let blank = MLXArray.zeros([100_000])
                log("Transcriber warmup...")
                _ = transcriber?.generate(audio: blank)
                log("Transcriber warmup done")
                warmupTask2 = nil
            }
        #endif

        detector = try await detectorTask.value
        #if os(macOS)
            warmupTask1 = Task {
                let blank = MLXArray.zeros([100_000])
                log("Speaker detection warmup...")
                _ = try? await detector?.generate(audio: blank)
                log("Speaker detection warmup done")
                warmupTask1 = nil
            }
        #endif
    }

    func stop() async {
        await recorder.stop()
    }

    func shutdown() async {
        await stop()
        await recorder.shutdown()
        effectQueue.continuation.finish()
        phraseContinuation.finish()
    }

    isolated deinit {
        log("\(Self.self) deinit")
    }

    func startManual() async {
        await warmupTask1?.value
        await warmupTask2?.value

        guard let transcriber, let delegate = modeDelegate else {
            return
        }

        effectQueue.continuation.yield(.startListening)

        log("Manual recording")

        if let session = await delegate.getSession() {
            await delegate.setMode(.listening(state: .talking, session: session))
        }

        Task {
            let sequence = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            log("Manual recording streaming")

            // depending on the UI to call stop()
            for try await chunk in sequence {
                audioChain.append(chunk)
            }

            if audioChain.isEmpty {
                await resetToWaiting()
            } else {
                log("Manual recording done, parsing")
                effectQueue.continuation.yield(.endListening)
                if let session = await delegate.getSession() {
                    await delegate.setMode(.transcribing(session: session))
                }

                let block = concatenated(audioChain)
                let text = transcriber.generate(audio: block).text.trimmingCharacters(in: .whitespacesAndNewlines)
                phraseContinuation.yield(text)
            }

            log("Manual recording stream ended")
        }
    }

    func startAutodetect() async {
        await warmupTask1?.value
        await warmupTask2?.value

        guard let detector, let transcriber, let delegate = modeDelegate else {
            return
        }

        if let session = await delegate.getSession() {
            await delegate.setMode(.listening(state: .quiet, session: session))
        }

        log("VAD recording")

        Task {
            var state = detector.initStreamingState()
            let stream = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            for try await chunk in stream {
                let (result, newState) = try await detector.feed(chunk: chunk, state: state, threshold: 0.5, minDuration: 0.3)
                state = newState

                if result.numSpeakers > 0 {
                    if audioChain.isEmpty {
                        log("Speaking started")
                        if let session = await delegate.getSession() {
                            await delegate.setMode(.listening(state: .talking, session: session))
                        }
                    }
                    audioChain.append(chunk)

                } else if !audioChain.isEmpty {
                    log("Speaking done, parsing")

                    await recorder.stop()

                    if let session = await delegate.getSession() {
                        await delegate.setMode(.transcribing(session: session))
                    }

                    let block = concatenated(audioChain)
                    audioChain.removeAll(keepingCapacity: true)

                    let text = transcriber.generate(audio: block).text.trimmingCharacters(in: .whitespacesAndNewlines)
                    phraseContinuation.yield(text)
                }
            }

            log("VAD stream ended")
        }
    }

    private func resetToWaiting() async {
        if let delegate = modeDelegate, let session = await delegate.getSession() {
            await delegate.setMode(.waiting(session: session))
        }
    }
}
