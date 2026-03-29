import SwiftUI

struct ConversationContainer: View {
    let conversation: Conversation

    private func loadTop(conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(conversation.displayName)
                .font(.title.bold())

            switch conversation.mode {
            case let .loading(progress, status):
                LoadingProgressDisplay(progress: progress, status: status)

            case let .loaded(container):
                HStack {
                    LoadingRow(title: "Ready", done: true)
                    Spacer()
                    Button("Start") {
                        withAnimation {
                            conversation.start(modelContainer: container)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case let .error(error):
                Text("**Loading failed:** \(String(describing: error))")

            default:
                EmptyView()
            }

            ParamsView(model: conversation.model)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(88)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch conversation.mode {
                case .error, .loaded, .loading:
                    loadTop(conversation: conversation)

                default:
                    ConversationView(conversation: conversation)
                }
            }
            .background {
                background
            }
        }
        .animation(.easeInOut, value: conversation.mode)
    }

    @ViewBuilder
    private var background: some View {
        switch conversation.mode {
        case .loading:
            ActiveBackground()

        default:
            PlainBackground()
        }
    }
}
