import SwiftUI

extension Notification.Name {
    static let shutdown = Notification.Name("Shutdown")
    static let startModel = Notification.Name("StartModel")
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
    private let appState = AppState()

    #if canImport(AppKit)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onReceive(NotificationCenter.default.publisher(for: .startModel)) { notification in
                    if let model = notification.object as? Model {
                        appState.go(conversation: .init(model: model))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .shutdown)) { notification in
                    #if canImport(AppKit)
                        if let app = notification.object as? NSApplication {
                            Task {
                                await appState.shutdown()
                                log("Shutdown complete, terminating.")
                                app.reply(toApplicationShouldTerminate: true)
                            }
                        }
                    #endif
                }
        }
    }
}
