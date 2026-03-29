import Foundation

extension Model {
    enum Category: Int, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }

        case qwen, dolphin, samantha, coding, creative, gemma, llamas, mistrals, apple, glm, openAi, nvidia, experimental

        var title: String {
            switch self {
            case .dolphin: "Dolphin"
            case .coding: "Coding"
            case .qwen: "Qwen"
            case .creative: "Creative"
            case .samantha: "Samantha"
            case .llamas: "Llamas"
            case .gemma: "Gemma"
            case .glm: "GLM"
            case .apple: "Apple"
            case .mistrals: "Mistral"
            case .openAi: "OpenAI"
            case .nvidia: "Nvidia"
            case .experimental: "Experimental"
            }
        }

        var description: String {
            switch self {
            case .dolphin:
                "The Dolphin dataset produces some of the best LLMs out there. This is a selection of models finetuned with this dataset."
            case .coding:
                "Models that can assist with programming, algorithms, and writing code."
            case .creative:
                "Models that can help with creative activities, such as writing. More will be added soon."
            case .samantha:
                "The \"sister\" of Dolphin, Samantha is a data set which produces models based on the premise they are sentient, and emotionally supportive of the user."
            case .mistrals:
                "Mistral models have proven over time to be dependable and consistently used as the base of many other models."
            case .qwen:
                "The Qwen models are consistently rated both highly in benchmarks and by users."
            case .llamas:
                "The llama is a quadruped which lives in big rivers like the Amazon. It has two ears, a heart, a forehead, and a beak for eating honey. But it is provided with fins for swimming."
            case .experimental:
                "Experimental models that are interesting for different reasons - merges, novelty value, or have a very specific use case."
            case .openAi:
                "Models published by OpenAI of ChatGPT fame"
            case .gemma:
                "Google claims Gemma 3 is the most natural chatbot in its size category."
            case .nvidia:
                "Models released as open source by Nvidia."
            case .apple:
                "Models published by Apple, focusing on maximising performance at each size category."
            case .glm:
                "ChatGLM is made by the THUDM group at Tsinghua University and is quite good at logic and coding tasks."
            }
        }
    }
}
