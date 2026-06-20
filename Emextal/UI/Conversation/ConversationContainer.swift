import SwiftUI

struct ConversationContainer: View {
    let conversation: Conversation

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private func loadTop(conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(conversation.displayName)
                .font(.title.bold())

            switch conversation.mode {
            case let .loading(progress, status):
                LoadingProgressDisplay(progress: progress, status: status)
                    .padding(.horizontal)

            case .loaded:
                HStack {
                    LoadingRow(title: "Ready", phase: .done)
                    Spacer()
                    Button("Start") {
                        conversation.start()
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
        .padding(horizontalSizeClass == .compact ? 10 : 88)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                switch conversation.mode {
                case .error, .loaded, .loading:
                    loadTop(conversation: conversation)
                        .colorScheme(.dark)

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
