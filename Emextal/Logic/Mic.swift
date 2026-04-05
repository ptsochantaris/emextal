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

    init(recorder: Recorder) {
        self.recorder = recorder
        (phraseStream, phraseContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
    }

    deinit {
        log("\(Self.self) deinit")
    }

    func setIgnoreMic(_ ignore: Bool) {
        ignoreMic = ignore
    }

    func setModeDelegate(_ delegate: Conversation) {
        modeDelegate = delegate
    }

    private var bootDone = false

    func boot() async throws {
        let detectorId = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
        async let detectorTask = SortformerModel.fromPretrained(detectorId, cache: Model.audioCache)

        let transcriberId = "mlx-community/Qwen3-ASR-1.7B-4bit"
        transcriber = try await Qwen3ASRModel.fromPretrained(transcriberId, cache: Model.audioCache)
        Model.clearAudioCache(for: transcriberId)

        detector = try await detectorTask
        Model.clearAudioCache(for: detectorId)

        #if os(macOS)
            guard let detect = FinalWrapper(detector).data() else {
                return
            }

            let blank = MLXArray.zeros([100_000])
            log("Speaker detection warmup...")
            _ = try? await detect.generate(audio: blank)
            log("Speaker detection warmup done")

            log("Transcriber warmup...")
            _ = transcriber?.generate(audio: blank)
            log("Transcriber warmup done")
        #endif

        bootDone = true
    }

    func waitForBoot() async {
        while !bootDone {
            try? await Task.sleep(for: .seconds(0.1))
        }
    }

    func stop() async {
        await recorder.stop()
    }

    func shutdown() async {
        await stop()
        await recorder.shutdown()
        phraseContinuation.finish()
    }

    func startManual() async {
        guard let transcriber, let delegate = modeDelegate else {
            return
        }

        await delegate.playEffect(.startListening)

        log("Manual recording")

        await delegate.setListeningTalkingMode()

        Task {
            let sequence = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            log("Manual recording streaming")

            // depending on the UI to call stop()
            for try await chunk in sequence {
                audioChain.append(chunk.data())
            }

            if audioChain.isEmpty {
                await delegate.setWaitingMode()
            } else {
                log("Manual recording done, parsing")
                await delegate.playEffect(.endListening)
                await delegate.setTranscribingMode()

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

        await delegate.setListeningQuietMode()

        log("VAD recording")

        Task {
            let detect = FinalWrapper(detector).data()
            var state = detect.initStreamingState()
            let stream = await recorder.start(dropFirstChunk: false)
            var audioChain = [MLXArray]()

            for try await chunk in stream {
                let (result, newState) = try await detect.feed(chunk: chunk.data(), state: state, threshold: 0.5, minDuration: 0.3)
                state = newState

                if result.numSpeakers > 0 {
                    if audioChain.isEmpty {
                        log("Speaking started")
                        await delegate.setListeningTalkingMode()
                    }
                    audioChain.append(chunk.data())

                } else if !audioChain.isEmpty {
                    log("Speaking done, parsing")

                    await recorder.stop()

                    await delegate.setTranscribingMode()

                    let block = concatenated(audioChain)
                    audioChain.removeAll(keepingCapacity: true)

                    let text = transcriber.generate(audio: block).text.trimmingCharacters(in: .whitespacesAndNewlines)
                    phraseContinuation.yield(text)
                }
            }

            log("VAD stream ended")
        }
    }
}
