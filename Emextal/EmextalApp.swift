import SwiftUI

extension Notification.Name {
    static let shutdown = Notification.Name("Shutdown")
    static let startModel = Notification.Name("StartModel")
    static let endModel = Notification.Name("EndModel")
    static let deleteModel = Notification.Name("DeleteModel")
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
        }
    }
}
