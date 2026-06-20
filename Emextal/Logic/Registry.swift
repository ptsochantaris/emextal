enum Registry {
    static let allModels: [Model] = [
        .init(category: .qwen, variant: .qwen36regular),
        .init(category: .qwen, variant: .qwen36moe),
        .init(category: .qwen, variant: .qwen3coderNext),
        .init(category: .gemma, variant: .gemma4),
        .init(category: .openAi, variant: .gptOssLarge),
        .init(category: .openAi, variant: .gptOss),
        .init(category: .llamas, variant: .llama),
        .init(category: .tiny, variant: .smol),
        .init(category: .experimental, variant: .qwen36deckard),
        .init(category: .experimental, variant: .nemotronCascade)
    ]

    static func variants(for category: Model.Category) -> [Model] {
        allModels.filter { $0.category == category }
    }

    static func category(for variant: Model.Variant) -> Model.Category? {
        allModels.first { $0.variant == variant }?.category
    }
}
