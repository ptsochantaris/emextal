import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ImageDrop: View {
    let state: ViewModel

    @State private var busy = false

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
                    .frame(height: 88)

            } else if let image = state.attachedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
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

            } else {
                Image(systemName: "photo")
                    .font(.title)
                    .frame(height: 88)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            if busy || state.attachedImage == nil {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(style: .init(lineWidth: 2, lineCap: .round, dash: [2.0, 4.0]))
            }
        }
        .onDrop(of: [.png, .jpeg], isTargeted: nil) { providers in
            busy = true
            providers.first?.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage,
                      let scaled = image.fit(side: 512)
                else {
                    return
                }
                Task { @MainActor in
                    withAnimation {
                        state.attachedImage = scaled
                        busy = false
                    }
                }
            }
            return true
        }
    }
}

struct SideBar: View {
    let state: ViewModel

    var body: some View {
        VStack(spacing: 0) {
            if state.mode.showGenie {
                Color.clear
                    .frame(height: 16)

                Genie(show: state.mode.showGenie)
                    .padding(.top, -4)
                    .padding(.bottom, -1)

            } else {
                if state.supportsImageInputs {
                    ImageDrop(state: state)
                        .padding()
                        .foregroundColor(.widgetForeground.opacity(0.7))
                }

                Spacer()
            }

            ModeView(modeProvider: state)
                .padding(.bottom, 4)
                .padding([.leading, .trailing])
                .foregroundColor(.widgetForeground.opacity(state.mode.isWaiting ? 0.7 : 0.8))
                .frame(height: assistantWidth) // make it square
        }
        .foregroundColor(.widgetForeground)
        .background {
            Rectangle()
                .foregroundStyle(.material)
        }
        .frame(width: assistantWidth)
        .cornerRadius(21)
    }
}
