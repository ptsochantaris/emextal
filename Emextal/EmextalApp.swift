import SwiftUI

extension Notification.Name {
    static let shutdown = Notification.Name("Shutdown")
}

#if canImport(AppKit)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            true
        }

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            Task {
                NotificationCenter.default.post(name: .shutdown, object: sender)
            }
            return .terminateLater
        }
    }
#endif

@main
struct EmextalApp: App {
    private let viewModel = ViewModel(model: Model(category: .qwen, variant: .qwen35moe))

    #if canImport(AppKit)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onReceive(NotificationCenter.default.publisher(for: .shutdown)) { notification in
                    #if canImport(AppKit)
                        if let app = notification.object as? NSApplication {
                            Task {
                                await viewModel.shutdown()
                                log("Shutdown complete, terminating.")
                                app.reply(toApplicationShouldTerminate: true)
                            }
                        }
                    #endif
                }
        }
    }
}
