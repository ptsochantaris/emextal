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

struct LoadingProgressDisplay: View {
    struct Status: Equatable, Identifiable {
        enum Phase {
            case waiting, loading, warmup, done
        }

        var id: String {
            text
        }

        let phase: Phase
        let text: String
    }

    let progress: CGFloat
    let status: [Status]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(status) { statusItem in
                LoadingRow(title: statusItem.text, phase: statusItem.phase)
            }
        }

        ProgressView(value: max(0, min(1, progress)))
    }
}
