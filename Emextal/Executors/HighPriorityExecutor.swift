import Foundation

final class HighPriorityExecutor: SerialExecutor {
    static let sharedExecutor = HighPriorityExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.high-priority", qos: .userInitiated)

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

@globalActor actor HighPriorityActor {
    static let shared = HighPriorityActor()

    private static let executor = HighPriorityExecutor()
    static let sharedUnownedExecutor = unsafe executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
