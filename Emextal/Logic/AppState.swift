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

        let inputNode = engine.inputNode
        let recorder = Recorder(inputNode: inputNode)

        let speaker = Speaker(engine: engine)

        let mic = Mic(recorder: recorder)

        Task {
            // Apple's Voice Processing I/O unit (enabled below for echo cancellation) couples the
            // microphone input and speaker output into a single audio unit, so the engine can only
            // start once microphone access has been granted. Request it up front rather than waiting
            // until a conversation begins, otherwise the output unit fails to initialise at launch.
            _ = await AVCaptureDevice.requestAccess(for: .audio)

            // Enable the built-in echo canceller so the spoken TTS output is removed from the
            // always-on microphone signal (otherwise the speaker feeds back into the VAD, and
            // barge-in can't work). On iOS we also configure the shared session: using the input
            // node forces the `playAndRecord` category, whose default output route is the receiver
            // (the earpiece used during phone calls), so route playback to the built-in speaker
            // while still allowing Bluetooth accessories. macOS has no audio session; routing
            // follows the system Sound preferences.
            do {
                #if os(iOS)
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                    try session.setActive(true)
                #endif
                try engine.inputNode.setVoiceProcessingEnabled(true)
            } catch {
                log("Could not enable echo cancellation: \(error)")
            }

            do {
                try engine.start()
            } catch {
                // Voice processing can fail to initialise on some output devices or when input is
                // unavailable. Fall back to a plain engine (no echo cancellation / barge-in) so the
                // app still launches rather than failing outright.
                log("Audio engine start failed with voice processing (\(error)); retrying without it")
                try? engine.inputNode.setVoiceProcessingEnabled(false)
                do {
                    try engine.start()
                } catch {
                    mode = .error(title: "Audio engine start failed", error: error)
                    return
                }
            }

            do {
                async let speakerBoot = speaker.boot()
                async let micBoot = mic.boot()
                try await speakerBoot
                try await micBoot
            } catch {
                mode = .error(title: "Audio engine boot failed", error: error)
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
