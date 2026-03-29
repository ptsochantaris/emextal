import SwiftUI

struct AssetCell: View {
    let model: Model
    @Binding var selected: Model?

    @Environment(\.openURL) var openUrl

    var body: some View {
        ZStack(alignment: .top) {
            PickerEntryBackground()

            let variant = model.variant
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text(variant.displayName)
                        .font(.title2)
                        .lineLimit(1)
                        .foregroundStyle(selected == model ? .accent : .primary)

                    HStack(spacing: 4) {
                        Text(variant.detail)
                            .lineLimit(1)

                        Button {
                            openUrl(variant.originalRepoUrl)
                        } label: {
                            Image(systemName: "questionmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if selected != model {
                    Text(variant.aboutText)
                }

                Spacer(minLength: 0)

                HStack {
                    if let info = model.status {
                        Text(info)
                            .font(.caption2)
                            .padding(4)
                            .padding(.horizontal, 4)
                            .background {
                                Capsule()
                                    .foregroundStyle(.material)
                            }
                    }

                    Spacer()

                    Text(variant.sizeDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 2)
                }
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(minHeight: 0)
            .opacity(variant.warningBeforeStart ? 0.6 : 1.0)

            if selected == model {
                ZStack {
                    RoundedRectangle(cornerSize: CGSize(width: 20, height: 20), style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 3))
                        .padding(1)

                    Button {
                        NotificationCenter.default.post(name: .startModel, object: model)
                    } label: {
                        Image(systemName: "play.fill")
                            .resizable()
                            .frame(width: 36, height: 42)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.accent)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selected = model
            }
        }
    }
}
