import Foundation

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

        init(topK: Int = 0, topP: Float = 0, minP: Float = 0, systemPrompt: String = "", temperature: Float = 0, repeatPenatly: Float = 0, frequencyPenatly: Float = 0, presentPenatly: Float = 0) {
            self.topK = topK
            self.topP = topP
            self.minP = minP
            self.systemPrompt = systemPrompt
            self.temperature = temperature
            self.repeatPenatly = repeatPenatly
            self.frequencyPenatly = frequencyPenatly
            self.presentPenatly = presentPenatly
        }
    }
}
