internal import Foundation

enum ActivationState {
    case button
    case voiceActivated

    var isManual: Bool {
        switch self {
        case .button:
            true
        case .voiceActivated:
            false
        }
    }
}
