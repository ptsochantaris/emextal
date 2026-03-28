import Foundation
import MLX

@Observable
final class MemoryStats {
    var active = ""
    var activePeak = ""

    var cache = ""
    var cacheLimit = ""

    var total = ""
    var totalLimit = ""

    var activePercent: CGFloat = 0
    var cachePercent: CGFloat = 0

    private func update() {
        active = memoryFormatter.format(Int64(Memory.activeMemory))
        activePeak = memoryFormatter.format(Int64(Memory.peakMemory))

        let limit64 = Int64(Memory.memoryLimit)

        cache = memoryFormatter.format(Int64(Memory.cacheMemory))
        cacheLimit = memoryFormatter.format(limit64)

        let sum = Memory.activeMemory + Memory.cacheMemory
        total = memoryFormatter.format(Int64(sum))
        totalLimit = memoryFormatter.format(limit64)

        let limit = CGFloat(limit64)
        activePercent = CGFloat(Memory.activeMemory) / limit
        cachePercent = CGFloat(Memory.cacheMemory) / limit
    }

    init() {
        Task { [weak self] in
            while !Task.isCancelled {
                self?.update()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
