import Foundation
import SwiftUI

struct PickerEntryBackground: View {
    var body: some View {
        RoundedRectangle(cornerSize: CGSize(width: 20, height: 20), style: .continuous)
            .foregroundStyle(.primary.opacity(0.1))
    }
}
