import Foundation

enum AppStateMode {
    case conversation(Conversation), menu

    var conversation: Conversation? {
        switch self {
        case let .conversation(conversation):
            conversation
        case .menu:
            nil
        }
    }
}
