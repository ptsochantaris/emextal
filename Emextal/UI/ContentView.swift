import MLXLMCommon
import SwiftUI

struct ContentView: View {
    private let viewModel: ViewModel

    @FocusState private var promptFocused

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    private var shimmer: some View {
        ShimmerBackground(show: .constant(true))
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }

    private var image: some View {
        Image(.background)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }

    private var loadTop: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.displayName)
                .font(.title.bold())

            switch viewModel.mode {
            case let .loading(progress, status):
                LoadingProgressDisplay(progress: progress, status: status)

            case let .loaded(container):
                HStack {
                    LoadingRow(title: "Ready", done: true)
                    Spacer()
                    Button("Start") {
                        withAnimation {
                            viewModel.start(modelContainer: container)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case let .error(error):
                Text("**Loading failed:** \(String(describing: error))")

            default:
                EmptyView()
            }

            ParamsView(model: viewModel.model)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(88)
    }

    @ViewBuilder
    private var background: some View {
        switch viewModel.mode {
        case .loading:
            shimmer

        default:
            image
        }
    }

    private var title: String {
        switch viewModel.mode {
        case .loading:
            "Loading \(viewModel.displayName)"

        case .loaded:
            viewModel.displayName

        case .error:
            "Loading Failed"

        default:
            "Emextal – \(viewModel.displayName)"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch viewModel.mode {
                case .error, .loaded, .loading:
                    loadTop

                default:
                    ConversationView(state: viewModel)
                }
            }
            .background {
                background
            }
        }
        .navigationTitle(title)
        .animation(.easeInOut, value: viewModel.mode)
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarTitleDisplayMode(.inline)
    }
}
