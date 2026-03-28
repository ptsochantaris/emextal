import Foundation
import PopTimer

@MainActor
@Observable
final class Model: Hashable, Identifiable, Sendable {
    let id: String
    let category: Category
    let variant: Variant

    private var saveTimer: PopTimer?

    var params: Params {
        didSet {
            saveTimer?.push()
        }
    }

    static let appDocumentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    static let modelsDir = appDocumentsUrl.appendingPathComponent("models", conformingTo: .directory)

    nonisolated static func == (lhs: Model, rhs: Model) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(category: Category, variant: Variant) {
        let myId = "\(category.id)-\(variant.id)"
        id = myId
        self.category = category
        self.variant = variant

        if let modelParams = Persisted.modelParams, let list = try? JSONDecoder().decode([ParamsHolder].self, from: modelParams), let mine = list.first(where: { $0.modelId == myId }) {
            params = mine.params
        } else {
            params = variant.defaultParams
        }

        saveTimer = PopTimer(timeInterval: 0.1) { [weak self] in
            self?.save()
        }
    }

    var additionalContext: [String: any Sendable] {
        variant.additionalContext
    }

    var modelHistoryPath: URL {
        let modelDir = Self.modelsDir
        let fm = FileManager.default
        if !fm.fileExists(atPath: modelDir.path) {
            try! fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
        }
        return modelDir.appendingPathComponent("history.json")
    }

    private var localStatePath: URL {
        let fm = FileManager.default
        let statePath = Model.appDocumentsUrl.appendingPathComponent("states-\(variant.id)", conformingTo: .directory)
        if !fm.fileExists(atPath: statePath.path) {
            try? fm.createDirectory(at: statePath, withIntermediateDirectories: true)
        }
        return statePath
    }

    func resetToDefaults() {
        params = variant.defaultParams
    }

    func save() {
        var list = if let modelParams = Persisted.modelParams, let list = try? JSONDecoder().decode([ParamsHolder].self, from: modelParams) {
            list
        } else {
            [ParamsHolder]()
        }

        let myParams = ParamsHolder(modelId: id, params: params)
        if let index = list.firstIndex(where: { $0.modelId == myParams.modelId }) {
            list[index] = myParams
        } else {
            list.append(myParams)
        }
        Persisted.modelParams = try? JSONEncoder().encode(list)
        log("Saved params for model \(id)")
    }

    var memoryEstimate: (used: String, max: String, system: String) {
        variant.memoryStrings
    }
}
