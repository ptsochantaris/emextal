import Foundation
import SwiftUI

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
