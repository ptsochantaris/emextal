import AVFoundation
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

extension NSImage {
    private nonisolated static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private nonisolated static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue

    nonisolated func fit(side: CGFloat) -> NSImage? {
        let newSize: CGSize
        if size.width > size.height {
            // landscape
            let s = side / size.height
            newSize = CGSize(width: size.width * s, height: size.height * s)
        } else {
            // square or portrait
            let s = side / size.width
            newSize = CGSize(width: size.width * s, height: size.height * s)
        }
        return scale(outputSize: newSize)
    }

    private nonisolated func scale(outputSize: CGSize) -> NSImage? {
        guard let cgImage = unsafe cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelOutputWidth = Int(outputSize.width)
        let pixelOutputHeight = Int(outputSize.height)

        let cgContext = unsafe CGContext(data: nil, width: pixelOutputWidth, height: pixelOutputHeight, bitsPerComponent: 8, bytesPerRow: pixelOutputWidth * 4, space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

        guard let cgContext else {
            return nil
        }
        cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelOutputWidth, height: pixelOutputHeight))

        guard let result = cgContext.makeImage() else {
            return nil
        }
        return NSImage(cgImage: result, size: outputSize)
    }
}
