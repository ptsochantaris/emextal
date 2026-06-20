import Foundation
import SwiftUI

struct DescriptorTitle: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    let value: Float

    var body: some View {
        HStack {
            Text(descriptor.title)
                .opacity(0.8)
            if value == descriptor.disabled {
                Text("Disabled")
            } else {
                Text(value, format: .number)
            }
            Spacer()
        }
    }
}
