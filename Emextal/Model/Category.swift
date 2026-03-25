import Foundation

extension Model {
    enum Category: Int, CaseIterable, Identifiable {
        var id: Int {
            rawValue
        }

        case qwen

        var title: String {
            switch self {
            case .qwen: "Qwen"
            }
        }

        var description: String {
            switch self {
            case .qwen:
                "The Qwen models are consistently rated both highly in benchmarks and by users."
            }
        }
    }
}
