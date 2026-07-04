import SwiftUI

struct SectionCell: View {
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title)

                Text(description)
                    .font(.caption2)

                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
    }
}
