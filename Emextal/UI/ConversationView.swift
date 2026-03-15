internal import AVFoundation
internal import SwiftUI

struct ConversationView: View {
    @Bindable var state: ViewModel

    @FocusState private var focusEntryField

    var body: some View {
        #if os(visionOS)
            let spacing: CGFloat = 18
        #else
            let spacing: CGFloat = 8
        #endif

        VStack(spacing: 0) {
            HStack(spacing: spacing) {
                WebView(viewModel: state)

                SideBar(state: state)
                #if os(visionOS)
                    .padding(.top, 0)
                    .padding(.bottom, spacing - 1)
                #elseif os(iOS)
                    .padding(.top, 0)
                    .padding(.bottom, spacing)
                #else
                    .padding(.top, 8)
                    .padding(.bottom, spacing)
                #endif
            }
            .padding(.horizontal, spacing)

            HStack(alignment: .bottom) {
                TextField("Hold \"↓\" to speak, or enter your message here", text: $state.prompt)
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
                    .padding(.bottom, 8)
                    .padding(.horizontal, spacing)
                #endif
                    .focused($focusEntryField)
                    .onSubmit {
                        state.respondToTypedPrompt()
                    }
            }
        }
        .colorScheme(.dark)
        .toolbar {
            Button {
                state.textOnly.toggle()
            } label: {
                Label(state.textOnly ? "Text Only" : "Spoken Replies", systemImage: state.textOnly ? "text.bubble" : "speaker.wave.2.bubble")
                    .labelStyle(.titleAndIcon)
            }

            let va = state.activationState == .voiceActivated
            Button { [weak state] in
                guard let state else { return }
                if va {
                    state.switchToPushButton()
                } else {
                    state.switchToVoiceActivated()
                }
            } label: {
                Label(va ? "Voice Activated" : "Manual", systemImage: va ? "waveform.badge.microphone" : "mic")
                    .labelStyle(.titleAndIcon)
            }
            .opacity(state.mode.showAlwaysOn ? 1 : 0.3)
            .allowsHitTesting(state.mode.showAlwaysOn)

            let ready = state.mode.nominal

            Button {
                if state.mode.isWaiting || state.mode.isQuietListening || state.mode.isReplying {
                    state.reset()
                }
            } label: {
                Label("Reset", systemImage: "clear")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut(KeyEquivalent("k"), modifiers: .command)
            .opacity(ready ? 1 : 0.3)
            .allowsHitTesting(ready)

            Button {
                // TODO:
            } label: {
                Label("Models", systemImage: "square.grid.3x2")
                    .labelStyle(.titleAndIcon)
            }
            .opacity(ready ? 1 : 0.3)
            .allowsHitTesting(ready)
        }
        .animation(.easeInOut, value: state.mode)
        .animation(.easeInOut, value: state.attachedImage)
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
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelOutputWidth = Int(outputSize.width)
        let pixelOutputHeight = Int(outputSize.height)

        let cgContext = CGContext(data: nil, width: pixelOutputWidth, height: pixelOutputHeight, bitsPerComponent: 8, bytesPerRow: pixelOutputWidth * 4, space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGImageByteOrderInfo.order32Little.rawValue)

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
