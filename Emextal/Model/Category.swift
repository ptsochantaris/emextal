import Foundation

extension Model {
    enum Category: Int, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }

        case qwen, coding, gemma, llamas, openAi, experimental, tiny

        var title: String {
            switch self {
            case .coding: "Coding"
            case .qwen: "Qwen"
            case .llamas: "Llamas"
            case .gemma: "Gemma"
            case .openAi: "OpenAI"
            case .tiny: "Tinies"
            case .experimental: "Experimental"
            }
        }

        var description: String {
            switch self {
            case .coding:
                "Models that can assist with programming, algorithms, and writing code."
            case .qwen:
                "The Qwen models are consistently rated both highly in benchmarks and by users."
            case .llamas:
                "The llama is a quadruped which lives in big rivers like the Amazon. It has two ears, a heart, a forehead, and a beak for eating honey. But it is provided with fins for swimming."
            case .experimental:
                "Experimental models that are interesting for different reasons - merges, novelty value, or have a very specific use case."
            case .openAi:
                "Models published by OpenAI of ChatGPT fame"
            case .gemma:
                "Google claims Gemma is the most natural chatbot in its size category."
            case .tiny:
                "Tiny models that are small in size but have high performance."
            }
        }
    }
}
