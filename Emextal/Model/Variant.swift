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
             qwen35opus,
             gptOss,
             nemotronCascade

        var repoId: String {
            switch self {
            case .qwen35opus: "Jackrong/MLX-Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2-4bit"
            case .qwen35regular: "Brooooooklyn/Qwen3.5-27B-unsloth-mlx"
            case .qwen35moe: "Brooooooklyn/Qwen3.5-35B-A3B-unsloth-mlx"
            case .qwen3coderNext: "mlx-community/Qwen3-Coder-Next-4bit"
            case .gptOss: "mlx-community/gpt-oss-20b-MXFP4-Q8"
            case .nemotronCascade: "mlx-community/Nemotron-Cascade-2-30B-A3B-4bit"
            }
        }

        var recommended: Bool {
            self == .qwen35moe
        }

        private var defaultPrompt: String {
            switch self {
            case .qwen3coderNext:
                ""
            case .gptOss, .nemotronCascade, .qwen35moe, .qwen35opus, .qwen35regular:
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
            case .gptOss:
                "12.1 GB"
            case .nemotronCascade:
                "17.8 GB"
            }
        }

        var memoryEstimate: Int64 {
            switch self {
            case .qwen3coderNext:
                44 * gb
            case .qwen35regular:
                20 * gb
            case .qwen35moe:
                20 * gb
            case .qwen35opus:
                17 * gb
            case .gptOss:
                14 * gb
            case .nemotronCascade:
                20 * gb
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
            case .gptOss: "OpenAI's open source LLM"
            case .nemotronCascade: "A model with strong mathematical reasoning"
            }
        }

        var warningBeforeStart: Bool {
            (memoryEstimate + Model.gb) > Memory.memoryLimit
        }

        private var defaultTopK: Int {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                40
            case .gptOss, .qwen35moe, .qwen35opus, .qwen35regular:
                20
            }
        }

        private var defaultTopP: Float {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                0.95
            case .gptOss, .qwen35moe, .qwen35opus, .qwen35regular:
                0.8
            }
        }

        private var defaultMinP: Float {
            0.0
        }

        private var defaultTemperature: Float {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                1.0
            case .gptOss, .qwen35moe, .qwen35opus, .qwen35regular:
                0.7
            }
        }

        private var defaultRepeatPenatly: Float {
            1.0
        }

        private var defaultFrequencyPenalty: Float {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                0.0
            case .gptOss, .qwen35moe, .qwen35opus, .qwen35regular:
                0.7
            }
        }

        private var defaultPresentPenalty: Float {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                1.0
            case .gptOss, .qwen35moe, .qwen35opus, .qwen35regular:
                1.5
            }
        }

        var architecture: Architecture {
            switch self {
            case .gptOss, .nemotronCascade, .qwen3coderNext, .qwen35opus:
                .llm
            case .qwen35moe, .qwen35regular:
                .vlm
            }
        }

        var injectThinkingTag: Bool {
            switch self {
            case .qwen35opus:
                true
            case .gptOss, .nemotronCascade, .qwen3coderNext, .qwen35moe, .qwen35regular:
                false
            }
        }

        var acceptsSystemPrompt: Bool {
            switch self {
            case .qwen3coderNext:
                false
            case .gptOss, .nemotronCascade, .qwen35moe, .qwen35opus, .qwen35regular:
                true
            }
        }

        // TODO: separate params per variant

        /// TODO: - put this in options if the model is eligible for the thinking param
        var additionalContext: [String: any Sendable] {
            switch self {
            case .nemotronCascade, .qwen35moe, .qwen35regular:
                ["enable_thinking": false]
            case .qwen35opus:
                ["enable_thinking": true]
            case .gptOss, .qwen3coderNext:
                [:]
            }
        }

        var displayName: String {
            switch self {
            case .qwen35regular: "Qwen 3.5 Regular"
            case .qwen35moe: "Qwen 3.5 (MoE)"
            case .qwen3coderNext: "Qwen 3 Coder Next"
            case .qwen35opus: "Qwen 3.5 Opus Distilled"
            case .gptOss: "GPT Open Source"
            case .nemotronCascade: "Nemotron Cascade 2"
            }
        }

        var detail: String {
            switch self {
            case .qwen35opus, .qwen35regular: "35b params MoE"
            case .qwen35moe: "27b params"
            case .qwen3coderNext: "80b params"
            case .gptOss: "20b params"
            case .nemotronCascade: "30b params"
            }
        }

        var id: String {
            switch self {
            case .qwen35opus: "3AF730C4-E787-42CE-86C2-87C1B7A66CF2"
            case .qwen35regular: "A16F9CE6-CC01-4EBC-9444-EC07E80FCA5C"
            case .qwen35moe: "231FF4EE-ECD2-45A1-87B5-79084B0ECFBF"
            case .qwen3coderNext: "A6D0B2BC-7C5E-4692-8ABA-8779D57665AC"
            case .gptOss: "CD9DF04E-A0A7-4EAE-803F-80BCB173040E"
            case .nemotronCascade: "D9AAF39E-DE93-44C8-A613-71756BB5C57D"
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
