import Foundation
import SwiftUI

struct SideBar: View {
    let state: ViewModel
    @FocusState.Binding var focusEntryField: Bool

    @State private var originalPos: CGPoint? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 33)

            if state.mode.showGenie {
                Genie(show: state.mode.showGenie)
                    .padding(.top, -4)
                    .padding(.bottom, -1)
                    .gesture(DragGesture().onChanged { value in
                        dragged(by: value)
                    }.onEnded { _ in
                        dragEnd()
                    })

            } else {
                let va = state.activationState == .voiceActivated
                if state.mode.showAlwaysOn {
                    Button("ALWAYS ON") { [weak state] in
                        guard let state else { return }
                        if va {
                            state.switchToPushButton()
                        } else {
                            state.switchToVoiceActivated()
                        }
                    }
                    .font(.caption2.bold())
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(va ? .accent : .widgetForeground)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background {
                        Capsule(style: .continuous)
                            .stroke(va ? .accent : .widgetForeground, lineWidth: 1)
                    }
                    .padding(1)
                }

                Color(.clear)
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        dragged(by: value)
                    }.onEnded { _ in
                        dragEnd()
                    })
            }

            ModeView(modeProvider: state)
                .padding(.bottom, 4)
                .padding([.leading, .trailing])
                .foregroundColor(.widgetForeground.opacity(state.mode.isWaiting ? 0.7 : 0.8))
                .frame(height: assistantWidth) // make it square

            if let image = state.attachedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                    .frame(width: assistantWidth)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation {
                                state.attachedImage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 0)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
            }
        }
        .foregroundColor(.widgetForeground)
        .background {
            Rectangle()
                .foregroundStyle(.material)
        }
        .frame(width: assistantWidth)
        .cornerRadius(21)
    }

    private func dragged(by value: DragGesture.Value) {
        #if canImport(AppKit)
            guard let window = NSApplication.shared.keyWindow else {
                return
            }
            var frame = window.frame
            let p = window.frame.origin
            frame.origin = CGPoint(x: p.x + value.translation.width, y: p.y - value.translation.height)
            originalPos = frame.origin
            window.setFrame(frame, display: false)
        #endif
    }

    private func dragEnd() {
        originalPos = nil
    }
}
