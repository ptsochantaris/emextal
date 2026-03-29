import SwiftUI

@Observable
final class AppState {
    private(set) var mode = AppStateMode.menu

    func go(conversation: Conversation) {
        mode = .conversation(conversation)
    }

    func endConversation() {
        mode = .menu
    }

    func shutdown() async {
        await mode.conversation?.shutdown()
    }

    var title: String {
        guard let conversation = mode.conversation else {
            return "Emextal"
        }

        return switch conversation.mode {
        case .loading: "Loading \(conversation.displayName)"
        case .loaded: conversation.displayName
        case .error: "Loading Failed"
        default: "Emextal – \(conversation.displayName)"
        }
    }
}
