import Foundation

enum AppStateMode: Equatable {
    case conversation(Conversation), menu

    static func == (lhs: AppStateMode, rhs: AppStateMode) -> Bool {
        switch (lhs, rhs) {
        case (.conversation, .conversation), (.menu, .menu):
            true
        default:
            false
        }
    }

    var conversation: Conversation? {
        switch self {
        case let .conversation(conversation):
            conversation
        case .menu:
            nil
        }
    }
}
