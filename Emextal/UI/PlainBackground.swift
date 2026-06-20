import Foundation
import SwiftUI

struct PlainBackground: View {
    var body: some View {
        Image(.background)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }
}
