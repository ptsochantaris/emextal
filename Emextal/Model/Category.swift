import Foundation

extension Model {
    enum Category: Int, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }

        case qwen, openAi, nvidia

        var title: String {
            switch self {
            case .qwen: "Qwen"
            case .openAi: "OpenAI"
            case .nvidia: "NVidia"
            }
        }

        var description: String {
            switch self {
            case .qwen:
                "The Qwen models are consistently rated both highly in benchmarks and by users."
            case .openAi:
                "The maker of ChatGPT's open source contribution"
            case .nvidia:
                "NVidia's own open source models"
            }
        }
    }
}
