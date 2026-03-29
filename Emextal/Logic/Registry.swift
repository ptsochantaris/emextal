enum Registry {
    static let allCategories: [Model.Category] = [
        .qwen
    ]

    static let allModels: [Model] = [
        .init(category: .qwen, variant: .qwen35regular),
        .init(category: .qwen, variant: .qwen35moe),
        .init(category: .qwen, variant: .qwen3coderNext),
        .init(category: .qwen, variant: .qwen35opus)
    ]

    static func variants(for category: Model.Category) -> [Model] {
        allModels.filter { $0.category == category }
    }

    static func category(for variant: Model.Variant) -> Model.Category? {
        allModels.first { $0.variant == variant }?.category
    }
}
