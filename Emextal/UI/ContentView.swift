import SwiftUI

struct ContentView: View {
    private let appState: AppState

    @FocusState private var promptFocused

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        ZStack {
            switch appState.mode {
            case .menu:
                Button("Go") {
                    let newConversation = Conversation(model: Model(category: .qwen, variant: .qwen35moe))
                    appState.go(conversation: newConversation)
                }

            case let .conversation(conversation):
                ConversationContainer(conversation: conversation)
            }
        }
        .navigationTitle(appState.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarTitleDisplayMode(.inline)
    }
}
