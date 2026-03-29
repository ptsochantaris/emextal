import Foundation
import MLX

extension Model {
    static let gb: Int64 = 1024 * 1024 * 1024

    enum Architecture {
        case llm, vlm

        var supportsImageInputs: Bool {
            switch self {
            case .llm: false
            case .vlm: true
            }
        }
    }

    enum Variant: Identifiable {
        case qwen35regular,
             qwen35moe,
             qwen3coderNext,
             qwen35opus

        var recommended: Bool {
            self == .qwen35moe
        }

        private var defaultPrompt: String {
            switch self {
            case .qwen3coderNext:
                ""
            case .qwen35moe, .qwen35regular, .qwen35opus:
                "You are a helpful AI chatbot"
            }
        }

        var originalRepoUrl: URL {
            URL(string: "https://huggingface.com/\(repoId)")!
        }

        var sizeDescription: String {
            switch self {
            case .qwen3coderNext:
                "44.8 GB"
            case .qwen35regular:
                "16.1 GB"
            case .qwen35moe:
                "20.4 GB"
            case .qwen35opus:
                "15.1 GB"
            }
        }

        var memoryEstimate: Int64 {
            switch self {
            case .qwen3coderNext:
                44 * gb
            case .qwen35regular:
                21 * gb // TODO:
            case .qwen35moe:
                21 * gb // TODO:
            case .qwen35opus:
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
            case .qwen3coderNext, .qwen35moe, .qwen35regular: "A consistently well regarded all-round model by users and benchmarks."
            case .qwen35opus: "An analytical logic model trained on the Opus dataset."
            }
        }

        var warningBeforeStart: Bool {
            (memoryEstimate + Model.gb) > Memory.memoryLimit
        }

        private var defaultTopK: Int {
            switch self {
            case .qwen3coderNext:
                40
            case .qwen35moe, .qwen35regular, .qwen35opus:
                20
            }
        }

        private var defaultTopP: Float {
            switch self {
            case .qwen3coderNext:
                0.95
            case .qwen35moe, .qwen35regular, .qwen35opus:
                0.8
            }
        }

        private var defaultMinP: Float {
            0.0
        }

        private var defaultTemperature: Float {
            switch self {
            case .qwen3coderNext:
                1.0
            case .qwen35moe, .qwen35regular, .qwen35opus:
                0.7
            }
        }

        private var defaultRepeatPenatly: Float {
            1.0
        }

        private var defaultFrequencyPenalty: Float {
            switch self {
            case .qwen3coderNext:
                0.0
            case .qwen35moe, .qwen35regular, .qwen35opus:
                0.7
            }
        }

        private var defaultPresentPenalty: Float {
            switch self {
            case .qwen3coderNext:
                1.0
            case .qwen35moe, .qwen35regular, .qwen35opus:
                1.5
            }
        }

        var architecture: Architecture {
            switch self {
            case .qwen3coderNext, .qwen35opus:
                .llm
            case .qwen35moe, .qwen35regular:
                .vlm
            }
        }

        var injectThinkingTag: Bool {
            switch self {
            case .qwen35opus:
                true
            case .qwen3coderNext, .qwen35moe, .qwen35regular:
                false
            }
        }

        var acceptsSystemPrompt: Bool {
            switch self {
            case .qwen3coderNext:
                false
            case .qwen35moe, .qwen35regular, .qwen35opus:
                true
            }
        }

        var additionalContext: [String: any Sendable] {
            switch self {
            case .qwen35moe, .qwen35regular:
                ["enable_thinking": false]
            case .qwen35opus:
                ["enable_thinking": true]
            case .qwen3coderNext:
                [:]
            }
        }

        var displayName: String {
            switch self {
            case .qwen35regular: "Qwen 3.5 Regular"
            case .qwen35moe: "Qwen 3.5 (MoE)"
            case .qwen3coderNext: "Qwen 3 Coder Next"
            case .qwen35opus: "Qwen 3.5 Opus Distilled"
            }
        }

        var detail: String {
            switch self {
            case .qwen35regular, .qwen35opus: "35b params MoE"
            case .qwen35moe: "27b params"
            case .qwen3coderNext: "80b params"
            }
        }

        var repoId: String {
            switch self {
            case .qwen35opus: "mlx-community/Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit"
            case .qwen35regular: "mlx-community/Qwen3.5-27B-4bit"
            case .qwen35moe: "mlx-community/Qwen3.5-35B-A3B-4bit"
            case .qwen3coderNext: "mlx-community/Qwen3-Coder-Next-4bit"
            }
        }

        var id: String {
            switch self {
            case .qwen35opus: "3AF730C4-E787-42CE-86C2-87C1B7A66CF2"
            case .qwen35regular: "A16F9CE6-CC01-4EBC-9444-EC07E80FCA5C"
            case .qwen35moe: "231FF4EE-ECD2-45A1-87B5-79084B0ECFBF"
            case .qwen3coderNext: "A6D0B2BC-7C5E-4692-8ABA-8779D57665AC"
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
