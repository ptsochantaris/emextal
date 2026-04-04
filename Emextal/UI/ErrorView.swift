import Foundation
import SwiftUI

struct ErrorView: View {
    let title: String
    let error: any Error

    var body: some View {
        ZStack {
            VStack(alignment: .leading) {
                Text(title)
                    .font(.title)

                Text(String(describing: error))
            }
            .multilineTextAlignment(.leading)
        }
        .background {
            PlainBackground()
        }
    }
}
