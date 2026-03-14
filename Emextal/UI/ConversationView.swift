import AVFoundation
import SwiftUI

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

                SideBar(state: state, focusEntryField: $focusEntryField)
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
        .onDrop(of: [.png, .jpeg], isTargeted: nil) { providers in
            providers.first?.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage,
                      let scaled = image.fit(side: 512)
                else {
                    return
                }
                Task { @MainActor in
                    withAnimation {
                        state.attachedImage = scaled
                    }
                }
            }
            return true
        }
        .colorScheme(.dark)
        .toolbar {
            Button {
                state.textOnly.toggle()
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: state.textOnly ? "text.bubble" : "speaker.wave.2.bubble")
                    Text(state.textOnly ? "Text-Only" : "Spoken Replies")
                        .padding([.leading, .trailing], 4)
                        .font(.caption)
                }
            }

            let ready = state.mode.nominal

            /*
             Button {
                 appPhase = .selection
             } label: {
                 HStack(spacing: 0) {
                     Image(systemName: "square.grid.3x2")
                     Text("Models")
                         .padding([.leading, .trailing], 4)
                         .font(.caption)
                 }
             }
             .opacity(ready ? 1 : 0.3)
             .allowsHitTesting(ready)
              */

            Button {
                if state.mode.isWaiting || state.mode.isQuietListening || state.mode.isReplying {
                    state.reset()
                }
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: "clear")
                    Text("Reset")
                        .padding([.leading, .trailing], 4)
                        .font(.caption)
                }
            }
            .keyboardShortcut(KeyEquivalent("k"), modifiers: .command)
            .opacity(ready ? 1 : 0.3)
            .allowsHitTesting(ready)
        }
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
