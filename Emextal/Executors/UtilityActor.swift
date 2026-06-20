import Foundation

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
