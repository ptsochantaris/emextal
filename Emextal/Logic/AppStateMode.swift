import Foundation

enum AppStateMode: Equatable {
    // The model is nil for conversations that don't use one, such as transcription mode.
    case conversation(conversation: Conversation, model: Model?), menu, error(title: String, error: any Error)

    static func == (lhs: AppStateMode, rhs: AppStateMode) -> Bool {
        switch (lhs, rhs) {
        case (.conversation, .conversation), (.error, .error), (.menu, .menu):
            true
        default:
            false
        }
    }

    var conversation: Conversation? {
        switch self {
        case let .conversation(conversation, _):
            conversation
        case .error, .menu:
            nil
        }
    }
}
