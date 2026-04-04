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
    private let inputFormat: AVAudioFormat

    private let converter: AVAudioConverter
    private let convertedBuffer: AVAudioPCMBuffer

    private let sampleContinuation: AsyncStream<FinalWrapper<AVAudioPCMBuffer>>.Continuation

    private var convertedContinuation: AsyncStream<FinalWrapper<MLXArray>>.Continuation?
    private let convertedBufferFrames: Int

    init(inputNode: AVAudioInputNode) {
        self.inputNode = inputNode

        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(transcriptionSampleRate), channels: 1, interleaved: true)!
        outputFrames = AVAudioFrameCount(outputFormat.sampleRate)

        inputFormat = inputNode.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)!

        let sampleRate = AVAudioFrameCount(inputFormat.sampleRate)
        convertedBufferFrames = Int(outputFrames * micBufferSize / sampleRate)
        convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(convertedBufferFrames))!

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
        let continuation = sampleContinuation
        let convertedSequence: AsyncStream<FinalWrapper<MLXArray>>
        (convertedSequence, convertedContinuation) = AsyncStream.makeStream(of: FinalWrapper<MLXArray>.self, bufferingPolicy: .unbounded)

        var dropFirstChunk = dropFirstChunk
        inputNode.installTap(onBus: 0, bufferSize: micBufferSize, format: inputFormat) { incomingBuffer, _ in
            if dropFirstChunk {
                dropFirstChunk = false
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
