import Foundation
import MLX

extension Model {
    enum Variant: Identifiable {
        case qwen35regular,
             qwen35moe

        var recommended: Bool {
            self == .qwen35moe
        }

        private var defaultPrompt: String {
            switch self {
            case .qwen35moe, .qwen35regular:
                "You are a helpful AI chatbot"
            }
        }

        var memoryEstimate: Int64 {
            let gb: Int64 = 1024 * 1024 * 1024

            return switch self {
            case .qwen35regular:
                21 * gb // TODO:
            case .qwen35moe:
                21 * gb // TODO:
            }
        }

        var memoryStrings: (used: String, max: String, system: String) {
            let bytes = memoryBytes
            return (memoryFormatter.format(bytes.used),
                    memoryFormatter.format(bytes.max),
                    memoryFormatter.format(Int64(bytes.systemTotal)))
        }

        var memoryBytes: (used: Int64, max: Int64, systemTotal: UInt64) {
            (Int64(Memory.activeMemory),
             Int64(Memory.memoryLimit),
             ProcessInfo.processInfo.physicalMemory)
        }

        var aboutText: String {
            switch self {
            case .qwen35moe, .qwen35regular: "A consistently well regarded all-round model by users and benchmarks."
            }
        }

        // temperature=0.7, top_p=0.8, top_k=20, min_p=0.0, presence_penalty=1.5, repetition_penalty=1.0

        private var defaultTopK: Int {
            20
        }

        private var defaultTopP: Float {
            0.8
        }

        private var defaultMinP: Float {
            0.0
        }

        private var defaultTemperature: Float {
            0.7
        }

        private var defaultRepeatPenatly: Float {
            1.0
        }

        private var defaultFrequencyPenalty: Float {
            1.0
        }

        private var defaultPresentPenalty: Float {
            1.5
        }

        var acceptsSystemPrompt: Bool {
            true
        }

        var displayName: String {
            switch self {
            case .qwen35regular: "Qwen 3.5 Regular"
            case .qwen35moe: "Qwen 3.5 (MoE)"
            }
        }

        var detail: String {
            switch self {
            case .qwen35regular: "35b params MoE"
            case .qwen35moe: "27b params"
            }
        }

        var repoId: String {
            switch self {
            case .qwen35regular: "mlx-community/Qwen3.5-27B-4bit"
            case .qwen35moe: "mlx-community/Qwen3.5-35B-A3B-4bit"
            }
        }

        var id: String {
            switch self {
            case .qwen35regular: "A16F9CE6-CC01-4EBC-9444-EC07E80FCA5C"
            case .qwen35moe: "231FF4EE-ECD2-45A1-87B5-79084B0ECFBF"
            }
        }

        var defaultParams: Params {
            Params(topK: defaultTopK,
                   topP: defaultTopP,
                   minP: defaultMinP,
                   systemPrompt: defaultPrompt,
                   temperature: defaultTemperature,
                   repeatPenatly: defaultRepeatPenatly,
                   frequencyPenatly: defaultFrequencyPenalty,
                   presentPenatly: defaultPresentPenalty)
        }
    }
}
