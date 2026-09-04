import Foundation
import SwiftUI

struct LoadingProgressDisplay: View {
    struct Status: Equatable, Identifiable {
        enum Phase {
            case waiting, loading, warmup, done
        }

        /// Keyed on the label rather than the whole value, so that a changing `detail` updates the
        /// existing row instead of replacing it — a new identity would restart the icon transition.
        var id: String {
            text
        }

        let phase: Phase
        let text: String

        /// Optional second line, such as the size and speed of an in-flight download.
        let detail: String?

        init(phase: Phase, text: String, detail: String? = nil) {
            self.phase = phase
            self.text = text
            self.detail = detail
        }
    }

    let progress: CGFloat
    let status: [Status]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(status) { statusItem in
                LoadingRow(title: statusItem.text, phase: statusItem.phase, detail: statusItem.detail)
            }
        }

        // Bytes land in large bursts a few seconds apart, so the bar is glided between readings
        // rather than being allowed to jump.
        ProgressView(value: max(0, min(1, progress)))
            .animation(.easeOut(duration: 1), value: progress)
    }
}
