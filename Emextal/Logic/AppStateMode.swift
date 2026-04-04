import Foundation

enum AppStateMode: Equatable {
    case conversation(Conversation), menu, error(title: String, error: any Error)

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
        case let .conversation(conversation):
            conversation
        case .error, .menu:
            nil
        }
    }
}
