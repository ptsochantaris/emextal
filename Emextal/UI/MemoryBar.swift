import SwiftUI

struct MemoryBar: View {
    let state: ViewModel

    var body: some View {
        ZStack {
            let memoryStats = state.memoryStats

            GeometryReader { proxyTotal in
                HStack(spacing: 0) {
                    let fill = proxyTotal.size.width * (memoryStats.activePercent + memoryStats.cachePercent)

                    Capsule()
                        .frame(width: fill)
                        .foregroundColor(.widgetForeground.opacity(0.3))

                    Spacer(minLength: 0)
                }
            }
            .padding(5)
            .background {
                Capsule()
                    .foregroundStyle(.material)
            }

            Text(memoryStats.total + " / " + memoryStats.totalLimit)
                .font(.caption2)
        }
    }
}
