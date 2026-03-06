import Foundation

final class LowPriorityExecutor: SerialExecutor {
    static let sharedExecutor = LowPriorityExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.low-priority", qos: .background)

    func enqueue(_ job: consuming ExecutorJob) {
        let j = UnownedJob(job)
        let e = asUnownedSerialExecutor()
        ggmlQueue.async {
            j.runSynchronously(on: e)
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}

@globalActor actor LowPriorityActor {
    static let shared = LowPriorityActor()

    private static let executor = LowPriorityExecutor()
    static let sharedUnownedExecutor = executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}

final class UtilityExecutor: SerialExecutor {
    static let sharedExecutor = UtilityExecutor()

    private let ggmlQueue = DispatchQueue(label: "build.bru.emeltal.utility-priority", qos: .utility)

    func enqueue(_ job: consuming ExecutorJob) {
        let j = UnownedJob(job)
        let e = asUnownedSerialExecutor()
        ggmlQueue.async {
            j.runSynchronously(on: e)
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}

@globalActor actor UtilityActor {
    static let shared = UtilityActor()

    private static let executor = UtilityExecutor()
    static let sharedUnownedExecutor = executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
