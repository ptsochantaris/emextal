import Foundation
import MLXLMCommon

extension Model {
    struct ParamsHolder: Codable {
        let modelId: String
        let params: Model.Params
    }

    struct Params: Codable {
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

        var topK: Int
        var topP: Float
        var minP: Float
        var systemPrompt: String
        var temperature: Float
        var repeatPenatly: Float
        var frequencyPenatly: Float
        var presentPenatly: Float
        var enableThinking: Bool
        let supportsQuantisation: Bool

        var mlx: GenerateParameters {
            let repeatResolved = repeatPenatly == Descriptors.repeatPenatly.disabled ? nil : repeatPenatly
            let frequencyResolved = frequencyPenatly == Descriptors.frequencyPenatly.disabled ? nil : frequencyPenatly
            let presenceResolved = presentPenatly == Descriptors.presentPenatly.disabled ? nil : presentPenatly

            return if supportsQuantisation {
                .init(
                    kvBits: 8,
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
            } else {
                .init(
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
}
