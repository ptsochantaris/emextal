import EmextalAudio
import Foundation
import MLX

final actor Mic {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    weak var modeDelegate: Conversation?

    let phraseStream: AsyncStream<String>

    private var ignoreMic = false
    private var transcriber: GLMASRModel?
    private var detector: SileroVAD?
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

    let loadingProgress = Progress(totalUnitCount: 1000)

    func boot() async throws {
        let detectorId = "mlx-community/silero-vad"
        async let detectorLocation = Model.installModel(id: detectorId, parentProgress: loadingProgress, progressCount: 100)

        let transcriberId = "mlx-community/GLM-ASR-Nano-2512-4bit"
        async let transcriberLocation = Model.installModel(id: transcriberId, parentProgress: loadingProgress, progressCount: 700)

        transcriber = try await GLMASRModel.fromModelDirectory(transcriberLocation)
        loadingProgress.completedUnitCount += 100

        detector = try await SileroVAD.fromModelDirectory(detectorLocation)
        loadingProgress.completedUnitCount += 100

        #if os(macOS)
            let blank = MLXArray.zeros([100_000])
            // log("Speaker detection warmup...")
            // _ = try? detect.feed(chunk: blank)
            // log("Speaker detection warmup done")

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
            for await chunk in sequence {
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
            var overflow = MLXArray()

            func splitData(_ data: MLXArray) -> [MLXArray] {
                let data = concatenated([overflow, data])
                let dataLen = data.count
                var i = 0
                var blocks = [MLXArray]()
                while i < dataLen {
                    let remaining = dataLen - i
                    if remaining < 512 {
                        overflow = data[i ..< dataLen]
                        break
                    } else {
                        let block = data[i ..< i + 512]
                        blocks.append(block)
                        i += 512
                    }
                }
                return blocks
            }

            do {
                let detect = FinalWrapper(detector).data()
                var state: SileroVADStreamingState?
                let stream = await recorder.start(dropFirstChunk: false)
                var audioChain = [MLXArray]()
                var lastNonSpeakingBlocks = [MLXArray]()
                var speakerMomentum = 0

                for try await audioChunk in stream {
                    let blocks = splitData(audioChunk.data())

                    for block in blocks {
                        let (probs, newState) = try detect.feed(chunk: block, state: state)
                        state = newState
                        let prob = probs.asArray(Float.self)[0]

                        if prob > 0.7 {
                            if audioChain.isEmpty {
                                log("Speaking started")
                                await delegate.setListeningTalkingMode()
                                audioChain = lastNonSpeakingBlocks
                                lastNonSpeakingBlocks = []
                                speakerMomentum = 10
                            } else if speakerMomentum < 50 {
                                speakerMomentum += 1
                                log("Speaker momentum: \(speakerMomentum)")
                            }
                            audioChain.append(block)

                        } else if audioChain.isEmpty {
                            lastNonSpeakingBlocks.append(block)
                            if lastNonSpeakingBlocks.count > 4 {
                                lastNonSpeakingBlocks.remove(at: 0)
                            }

                        } else {
                            speakerMomentum = max(speakerMomentum - 1, 0)
                            log("Speaker momentum: \(speakerMomentum)")
                            if speakerMomentum == 0 {
                                log("Speaking done, parsing")

                                await recorder.stop()

                                await delegate.setTranscribingMode()

                                let block = concatenated(audioChain)
                                audioChain.removeAll(keepingCapacity: true)
                                lastNonSpeakingBlocks = []

                                let text = transcriber.generate(audio: block).text.trimmingCharacters(in: .whitespacesAndNewlines)
                                phraseContinuation.yield(text)
                            }
                        }
                    }
                }
            } catch {
                log("Error in VAD: \(error)")
            }
            log("VAD stream ended")
        }
    }
}
