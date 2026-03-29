import SwiftUI

@Observable
final class AppState {
    private(set) var mode = AppStateMode.menu

    var title: String {
        guard let conversation = mode.conversation else {
            return "Emextal"
        }

        return switch conversation.mode {
        case .loading: "Loading \(conversation.displayName)"
        case .loaded: conversation.displayName
        case .error: "Loading Failed"
        default: "Emextal – \(conversation.displayName)"
        }
    }

    init() {
        let center = NotificationCenter.default
        Task { [weak self] in
            for await notification in center.notifications(named: .startModel) {
                guard let self else { return }
                if let model = notification.object as? Model {
                    mode = .conversation(.init(model: model))
                }
            }
        }
        Task {
            for await notification in center.notifications(named: .deleteModel) {
                if let model = notification.object as? Model {
                    model.delete()
                }
            }
        }
        Task { [weak self] in
            for await _ in center.notifications(named: .endModel) {
                guard let self else { return }
                mode = .menu
            }
        }
        Task { [weak self] in
            for await notification in center.notifications(named: .shutdown) {
                #if canImport(AppKit)
                    if let app = notification.object as? NSApplication {
                        guard let self else { return }
                        await mode.conversation?.shutdown()
                        log("Shutdown complete, terminating.")
                        app.reply(toApplicationShouldTerminate: true)
                    }
                #endif
            }
        }
    }
}
