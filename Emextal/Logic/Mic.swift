import AVFoundation
import Foundation
import MLX
import MLXAudioSTT
import MLXAudioVAD

final actor Mic {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    weak var modeDelegate: Conversation?

    let phraseStream: AsyncStream<String>

    private var ignoreMic = false
    private var transcriber: Qwen3ASRModel?
    private var detector: SortformerModel?
    private let phraseContinuation: AsyncStream<String>.Continuation
    private let recorder: Recorder

    init(engine: AVAudioEngine) {
        nonisolated(unsafe) let engineRef = engine
        unsafe recorder = Recorder(engine: engineRef)

        (phraseStream, phraseContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
    }

    func setIgnoreMic(_ ignore: Bool) {
        ignoreMic = ignore
    }

    func setModeDelegate(_ delegate: Conversation) {
        modeDelegate = delegate
    }

    func warmup() async throws {
        #if os(macOS)
            guard let detect = FinalWrapper(detector).data else {
                return
            }

            let blank = MLXArray.zeros([100_000])
            log("Speaker detection warmup...")
            _ = try await detect.generate(audio: blank)
            log("Speaker detection warmup done")

            log("Transcriber warmup...")
            _ = transcriber?.generate(audio: blank)
            log("Transcriber warmup done")
        #endif
    }

    func boot() async throws {
        async let detectorTask = SortformerModel.fromPretrained("mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16")
        transcriber = try await Qwen3ASRModel.fromPretrained("mlx-community/Qwen3-ASR-1.7B-4bit")
        detector = try await detectorTask
    }

    func stop() async {
        await recorder.stop()
    }

    func shutdown() async {
        await stop()
        await recorder.shutdown()
        phraseContinuation.finish()
    }

    isolated deinit {
        log("\(Self.self) deinit")
    }

    func startManual() async {
        guard let transcriber, let delegate = modeDelegate else {
            return
        }

        await delegate.playEffect(.startListening)

        log("Manual recording")

        if let session = await delegate.getSession().data {
            await delegate.setMode(.listening(state: .talking, session: session))
        }

        Task {
            let sequence = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            log("Manual recording streaming")

            // depending on the UI to call stop()
            for try await chunk in sequence {
                audioChain.append(chunk.data)
            }

            if audioChain.isEmpty {
                await resetToWaiting()
            } else {
                log("Manual recording done, parsing")
                await delegate.playEffect(.endListening)
                if let session = await delegate.getSession().data {
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
        guard let detector, let transcriber, let delegate = modeDelegate else {
            return
        }

        if let session = await delegate.getSession().data {
            await delegate.setMode(.listening(state: .quiet, session: session))
        }

        log("VAD recording")

        Task {
            let detect = FinalWrapper(detector).data
            var state = detect.initStreamingState()
            let stream = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            for try await chunk in stream {
                let (result, newState) = try await detect.feed(chunk: chunk.data, state: state, threshold: 0.5, minDuration: 0.3)
                state = newState

                if result.numSpeakers > 0 {
                    if audioChain.isEmpty {
                        log("Speaking started")
                        if let session = await delegate.getSession().data {
                            await delegate.setMode(.listening(state: .talking, session: session))
                        }
                    }
                    audioChain.append(chunk.data)

                } else if !audioChain.isEmpty {
                    log("Speaking done, parsing")

                    await recorder.stop()

                    if let session = await delegate.getSession().data {
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
        if let delegate = modeDelegate, let session = await delegate.getSession().data {
            await delegate.setMode(.waiting(session: session))
        }
    }
}
