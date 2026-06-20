import SwiftUI

struct ConversationView: View {
    @Bindable var conversation: Conversation

    @FocusState private var focusEntryField

    @State private var inputHeight: CGFloat = 0

    var body: some View {
        #if os(visionOS)
            let spacing: CGFloat = 18
        #else
            let spacing: CGFloat = 8
        #endif

        HStack(spacing: spacing) {
            VStack(spacing: spacing) {
                WebView(viewModel: conversation)

                TextField("Hold \"↓\" to speak, or enter your message here", text: $conversation.prompt)
                    .textFieldStyle(.plain)
                    .onAppear { focusEntryField = true }
                #if os(visionOS)
                    .padding(22)
                    .background(.ultraThinMaterial)
                #else
                    .padding(7)
                    .padding(.horizontal, 5)
                    .background {
                        Capsule()
                            .foregroundStyle(.material)
                    }
                #endif
                    .focused($focusEntryField)
                    .onSubmit {
                        conversation.respondToTypedPrompt()
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { newValue in
                        inputHeight = newValue
                    }
            }

            VStack(spacing: spacing) {
                SideBar(state: conversation)

                MemoryBar(state: conversation)
                    .frame(width: SideBar.width, height: inputHeight)
            }
        }
        .padding(spacing)
        .colorScheme(.dark)
        .toolbar {
            Button {
                conversation.textOnly.toggle()
            } label: {
                Label(conversation.textOnly ? "Text Only" : "Spoken Replies", systemImage: conversation.textOnly ? "text.bubble" : "speaker.wave.2.bubble")
                    .labelStyle(.titleAndIcon)
            }

            let va = conversation.activationState == .voiceActivated
            Button { [weak conversation] in
                guard let conversation else { return }
                if va {
                    conversation.switchToPushButton()
                } else {
                    conversation.switchToVoiceActivated()
                }
            } label: {
                Label(va ? "Voice Activated" : "Manual", systemImage: va ? "waveform.badge.microphone" : "mic")
                    .labelStyle(.titleAndIcon)
            }
            .opacity(conversation.mode.showAlwaysOn ? 1 : 0.3)
            .allowsHitTesting(conversation.mode.showAlwaysOn)

            let ready = conversation.mode.nominal

            Button {
                if conversation.mode.isWaiting || conversation.mode.isQuietListening || conversation.mode.isReplying {
                    conversation.reset()
                }
            } label: {
                Label("Reset", systemImage: "clear")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut(KeyEquivalent("k"), modifiers: .command)
            .opacity(ready ? 1 : 0.3)
            .allowsHitTesting(ready)

            Button {
                NotificationCenter.default.post(name: .endModel, object: nil)
                Task {
                    await conversation.shutdown()
                }
            } label: {
                Label("Models", systemImage: "square.grid.3x2")
                    .labelStyle(.titleAndIcon)
            }
            .opacity(ready ? 1 : 0.3)
            .allowsHitTesting(ready)
        }
        .animation(.easeInOut, value: conversation.mode)
        .animation(.easeInOut, value: conversation.attachedImage)
    }
}
