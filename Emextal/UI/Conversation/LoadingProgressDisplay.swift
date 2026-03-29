import Foundation
import SwiftUI

struct LoadingRow: View {
    let title: String
    let done: Bool

    var body: some View {
        HStack {
            Image(systemName: done ? "checkmark.circle" : "circle.dotted.circle")
                .foregroundStyle(done ? .accent : .primary)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
        }
        .font(.title2)
    }
}

struct LoadingProgressDisplay: View {
    struct Status: Equatable, Identifiable {
        var id: String {
            text
        }

        let loaded: Bool
        let text: String
    }

    let progress: CGFloat
    let status: [Status]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(status) { statusItem in
                LoadingRow(title: statusItem.text, done: statusItem.loaded)
            }
        }

        ProgressView(value: progress)
    }
}
