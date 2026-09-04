import SwiftUI

struct ConversationContainer: View {
    let conversation: Conversation
    let model: Model?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    private func loadTop(conversation: Conversation) -> some View {
        let content = VStack(alignment: .leading, spacing: 16) {
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
                    .foregroundStyle(.black)
                    .buttonStyle(.borderedProminent)
                }

            case let .error(error):
                Text("**Loading failed:** \(String(describing: error))")

            default:
                EmptyView()
            }

            if let model {
                ParamsView(model: model)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                // No model, no params panel — but that panel is where "Back" normally lives.
                Button("Back") {
                    NotificationCenter.default.post(name: .endModel, object: nil)
                }
            }
        }
        .padding(horizontalSizeClass == .compact ? 10 : 88)
        .animation(.easeInOut, value: model?.params.cacheStrategy)

        // This panel is rigid vertically: its minimum height is its ideal height. Placed in the window
        // directly it therefore becomes the window's minimum content height, and while loading — status
        // rows plus the params panel — that is taller than a good many screens, which leaves the window
        // pinned to full height with no way to drag it back down. Scrolling gives it a zero minimum,
        // and the `minHeight` keeps it centred in the viewport for as long as it does fit.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
