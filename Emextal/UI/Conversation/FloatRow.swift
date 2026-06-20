import Foundation
import SwiftUI

struct FloatRow: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    @Binding var value: Float

    var body: some View {
        VStack {
            DescriptorTitle(descriptor: descriptor, value: value)
            Slider(value: .round(from: $value), in: descriptor.min ... descriptor.max)
        }
    }
}
