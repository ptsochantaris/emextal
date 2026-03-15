internal import MLXLMCommon
internal import SwiftUI

struct ContentView: View {
    private let viewModel: ViewModel

    @FocusState private var promptFocused

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            switch viewModel.mode {
            case let .loading(progress, status):
                LoadingProgressDisplay(title: viewModel.displayName, progress: progress, status: status)
                    .colorScheme(.dark)
                    .padding(88)
                    .navigationTitle("Loading \(viewModel.displayName)")

            case let .error(error):
                Text("**Loading failed:** \(String(describing: error))")
                    .colorScheme(.dark)
                    .padding(88)
                    .navigationTitle("Loading Failed")

            default:
                ConversationView(state: viewModel)
                    .navigationTitle("Emextal – \(viewModel.displayName)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarTitleDisplayMode(.inline)
        .background {
            switch viewModel.mode {
            case .loading:
                ShimmerBackground(show: .constant(true))
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()

            default:
                Image(.background)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            }
        }
    }
}
