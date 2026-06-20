import Foundation

final class UtilityExecutor: SerialExecutor {
    static let sharedExecutor = UtilityExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.utility-priority", qos: .utility)

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
