import Foundation
import SwiftUI

struct SideBar: View {
    let state: Conversation

    static let width: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            if state.mode.showGenie {
                Color.clear
                    .frame(height: 16)

                Genie(show: state.mode.showGenie)
                    .padding(.top, -4)
                    .padding(.bottom, -1)

            } else {
                if state.supportsImageInputs {
                    ImageDrop(state: state)
                        .padding()
                        .foregroundColor(.widgetForeground.opacity(0.7))
                }

                Spacer()
            }

            ModeView(modeProvider: state)
                .padding(.bottom, 4)
                .padding([.leading, .trailing])
                .foregroundColor(.widgetForeground.opacity(state.mode.isWaiting ? 0.7 : 0.8))
                .frame(height: Self.width) // make it square
        }
        .foregroundColor(.widgetForeground)
        .background {
            Rectangle()
                .foregroundStyle(.material)
        }
        .frame(width: Self.width)
        .cornerRadius(21)
    }
}
