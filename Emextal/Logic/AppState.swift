import AVFoundation
import SwiftUI

@Observable
final class AppState {
    var selectedModel: Model? {
        didSet {
            Persisted.lastSelectedModelId = selectedModel?.id
        }
    }

    private(set) var mode = AppStateMode.menu

    var memoryWarning = false

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

    private nonisolated(unsafe) let engine = AVAudioEngine()

    init() {
        if let id = Persisted.lastSelectedModelId {
            selectedModel = Registry.allModels.first(where: { $0.id == id })
        }

        unsafe engine.inputNode.volume = 1.0

        nonisolated(unsafe) let inputNode = unsafe engine.inputNode
        let recorder = Recorder(inputNode: unsafe inputNode)

        let speaker = Speaker(engine: unsafe engine)

        let mic = Mic(recorder: recorder)

        Task {
            do {
                unsafe try engine.start()
                async let speakerBoot = speaker.boot()
                async let micBoot = mic.boot()
                try await speakerBoot
                try await micBoot
            } catch {
                mode = .error(title: "Audio engine start failed", error: error)
            }
        }

        let center = NotificationCenter.default

        Task { [weak self] in
            for await _ in center.notifications(named: .startModel) {
                guard let self, let selectedModel else { return }
                if selectedModel.shouldWarnAboutMemory {
                    memoryWarning = true
                } else {
                    NotificationCenter.default.post(name: .startModelWithoutConfirming, object: nil)
                }
            }
        }
        Task { [weak self] in
            for await _ in center.notifications(named: .startModelWithoutConfirming) {
                guard let self, let selectedModel else { return }
                mode = .conversation(.init(model: selectedModel, speaker: speaker, mic: mic))
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
