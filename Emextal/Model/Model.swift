import EmextalAudio
import Foundation
import HFAPI
import MLX
import MLXLMCommon
import PopTimer

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

    static func installModel(id: String, parentProgress: Progress, progressCount: Int64, detailHandler: (@MainActor (String?) -> Void)? = nil) async throws -> URL {
        let repoId = Repo.ID(stringLiteral: id)
        let modelDestination = HubCache.default.snapshotPath(repo: repoId, kind: .model, revision: "main")
        if let modelDestination {
            parentProgress.completedUnitCount += progressCount
            return modelDestination
        } else {
            // Progress is measured from the cache directory rather than taken from the Hub client's
            // progress object, which only moves as whole files complete — see DownloadTracker. The
            // Hub client's progress is used solely for the total size, so this stands in for it as
            // the child of the caller's progress.
            let downloadProgress = Progress(totalUnitCount: 0)
            parentProgress.addChild(downloadProgress, withPendingUnitCount: progressCount)

            let blobsDirectory = HubCache.default.blobsDirectory(repo: repoId, kind: .model)
            let tracker = DownloadTracker(
                blobsDirectory: blobsDirectory,
                progress: downloadProgress,
                detailHandler: detailHandler
            )

            // Only the first of these callbacks does anything: it hands over the total size, which
            // in turn triggers the opening read.
            let progressHandler = { @Sendable (progress: Progress) in
                _ = Task { @MainActor in
                    await tracker.setTotalBytes(progress.totalUnitCount)
                }
            }

            // Polled rather than observed. File presentation reports coordinated writes, and the
            // downloader appends to its shards with plain writes that the coordination machinery
            // never hears about — notifications only arrive while some other process happens to be
            // watching the directory. FSEvents would see them, but exists only on macOS.
            let pollTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await tracker.poll()
                }
            }

            defer {
                pollTask.cancel()
                tracker.finish()
            }

            let hubClientOnline = HubClient(useOfflineMode: false)
            return try await hubClientOnline.downloadSnapshot(of: repoId, maxConcurrent: 1, progressHandler: progressHandler)
        }
    }

    func install(parentProgress: Progress, progressCount: Int64, detailHandler: (@MainActor (String?) -> Void)? = nil) async throws {
        defer {
            updateStatus()
        }

        let loader = EmextalTokenizerLoader()
        let snapshotPath = try await Self.installModel(id: variant.repoId, parentProgress: parentProgress, progressCount: progressCount, detailHandler: detailHandler)
        // Reading a multi-gigabyte model off disk is slow enough to look like another stall, so the
        // detail line has to say what is happening now that the download is behind us.
        detailHandler?("Loading into memory…")
        modelContainer = try await loadModelContainer(from: snapshotPath, using: loader)
        detailHandler?(nil)
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
            variant.recommended ? "START HERE" : nil
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
