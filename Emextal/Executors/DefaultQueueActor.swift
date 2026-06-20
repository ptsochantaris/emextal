import Foundation

@globalActor actor DefaultQueueActor {
    static let shared = DefaultQueueActor()

    private static let executor = DefaultQueueExecutor()
    static let sharedUnownedExecutor = unsafe executor.asUnownedSerialExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        unsafe Self.sharedUnownedExecutor
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
