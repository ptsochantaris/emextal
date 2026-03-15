internal import Foundation

nonisolated enum MicState: Equatable {
    case quiet, talking

    var isQuiet: Bool {
        if case .quiet = self {
            return true
        }
        return false
    }
}
