import SwiftUI

#if canImport(AppKit)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            true
        }
    }
#endif

@main
struct EmextalApp: App {
    private let viewModel = ViewModel(model: Model(category: .qwen, variant: .qwen3coderNext))

    #if canImport(AppKit)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onDisappear {
                    Task {
                        await viewModel.shutdown()
                    }
                }
        }
    }
}
