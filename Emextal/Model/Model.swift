import Foundation
import Hub
import PopTimer

@MainActor
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
        let fm = FileManager.default

        guard
            let repoDestination = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "models/\(variant.repoId)"),
            fm.fileExists(atPath: repoDestination.path)
        else {
            return false
        }

        guard
            let enumerator = fm.enumerator(
                at: repoDestination,
                includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return false
        }

        var fileUrls = [URL]()

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            if resourceValues.isRegularFile == true, resourceValues.isHidden != true {
                fileUrls.append(fileURL)
            }
        }

        if fileUrls.isEmpty {
            return false
        }

        let repoMetadataDestination = repoDestination.appending(path: ".cache/huggingface/download")

        for fileUrl in fileUrls {
            let metadataPath = URL(
                fileURLWithPath: fileUrl.path.replacingOccurrences(
                    of: repoDestination.path,
                    with: repoMetadataDestination.path
                ) + ".metadata"
            )

            let localMetadata = try HubApi.shared.readDownloadMetadata(metadataPath: metadataPath)

            guard localMetadata != nil else {
                return false
            }
        }

        return true
    }

    func delete() {
        let fm = FileManager.default

        if let repoDestination = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "models/\(variant.repoId)"),
           fm.fileExists(atPath: repoDestination.path) {
            try? fm.removeItem(at: repoDestination)
        }

        if let repoDestination = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: "huggingface/hub/models--\(variant.repoId.replacingOccurrences(of: "/", with: "--"))"),
           fm.fileExists(atPath: repoDestination.path) {
            try? fm.removeItem(at: repoDestination)
        }

        updateStatus()
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

        updateStatus()

        saveTimer = PopTimer(timeInterval: 0.1) { [weak self] in
            self?.save()
        }
    }

    var additionalContext: [String: any Sendable] {
        variant.additionalContext
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
}
