import SwiftUI

struct ContentView: View {
    @Bindable private(set) var appState: AppState

    @FocusState private var promptFocused

    var body: some View {
        ZStack {
            switch appState.mode {
            case .menu:
                SelectionGrid(selected: $appState.selectedModel)

            case let .error(title, error):
                ErrorView(title: title, error: error)

            case let .conversation(conversation):
                ConversationContainer(conversation: conversation)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.selectedModel)
        .animation(.easeInOut, value: appState.mode)
        .navigationTitle(appState.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog("This model will not fit into memory, are you sure?", isPresented: $appState.memoryWarning) {
            Button("Load Model", role: .destructive) {
                NotificationCenter.default.post(name: .startModelWithoutConfirming, object: nil)
            }
        }
    }
}
