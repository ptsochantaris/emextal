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
             nemotronCascade,
             gemmaLm,
             smol,
             deepseek,
             devstral,
             mistral,
             llama,
             sage

        var repoId: String {
            switch self {
            case .qwen35opus: "Jackrong/MLX-Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-v2-4bit"
            case .qwen35regular: "Brooooooklyn/Qwen3.5-27B-unsloth-mlx"
            case .qwen35moe: "Brooooooklyn/Qwen3.5-35B-A3B-unsloth-mlx"
            case .qwen3coderNext: "mlx-community/Qwen3-Coder-Next-4bit"
            case .gptOss: "mlx-community/gpt-oss-20b-MXFP4-Q8"
            case .nemotronCascade: "mlx-community/Nemotron-Cascade-2-30B-A3B-4bit"
            case .smol: "mlx-community/SmolLM3-3B-4bit"
            case .gemmaLm: "mlx-community/gemma-3n-E4B-it-lm-4bit"
            case .deepseek: "mlx-community/DeepSeek-R1-0528-4bit"
            case .devstral: "mlx-community/mistralai_Devstral-Small-2-24B-Instruct-2512-MLX-4Bit"
            case .mistral: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit"
            case .llama: "mlx-community/Llama-3.3-70B-Instruct-4bit"
            case .sage: "apple/sage-ft-mixtral-8x7b"
            }
        }

        var recommended: Bool {
            self == .qwen35moe
        }

        private var defaultPrompt: String {
            switch self {
            case .devstral, .qwen3coderNext:
                "You are a helpful AI coding assistant"
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .nemotronCascade, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                "You are a helpful AI chatbot"
            }
        }

        var originalRepoUrl: URL {
            URL(string: "https://huggingface.co/\(repoId)")!
        }

        var sizeDescription: String {
            switch self {
            case .qwen3coderNext: "44.8 GB"
            case .qwen35regular: "16.1 GB"
            case .qwen35moe: "20.4 GB"
            case .qwen35opus: "15.1 GB"
            case .gptOss: "12.1 GB"
            case .nemotronCascade: "17.8 GB"
            case .smol: "1.8 GB"
            case .deepseek: "378 GB"
            case .devstral: "13.3 GB"
            case .gemmaLm: "3.9 GB"
            case .llama: "39.7 GB"
            case .mistral: "13.3 GB"
            case .sage: "26.3 GB"
            }
        }

        var memoryEstimate: Int64 {
            switch self {
            case .qwen3coderNext: 44 * gb
            case .qwen35regular: 20 * gb
            case .qwen35moe: 20 * gb
            case .qwen35opus: 17 * gb
            case .gptOss: 14 * gb
            case .nemotronCascade: 20 * gb
            case .smol: 5 * gb
            case .deepseek: 1 * gb // TODO:
            case .devstral: 1 * gb // TODO:
            case .gemmaLm: 6 * gb
            case .llama: 1 * gb // TODO:
            case .mistral: 1 * gb // TODO:
            case .sage: 1 * gb // TODO:
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
            case .gptOss: "OpenAI's open-weight language model."
            case .nemotronCascade: "A model with strong mathematical and logical reasoning."
            case .smol: "A very capable mini-model by HuggingFace, currently with the top performance in the compact model range."
            case .devstral: "This model claims to be the top coding model for its size, but heavily quantised."
            case .mistral: "Multilingual and very knowledge-dense model by Mistral."
            case .llama: "The regular version of the latest Llama-3 model from Meta."
            case .gemmaLm: "The compact and very capable Gemma 3 model."
            case .deepseek: "Deepseek's latest R1 model."
            case .sage: "A state of the art Apple model focusing on empathy and emptional intelligence."
            }
        }

        var warningBeforeStart: Bool {
            (memoryEstimate + Model.gb) > Memory.memoryLimit
        }

        private var defaultTopK: Int {
            switch self {
            case .devstral, .nemotronCascade, .qwen3coderNext:
                40
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                20
            }
        }

        private var defaultTopP: Float {
            switch self {
            case .devstral, .nemotronCascade, .qwen3coderNext:
                0.95
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                0.8
            }
        }

        private var defaultMinP: Float {
            0.0
        }

        private var defaultTemperature: Float {
            switch self {
            case .devstral, .nemotronCascade, .qwen3coderNext:
                1.0
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                0.7
            }
        }

        private var defaultRepeatPenatly: Float {
            1.0
        }

        private var defaultFrequencyPenalty: Float {
            switch self {
            case .devstral, .nemotronCascade, .qwen3coderNext:
                0.0
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                0.7
            }
        }

        private var supportsQuantisation: Bool {
            switch self {
            case .gemmaLm:
                false
            case .deepseek, .devstral, .gptOss, .llama, .mistral, .nemotronCascade, .qwen3coderNext, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                true
            }
        }

        var supportsThinking: Bool {
            switch self {
            case .smol:
                true
            case .deepseek, .devstral, .gemmaLm, .gptOss, .llama, .mistral, .nemotronCascade, .qwen3coderNext, .qwen35moe, .qwen35opus, .qwen35regular, .sage:
                false
            }
        }

        private var defaultEnableThinking: Bool {
            false
        }

        private var defaultPresentPenalty: Float {
            switch self {
            case .devstral, .nemotronCascade, .qwen3coderNext:
                1.0
            case .deepseek, .gemmaLm, .gptOss, .llama, .mistral, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                1.5
            }
        }

        var architecture: Architecture {
            switch self {
            case .deepseek, .devstral, .gemmaLm, .gptOss, .llama, .mistral, .nemotronCascade, .qwen3coderNext, .qwen35opus, .sage, .smol:
                .llm
            case .qwen35moe, .qwen35regular:
                .vlm
            }
        }

        var injectThinkingTag: Bool {
            switch self {
            case .qwen35opus:
                true
            case .deepseek, .devstral, .gemmaLm, .gptOss, .llama, .mistral, .nemotronCascade, .qwen3coderNext, .qwen35moe, .qwen35regular, .sage, .smol:
                false
            }
        }

        var acceptsSystemPrompt: Bool {
            switch self {
            case .qwen3coderNext:
                false
            case .deepseek, .devstral, .gemmaLm, .gptOss, .llama, .mistral, .nemotronCascade, .qwen35moe, .qwen35opus, .qwen35regular, .sage, .smol:
                true
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
            case .smol: "SmolLM 2"
            case .gemmaLm: "Gemma 3n"
            case .deepseek: "Deepseek R1"
            case .mistral: "Mistral Small 2501"
            case .llama: "Llama 3.3"
            case .devstral: "Devstral 2"
            case .sage: "Sage"
            }
        }

        var detail: String {
            switch self {
            case .qwen35opus, .qwen35regular: "35b params MoE"
            case .qwen35moe: "27b params"
            case .qwen3coderNext: "80b params"
            case .gptOss: "20b params"
            case .nemotronCascade: "30b params"
            case .smol: "1.7b params"
            case .mistral: "24b params"
            case .gemmaLm: "4b params"
            case .deepseek: "105b params"
            case .devstral: "4b params"
            case .llama: "70b params"
            case .sage: "56b params MoE"
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
            case .smol: "650C7684-B76F-42CE-9EAD-8BCC4BD9C247"
            case .mistral: "7F570A81-8489-4930-BF88-9278AE4E2ED5"
            case .deepseek: "C45DB369-0F20-490C-A18B-9989DB487879"
            case .devstral: "7A282082-2990-42EC-ACF0-C4AFF41326C6"
            case .gemmaLm: "FD83A01A-0B6D-4836-A2B9-2FE6761FC4D5"
            case .llama: "73476AA8-9D1E-444C-B6C0-140A4682A67D"
            case .sage: "D1D170A3-3CDD-40EF-9456-1741BF22EBB4"
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
