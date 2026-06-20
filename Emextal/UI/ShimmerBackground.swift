import Foundation
import SwiftUI

private let startTime = Date.now.addingTimeInterval(Double.random(in: -10 ..< 0))

struct ShimmerBackground: View {
    @Binding var show: Bool

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation(minimumInterval: 0.06, paused: !show)) {
                let elapsedTime = startTime.distance(to: $0.date)
                Rectangle()
                    .visualEffect { content, proxy in
                        content
                            .colorEffect(
                                ShaderLibrary.pickerBackground(
                                    .float2(proxy.size),
                                    .float(elapsedTime)
                                )
                            )
                    }
            }
        }
    }
}
