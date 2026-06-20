import Foundation
import SwiftUI

struct ImageWrapper: View {
    let image: ImageClass

    var body: some View {
        #if canImport(AppKit)
            Image(nsImage: image)
                .resizable()
        #elseif canImport(UIKit)
            Image(uiImage: image)
                .resizable()
        #endif
    }
}
