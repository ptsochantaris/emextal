import Foundation
import MLX

struct MemoryStats {
    let active: String
    let activePeak: String

    let cache: String
    let cacheLimit: String

    let total: String
    let totalLimit: String

    let activePercent: CGFloat
    let cachePercent: CGFloat

    init() {
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
}
