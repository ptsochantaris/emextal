import SwiftUI

/// The "Utilities" row of the selection grid: conversation flavours that don't involve a
/// language model. Currently just transcription.
struct UtilitySection: View {
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                SectionCell(title: "Utilities", description: "Voice-driven features which use no language model, and are ready to go immediately.")
                    .frame(width: 200)

                TranscriptionCell()
                #if canImport(AppKit)
                    .aspectRatio(1.2, contentMode: .fit)
                #else
                    .aspectRatio(1.8, contentMode: .fit)
                #endif
            }
            .frame(height: 200)
            .scrollIndicators(.hidden)
            .padding([.trailing, .top, .bottom])
        }
        .background(.white.opacity(0.3).blendMode(.softLight))
    }
}

struct TranscriptionCell: View {
    var body: some View {
        ZStack(alignment: .top) {
            PickerEntryBackground()

            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("Transcription")
                        .font(.title2)
                        .lineLimit(1)

                    Text("Dictation, without AI")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Speak, and build up a text transcript that you can copy out. Nothing is sent to a language model.")

                Spacer(minLength: 0)

                HStack {
                    Text("BUILT-IN")
                        .font(.caption2)
                        .padding(4)
                        .padding(.horizontal, 4)
                        .background {
                            Capsule()
                                .foregroundStyle(.material)
                        }

                    Spacer()

                    Button("Start") {
                        NotificationCenter.default.post(name: .startTranscription, object: nil)
                    }
                    .foregroundStyle(.black)
                    .buttonStyle(.borderedProminent)
                }
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(minHeight: 0)
        }
    }
}
