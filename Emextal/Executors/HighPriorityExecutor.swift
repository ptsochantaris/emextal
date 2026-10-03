import Foundation

final class HighPriorityExecutor: SerialExecutor {
    static let sharedExecutor = HighPriorityExecutor()

    /// A separate lane for speech synthesis. TTS renders run synchronously for seconds at a time, so
    /// sharing the mic's executor would starve audio capture and the VAD for the whole reply,
    /// making voice barge-in impossible.
    static let speechExecutor = HighPriorityExecutor(label: "build.bru.emeltal.high-priority.speech")

    private let ggmlQueue: DispatchQueue

    init(label: String = "build.bru.emeltal.high-priority") {
        ggmlQueue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let j = UnownedJob(job)
        let e = unsafe asUnownedSerialExecutor()
        ggmlQueue.async {
            unsafe j.runSynchronously(on: e)
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
