import SwiftUI

struct ContentView: View {
    let appState: AppState

    @FocusState private var promptFocused

    @State private var selectedModel: Model?

    var body: some View {
        ZStack {
            switch appState.mode {
            case .menu:
                SelectionGrid(selected: $selectedModel)

            case let .conversation(conversation):
                ConversationContainer(conversation: conversation)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedModel)
        .animation(.easeInOut, value: appState.mode)
        .colorScheme(.dark)
        .navigationTitle(appState.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarTitleDisplayMode(.inline)
    }
}
