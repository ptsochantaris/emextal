import Foundation

final class DefaultQueueExecutor: SerialExecutor {
    static let sharedExecutor = DefaultQueueExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.default-priority", qos: .default)

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
