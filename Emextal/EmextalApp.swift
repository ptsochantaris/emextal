import SwiftUI

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
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
    }
}
