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

@globalActor actor UtilityActor {
    static let shared = UtilityActor()

    private static let executor = UtilityExecutor()
    static let sharedUnownedExecutor = unsafe executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
