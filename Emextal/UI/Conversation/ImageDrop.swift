import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ImageDrop: View {
    let state: Conversation

    @State private var busy = false

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
                    .frame(height: 88)

            } else if let image = state.attachedImage {
                ImageWrapper(image: image)
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
            providers.first?.loadObject(ofClass: ImageClass.self) { item, _ in
                guard let image = item as? ImageClass,
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
