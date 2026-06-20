import Foundation
import SwiftUI

struct ActiveBackground: View {
    var body: some View {
        ShimmerBackground(show: .constant(true))
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}
