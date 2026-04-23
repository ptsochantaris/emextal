import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLMHFAPI
import PopTimer
import Tokenizers

@Observable
final class Model: Hashable, Identifiable, Sendable {
    let id: String
    let category: Category
    let variant: Variant

    var status: String?

    private var saveTimer: PopTimer?

    var params: Params {
        didSet {
            saveTimer?.push()
        }
    }

    var isInstalled = false

    private func updateInstalled() throws -> Bool {
        modelDirectory != nil
    }

    var modelContainer: ModelContainer?

    static func installModel(id: String, parentProgress: Progress, progressCount: Int64) async throws -> URL {
        let repoId = Repo.ID(stringLiteral: id)
        let modelDestination = HubCache.default.snapshotPath(repo: repoId, kind: .model, revision: "main")
        if let modelDestination {
            parentProgress.completedUnitCount += progressCount
            return modelDestination
        } else {
            nonisolated(unsafe) var addedChild = false
            let progressHandler = { @Sendable (progress: Progress) in
                _ = Task { @MainActor in
                    if unsafe !addedChild {
                        unsafe addedChild = true
                        parentProgress.addChild(progress, withPendingUnitCount: progressCount)
                    }
                }
            }

            let hubClientOnline = HubClient(useOfflineMode: false)
            return try await hubClientOnline.downloadSnapshot(of: repoId, progressHandler: progressHandler)
        }
    }

    func install(parentProgress: Progress, progressCount: Int64) async throws {
        defer {
            updateStatus()
        }

        let loader = #huggingFaceTokenizerLoader() // TODO: Use integration package instead of HF tokenizer
        let snapshotPath = try await Self.installModel(id: variant.repoId, parentProgress: parentProgress, progressCount: progressCount)
        modelContainer = try await loadModelContainer(from: snapshotPath, using: loader)
    }

    func delete() {
        let repoDirectory = HubCache.default.repoDirectory(repo: Repo.ID(stringLiteral: variant.repoId), kind: .model)
        let fm = FileManager.default
        if fm.fileExists(atPath: repoDirectory.path) {
            try? fm.removeItem(at: repoDirectory)
        }

        updateStatus()
    }

    nonisolated static let appDocumentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    var modelDirectory: URL? {
        HubCache.default.snapshotPath(repo: Repo.ID(stringLiteral: variant.repoId), kind: .model, revision: "main")
    }

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

        updateStatus()

        saveTimer = PopTimer(timeInterval: 0.1) { [weak self] in
            self?.save()
        }
    }

    var additionalContext: [String: any Sendable] {
        if variant.supportsThinkingSwitch {
            ["enable_thinking": params.enableThinking]
        } else {
            [:]
        }
    }

    func updateStatus() {
        isInstalled = (try? updateInstalled()) == true
        status = if isInstalled {
            "INSTALLED"
        } else {
            variant == .qwen35regular ? "START HERE" : nil
        }
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

    var shouldWarnAboutMemory: Bool {
        let limit = Int64(Double(Memory.memoryLimit) * 0.9)
        return variant.memoryEstimate > limit
    }
}
