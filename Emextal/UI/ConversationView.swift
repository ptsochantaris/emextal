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
