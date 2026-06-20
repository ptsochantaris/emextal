import AVFoundation
import Foundation
import MLX

final actor Recorder {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private let transcriptionSampleRate = 16000
    private let micBufferSize: UInt32 = 16384
    private let outputFormat: AVAudioFormat
    private let outputFrames: AVAudioFrameCount

    private let inputNode: AVAudioInputNode

    // Captured lazily in `start()` rather than at init, so that toggling voice-processing (echo
    // cancellation) — which changes the input node's format — can never leave these stale.
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var convertedBuffer: AVAudioPCMBuffer?
    private var convertedBufferFrames = 0

    private let sampleContinuation: AsyncStream<FinalWrapper<AVAudioPCMBuffer>>.Continuation

    private var convertedContinuation: AsyncStream<FinalWrapper<MLXArray>>.Continuation?

    init(inputNode: AVAudioInputNode) {
        self.inputNode = inputNode

        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(transcriptionSampleRate), channels: 1, interleaved: true)!
        outputFrames = AVAudioFrameCount(outputFormat.sampleRate)

        let sampleQueue: AsyncStream<FinalWrapper<AVAudioPCMBuffer>>
        (sampleQueue, sampleContinuation) = AsyncStream.makeStream(of: FinalWrapper<AVAudioPCMBuffer>.self, bufferingPolicy: .unbounded)

        Task {
            for await buffer in sampleQueue {
                await processBuffer(buffer)
            }
            log("Conversion queue done")
        }
    }

    func start(dropFirstChunk: Bool) -> AsyncStream<FinalWrapper<MLXArray>> {
        log("Adding mic tap")

        // Sample the input format now, after any voice-processing changes have settled.
        let inputFormat = inputNode.outputFormat(forBus: 0)
        self.inputFormat = inputFormat
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        // Voice processing presents the mic as a multi-channel input (e.g. 4 identical channels on
        // macOS). With no channel layout on a discrete multi-channel source, AVAudioConverter's
        // default down-mix matrix produces pure silence — it runs without error but every output
        // sample is zero. Map the single mono output channel explicitly from input channel 0 so the
        // mic signal actually comes through. For a normal 1-channel input this is just identity.
        converter?.channelMap = [0]
        self.converter = converter
        let sampleRate = AVAudioFrameCount(inputFormat.sampleRate)
        let frames = Int(outputFrames * micBufferSize / sampleRate)
        convertedBufferFrames = frames
        convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(frames))

        let continuation = sampleContinuation
        let convertedSequence: AsyncStream<FinalWrapper<MLXArray>>
        (convertedSequence, convertedContinuation) = AsyncStream.makeStream(of: FinalWrapper<MLXArray>.self, bufferingPolicy: .unbounded)

        // The tap block is invoked on CoreAudio's realtime thread. Without `@Sendable` it would
        // inherit this actor's isolation (the module defaults to MainActor isolation), and the
        // Swift runtime's executor assertion would trap the moment the realtime thread runs it —
        // silently killing audio capture. Marking it `@Sendable` keeps it non-isolated.
        nonisolated(unsafe) var dropFirstChunk = dropFirstChunk
        inputNode.installTap(onBus: 0, bufferSize: micBufferSize, format: inputFormat) { @Sendable incomingBuffer, _ in
            if unsafe dropFirstChunk {
                unsafe dropFirstChunk = false
                return
            }
            let buffer = FinalWrapper(incomingBuffer)
            continuation.yield(buffer)
        }
        return convertedSequence
    }

    func stop() {
        guard let continuation = convertedContinuation else {
            return
        }
        log("Removing mic tap")
        inputNode.removeTap(onBus: 0)
        continuation.finish()
        convertedContinuation = nil
    }

    func shutdown() {
        stop()
        sampleContinuation.finish()
    }

    private func processBuffer(_ incomingBuffer: FinalWrapper<AVAudioPCMBuffer>) {
        guard let converter, let convertedBuffer else {
            return
        }

        var error: NSError?
        nonisolated(unsafe) var reported = AVAudioConverterInputStatus.haveData

        unsafe converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            unsafe outStatus.pointee = reported
            unsafe reported = .noDataNow
            return incomingBuffer.data()
        }

        if let error {
            log("Warning: Conversion error, skipping chunk: \(error)")
            return
        }

        let convertedAudioBuffer = unsafe UnsafeBufferPointer<Float32>(
            start: convertedBuffer.floatChannelData![0],
            count: convertedBufferFrames
        )
        let array = unsafe MLXArray(convertedAudioBuffer)
        let chunk = FinalWrapper(array)
        convertedContinuation?.yield(chunk)
    }
}
