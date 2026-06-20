import Foundation
import SwiftUI

private let startTime = Date.now.addingTimeInterval(Double.random(in: -10 ..< 0))

struct Genie: View {
    let show: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.034, paused: !show)) {
            let elapsedTime = startTime.distance(to: $0.date)
            EllipticalGradient(colors: [.black.opacity(0.1), .clear], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .visualEffect { content, proxy in
                    content
                        .colorEffect(
                            ShaderLibrary.genie(
                                .float2(proxy.size),
                                .float(elapsedTime)
                            )
                        )
                }
        }
    }
}
