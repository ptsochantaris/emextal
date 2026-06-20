import Foundation
import SwiftUI

struct IntRow: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    @Binding var value: Int

    var body: some View {
        VStack {
            DescriptorTitle(descriptor: descriptor, value: Float(value))
            Slider(value: .convert(from: $value), in: descriptor.min ... descriptor.max)
        }
    }
}
