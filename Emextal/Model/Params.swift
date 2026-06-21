import Foundation
import MLXLMCommon

extension Model {
    struct ParamsHolder: Codable {
        let modelId: String
        let params: Model.Params
    }

    struct Params {
        enum Descriptors {
            struct Descriptor {
                let title: String
                let min: Float
                let max: Float
                let disabled: Float
            }

            static let topK = Descriptor(title: "Top-K", min: 0, max: 200, disabled: 0)
            static let topP = Descriptor(title: "Top-P", min: 0, max: 2, disabled: 0)
            static let minP = Descriptor(title: "Min-P", min: 0, max: 1, disabled: 0.1)
            static let temperature = Descriptor(title: "Temperature", min: 0, max: 2, disabled: 0)
            static let repeatPenatly = Descriptor(title: "Repeat Penalty", min: 1, max: 4, disabled: 1)
            static let frequencyPenatly = Descriptor(title: "Frequency Penalty", min: 0, max: 4, disabled: 0)
            static let presentPenatly = Descriptor(title: "Presence Penalty", min: 1, max: 4, disabled: 1)
        }

        /// The KV-cache memory strategy. MLX exposes three mutually exclusive options, so they're
        /// modelled as one choice rather than independent knobs (illegal combinations can't be expressed):
        /// - `unbounded`: `KVCacheSimple`, retains the whole conversation at full precision.
        /// - `window`: `RotatingKVCache`, caps the cache to a rotating window of the given token count
        ///   (full precision, drops the oldest context once full).
        /// - `quantized`: an unbounded cache that MLX upgrades to a `QuantizedKVCache` during generation,
        ///   retaining all context but storing it at the given bit depth to save memory.
        enum CacheStrategy: Codable, Equatable {
            case unbounded
            case window(tokens: Int)
            case quantized(bits: Int)
        }

        var topK: Int
        var topP: Float
        var minP: Float
        var systemPrompt: String
        var temperature: Float
        var repeatPenatly: Float
        var frequencyPenatly: Float
        var presentPenatly: Float
        var enableThinking: Bool
        var cacheStrategy: CacheStrategy

        var mlx: GenerateParameters {
            let repeatResolved = repeatPenatly == Descriptors.repeatPenatly.disabled ? nil : repeatPenatly
            let frequencyResolved = frequencyPenatly == Descriptors.frequencyPenatly.disabled ? nil : frequencyPenatly
            let presenceResolved = presentPenatly == Descriptors.presentPenatly.disabled ? nil : presentPenatly

            let maxKVSize: Int?
            let kvBits: Int?
            switch cacheStrategy {
            case .unbounded:
                maxKVSize = nil
                kvBits = nil
            case let .window(tokens):
                maxKVSize = tokens
                kvBits = nil
            case let .quantized(bits):
                maxKVSize = nil
                kvBits = bits
            }

            return .init(
                maxKVSize: maxKVSize,
                kvBits: kvBits,
                kvGroupSize: 64,
                quantizedKVStart: 0,
                temperature: temperature,
                topP: topP,
                topK: topK,
                minP: minP,
                repetitionPenalty: repeatResolved, repetitionContextSize: 64,
                presencePenalty: presenceResolved, presenceContextSize: 64,
                frequencyPenalty: frequencyResolved, frequencyContextSize: 64
            )
        }
    }
}

extension Model.Params: Codable {
    private enum CodingKeys: String, CodingKey {
        case topK, topP, minP, systemPrompt, temperature
        case repeatPenatly, frequencyPenatly, presentPenatly, enableThinking
        case cacheStrategy
        // Legacy key, decoded only for backward compatibility (see init(from:)).
        case contextSize
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topK = try container.decode(Int.self, forKey: .topK)
        topP = try container.decode(Float.self, forKey: .topP)
        minP = try container.decode(Float.self, forKey: .minP)
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        temperature = try container.decode(Float.self, forKey: .temperature)
        repeatPenatly = try container.decode(Float.self, forKey: .repeatPenatly)
        frequencyPenatly = try container.decode(Float.self, forKey: .frequencyPenatly)
        presentPenatly = try container.decode(Float.self, forKey: .presentPenatly)
        enableThinking = try container.decode(Bool.self, forKey: .enableThinking)

        // Prefer the current `cacheStrategy`. Older saved params instead carried an optional
        // `contextSize`, where a value meant a bounded window and its absence meant the default
        // unbounded cache; migrate those onto the new model.
        if let strategy = try container.decodeIfPresent(CacheStrategy.self, forKey: .cacheStrategy) {
            cacheStrategy = strategy
        } else if let legacyContextSize = try container.decodeIfPresent(Int.self, forKey: .contextSize) {
            cacheStrategy = .window(tokens: legacyContextSize)
        } else {
            cacheStrategy = .unbounded
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(topK, forKey: .topK)
        try container.encode(topP, forKey: .topP)
        try container.encode(minP, forKey: .minP)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(repeatPenatly, forKey: .repeatPenatly)
        try container.encode(frequencyPenatly, forKey: .frequencyPenatly)
        try container.encode(presentPenatly, forKey: .presentPenatly)
        try container.encode(enableThinking, forKey: .enableThinking)
        try container.encode(cacheStrategy, forKey: .cacheStrategy)
    }
}
