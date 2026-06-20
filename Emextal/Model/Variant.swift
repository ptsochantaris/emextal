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
        case qwen36regular,
             qwen36moe,
             qwen36deckard,
             qwen3coderNext,
             gptOss,
             gptOssLarge,
             nemotronCascade,
             smol,
             llama,
             gemma4

        var repoId: String {
            switch self {
            case .qwen36regular: "unsloth/Qwen3.6-27B-UD-MLX-4bit"
            case .qwen36moe: "unsloth/Qwen3.6-35B-A3B-UD-MLX-4bit"
            case .qwen3coderNext: "mlx-community/Qwen3-Coder-Next-4bit"
            case .gptOss: "txgsync/gpt-oss-20b-Derestricted-mxfp4-mlx"
            case .nemotronCascade: "mlx-community/Nemotron-Cascade-2-30B-A3B-4bit"
            case .smol: "mlx-community/SmolLM3-3B-4bit"
            case .llama: "mlx-community/Llama-3.3-70B-Instruct-4bit"
            case .gemma4: "unsloth/gemma-4-31b-it-UD-MLX-4bit"
            case .gptOssLarge: "txgsync/gpt-oss-120b-Derestricted-mxfp4-mlx"
            case .qwen36deckard: "mlx-community/Qwen3.6-40B-Claude-4.6-Opus-Deckard-Heretic-Uncensored-Thinking-8bit"
            }
        }

        var recommended: Bool {
            self == .qwen36regular
        }

        private var defaultPrompt: String {
            switch self {
            case .qwen3coderNext:
                "You are an AI coding assistant"
            case .gemma4, .gptOss, .gptOssLarge, .llama, .nemotronCascade, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                "You are a conversational AI chatbot"
            }
        }

        var originalRepoUrl: URL {
            URL(string: "https://huggingface.co/\(repoId)")!
        }

        var sizeDescription: String {
            switch self {
            case .qwen3coderNext: "44.8 GB"
            case .qwen36regular: "26.2 GB"
            case .qwen36moe: "21.6 GB"
            case .gptOss: "13.8 GB"
            case .nemotronCascade: "17.8 GB"
            case .smol: "1.8 GB"
            case .gptOssLarge: "65.2 GB"
            case .llama: "39.7 GB"
            case .gemma4: "18.4 GB"
            case .qwen36deckard: "41.5 GB"
            }
        }

        var memoryEstimate: Int64 {
            switch self {
            case .qwen3coderNext: 44 * gb
            case .qwen36regular: 26 * gb
            case .qwen36moe: 22 * gb
            case .gptOss: 18 * gb
            case .nemotronCascade: 20 * gb
            case .smol: 5 * gb
            case .gptOssLarge: 66 * gb
            case .llama: 1 * gb
            case .gemma4: 34 * gb
            case .qwen36deckard: 45 * gb // TODO
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
            case .qwen3coderNext, .qwen36moe, .qwen36regular: "A consistently well regarded all-round model by users and benchmarks."
            case .qwen36deckard: "Qwen 3.6 uncensored and trained on Deckard/PDK, and Claude 4.6 Opus Distill"
            case .gptOss: "Compact version of OpenAI's open-weight language model."
            case .nemotronCascade: "A model with strong mathematical and logical reasoning."
            case .smol: "A very capable mini-model by HuggingFace, currently with the top performance in the compact model range."
            case .llama: "The regular version of the latest Llama-3 model from Meta."
            case .gemma4: "The latest Gemma 4 model."
            case .gptOssLarge: "Full version of OpenAI's open-weight language model."
            }
        }

        var usesHarmony: Bool {
            switch self {
            case .gptOss:
                true
            case .gemma4, .gptOssLarge, .llama, .nemotronCascade, .qwen3coderNext, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                false
            }
        }

        var warningBeforeStart: Bool {
            (memoryEstimate + Model.gb) > Memory.memoryLimit
        }

        private var defaultTopK: Int {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                40
            case .gptOss, .gptOssLarge, .llama, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                20
            case .gemma4:
                64
            }
        }

        private var defaultTopP: Float {
            switch self {
            case .gemma4, .nemotronCascade, .qwen3coderNext:
                0.95
            case .gptOss, .gptOssLarge, .llama, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                0.8
            }
        }

        private var defaultMinP: Float {
            0.0
        }

        private var defaultTemperature: Float {
            switch self {
            case .gemma4, .nemotronCascade, .qwen3coderNext:
                1.0
            case .gptOss, .gptOssLarge, .llama, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
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
            case .gemma4, .gptOss, .gptOssLarge, .llama, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                0.7
            }
        }

        private var supportsQuantisation: Bool {
            switch self {
            case .gemma4, .gptOss, .gptOssLarge:
                false
            case .llama, .nemotronCascade, .qwen3coderNext, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                true
            }
        }

        var supportsThinkingSwitch: Bool {
            switch self {
            case .gemma4, // TODO: implement on system prompt for gemma4
                 .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                true
            case .gptOss, .gptOssLarge, .llama, .nemotronCascade, .qwen3coderNext:
                false
            }
        }

        private var defaultEnableThinking: Bool {
            false
        }

        private var defaultPresentPenalty: Float {
            switch self {
            case .nemotronCascade, .qwen3coderNext:
                1.0
            case .gemma4, .gptOss, .gptOssLarge, .llama, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                1.5
            }
        }

        var architecture: Architecture {
            switch self {
            case .gptOss, .gptOssLarge, .llama, .nemotronCascade, .qwen3coderNext, .smol:
                .llm
            case .gemma4, .qwen36moe, .qwen36regular, .qwen36deckard:
                .vlm
            }
        }

        var injectThinkingTag: Bool {
            switch self {
            case .gemma4, .gptOss, .gptOssLarge, .llama, .nemotronCascade, .qwen3coderNext, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                false
            }
        }

        var acceptsSystemPrompt: Bool {
            switch self {
            case .qwen3coderNext:
                false
            case .gemma4, .gptOss, .gptOssLarge, .llama, .nemotronCascade, .qwen36moe, .qwen36regular, .smol, .qwen36deckard:
                true
            }
        }

        var displayName: String {
            switch self {
            case .qwen36regular: "Qwen 3.6 Regular"
            case .qwen36moe: "Qwen 3.6 (MoE)"
            case .qwen36deckard: "Qwen 3.6 Deckard"
            case .qwen3coderNext: "Qwen 3 Coder Next"
            case .gptOss: "GPT OSS Compact"
            case .nemotronCascade: "Nemotron Cascade 2"
            case .smol: "SmolLM 2"
            case .gptOssLarge: "GPT OSS Regular"
            case .llama: "Llama 3.3"
            case .gemma4: "Gemma 4"
            }
        }

        var detail: String {
            switch self {
            case .qwen36moe: "35b params MoE"
            case .qwen36regular: "27b params"
            case .qwen36deckard: "40b params"
            case .qwen3coderNext: "80b params"
            case .gptOss: "20b params"
            case .nemotronCascade: "30b params"
            case .smol: "1.7b params"
            case .gptOssLarge: "117b params"
            case .llama: "70b params"
            case .gemma4: "31b params"
            }
        }

        var id: String {
            switch self {
            case .qwen36regular: "A16F4CE6-CC01-4EBC-9444-EC07E80FCA5C"
            case .qwen36moe: "231FF4DE-ECD2-45A1-87B5-79084B0ECFBF"
            case .qwen3coderNext: "A6D0B2BC-7C5E-4692-8ABA-8779D57665AC"
            case .gptOss: "CD9DF04E-A0A7-4EAE-803F-80BCB173040E"
            case .nemotronCascade: "D9AAF39E-DE93-44C8-A613-71756BB5C57D"
            case .smol: "650C7684-B76F-42CE-9EAD-8BCC4BD9C247"
            case .gptOssLarge: "D45DB369-0F20-490C-A18B-9989DB487879"
            case .llama: "73476AA8-9D1E-444C-B6C0-140A4682A67D"
            case .gemma4: "5B90E2EA-A97F-4AF5-BF99-F4E1C684D7D5"
            case .qwen36deckard: "8286D907-F97A-43C1-B046-2162D0CEE654"
            }
        }

        var defaultParams: Params {
            Params(
                topK: defaultTopK,
                topP: defaultTopP,
                minP: defaultMinP,
                systemPrompt: defaultPrompt,
                temperature: defaultTemperature,
                repeatPenatly: defaultRepeatPenatly,
                frequencyPenatly: defaultFrequencyPenalty,
                presentPenatly: defaultPresentPenalty,
                enableThinking: defaultEnableThinking,
                supportsQuantisation: supportsQuantisation
            )
        }
    }
}
