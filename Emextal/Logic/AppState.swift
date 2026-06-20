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

    private let engine = AVAudioEngine()

    init() {
        if let id = Persisted.lastSelectedModelId {
            selectedModel = Registry.allModels.first(where: { $0.id == id })
        }

        engine.inputNode.volume = 1.0

        // Enable Apple's voice-processing I/O on the input node, which runs the built-in echo
        // canceller so the spoken TTS output is removed from the always-on microphone signal
        // (otherwise the speaker feeds back into the VAD). This works on both macOS and iOS, and
        // must happen before the Recorder samples the input node's format below, as it changes
        // the I/O format. On iOS we additionally configure the shared session: using the input
        // node forces the `playAndRecord` category, whose default output route is the receiver
        // (the earpiece used during phone calls), so route playback to the built-in speaker
        // instead while still allowing Bluetooth accessories. macOS has no audio session; its
        // routing follows the system Sound preferences.
        do {
            #if os(iOS)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                try session.setActive(true)
            #endif
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            log("Could not configure audio session / echo cancellation: \(error)")
        }

        let inputNode = engine.inputNode
        let recorder = Recorder(inputNode: inputNode)

        let speaker = Speaker(engine: engine)

        let mic = Mic(recorder: recorder)

        Task {
            do {
                try engine.start()
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
