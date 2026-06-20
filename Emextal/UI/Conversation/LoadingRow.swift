import Foundation
import SwiftUI

struct LoadingRow: View {
    let title: String
    let phase: LoadingProgressDisplay.Status.Phase

    var body: some View {
        HStack {
            Group {
                switch phase {
                case .waiting:
                    Image(systemName: "circle.dotted.circle")
                        .foregroundStyle(.primary)

                case .loading:
                    Image(systemName: "arrowshape.down.circle")
                        .foregroundStyle(.primary)

                case .warmup:
                    Image(systemName: "circle")
                        .foregroundStyle(.accent)

                case .done:
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.accent)
                }
            }
            .contentTransition(.symbolEffect(.replace))

            Text(title)
        }
        .font(.title2)
    }
}
