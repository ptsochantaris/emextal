import Foundation
import SwiftUI

/// Slider for the conversation context size (KV-cache window). Ranges from a 4K-token floor up to the
/// model's native maximum, snapping to 1024-token boundaries. The top of the track is "Unbounded",
/// which stores `nil` to keep MLX's default unlimited cache (the same as not specifying a size).
struct ContextRow: View {
    @Binding var contextSize: Int?
    let maxContextTokens: Int

    private let minContextTokens = 4096
    private let step = 1024

    var body: some View {
        let isUnbounded = (contextSize ?? maxContextTokens) >= maxContextTokens

        let sliderValue = Binding<Double> {
            Double(contextSize ?? maxContextTokens)
        } set: { newValue in
            let rounded = Int((newValue / Double(step)).rounded()) * step
            contextSize = rounded >= maxContextTokens ? nil : rounded
        }

        VStack {
            HStack {
                Text("Context Size")
                    .opacity(0.8)
                if isUnbounded {
                    Text("Unbounded")
                } else {
                    Text("\(contextSize ?? maxContextTokens, format: .number) tokens")
                }
                Spacer()
            }
            Slider(value: sliderValue, in: Double(minContextTokens) ... Double(maxContextTokens))
        }
    }
}
