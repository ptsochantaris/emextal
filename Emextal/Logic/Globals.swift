import Foundation

#if DEBUG
    import OSLog
#endif

nonisolated func log(_ message: @autoclosure () -> String) {
    #if DEBUG
        unsafe os_log("%{public}@", message())
    #endif
}

enum EmeltalError: Error {
    case message(String)
}
