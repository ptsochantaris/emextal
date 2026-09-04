import Foundation
import SwiftUI

struct LoadingRow: View {
    let title: String
    let phase: LoadingProgressDisplay.Status.Phase
    var detail: String? = nil

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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)

                if let detail {
                    // Monospaced digits stop the line jittering as digit widths change. No numeric
                    // content transition: most of the line is not numeric, so rolling the whole
                    // string reads as noise at this update cadence.
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .font(.title2)
        .animation(.default, value: detail)
    }
}
