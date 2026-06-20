import Foundation

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
