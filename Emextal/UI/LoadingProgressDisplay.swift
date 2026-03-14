import Foundation
import SwiftUI

struct LoadingProgressDisplay: View {
    struct Status: Equatable, Identifiable {
        var id: String {
            text
        }

        let loaded: Bool
        let text: String
    }

    let title: String
    let progress: CGFloat
    let status: [Status]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 12) {
                ForEach(status) { statusItem in
                    HStack {
                        Image(systemName: statusItem.loaded ? "checkmark.circle" : "circle.dotted.circle")
                            .foregroundStyle(statusItem.loaded ? .accent : .primary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(statusItem.text)
                    }
                }
                .font(.title2)
            }

            ProgressView(value: progress)
        }
    }
}
