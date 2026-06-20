import Foundation

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
