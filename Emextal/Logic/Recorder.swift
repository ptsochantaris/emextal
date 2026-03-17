import AVFoundation
import Foundation
import MLX

extension MLXArray: @unchecked @retroactive Sendable {}

final actor Recorder {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe HighPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private let engine: AVAudioEngine

    private let transcriptionSampleRate = 16000
    private let micBufferSize: UInt32 = 16384
    private let outputFormat: AVAudioFormat
    private let outputFrames: AVAudioFrameCount

    private let inputNode: AVAudioInputNode
    private let inputFormat: AVAudioFormat

    private let converter: AVAudioConverter
    private let convertedBuffer: AVAudioPCMBuffer

    private let sampleContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    private var convertedContinuation: AsyncStream<MLXArray>.Continuation?
    private let convertedBufferFrames: Int

    init(engine: AVAudioEngine) {
        self.engine = engine

        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(transcriptionSampleRate), channels: 1, interleaved: true)!
        outputFrames = AVAudioFrameCount(outputFormat.sampleRate)

        inputNode = engine.inputNode
        inputFormat = inputNode.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

        let sampleRate = AVAudioFrameCount(inputFormat.sampleRate)
        convertedBufferFrames = Int(outputFrames * micBufferSize / sampleRate)
        convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(convertedBufferFrames))!

        let sampleQueue: AsyncStream<AVAudioPCMBuffer>
        (sampleQueue, sampleContinuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self, bufferingPolicy: .unbounded)

        Task {
            for await buffer in sampleQueue {
                await processBuffer(buffer)
            }
            log("Conversion queue done")
        }
    }

    func start(dropFirstChunk: Bool) -> AsyncStream<MLXArray> {
        log("Adding mic tap")
        let continuation = sampleContinuation
        let convertedSequence: AsyncStream<MLXArray>
        (convertedSequence, convertedContinuation) = AsyncStream.makeStream(of: MLXArray.self, bufferingPolicy: .unbounded)

        var dropFirstChunk = dropFirstChunk
        inputNode.installTap(onBus: 0, bufferSize: micBufferSize, format: inputFormat) { incomingBuffer, _ in
            if dropFirstChunk {
                dropFirstChunk = false
                return
            }
            continuation.yield(incomingBuffer)
        }

        return convertedSequence
    }

    func stop() {
        log("Removing mic tap")
        inputNode.removeTap(onBus: 0)
        convertedContinuation?.finish()
        convertedContinuation = nil
    }

    func shutdown() {
        stop()
        sampleContinuation.finish()
    }

    private func processBuffer(_ incomingBuffer: AVAudioPCMBuffer) {
        var error: NSError?
        nonisolated(unsafe) var reported = AVAudioConverterInputStatus.haveData

        unsafe converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            unsafe outStatus.pointee = reported
            unsafe reported = .noDataNow
            return incomingBuffer
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
        convertedContinuation?.yield(array)
    }
}
