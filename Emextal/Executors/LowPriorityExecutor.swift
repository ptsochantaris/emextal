import Foundation

final class LowPriorityExecutor: SerialExecutor {
    static let sharedExecutor = LowPriorityExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.low-priority", qos: .background)

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

@globalActor actor LowPriorityActor {
    static let shared = LowPriorityActor()

    private static let executor = LowPriorityExecutor()
    static let sharedUnownedExecutor = unsafe executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
