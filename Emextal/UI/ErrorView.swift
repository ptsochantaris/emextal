import Foundation
import SwiftUI

struct ErrorView: View {
    let title: String
    let error: any Error

    var body: some View {
        ZStack {
            PlainBackground()

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title)

                Text(String(describing: error))
            }
            .multilineTextAlignment(.leading)
            .padding(88)
            .foregroundStyle(.white)
        }
    }
}
