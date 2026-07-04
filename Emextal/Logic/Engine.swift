import Foundation

/// What powers a `Conversation`: a language model that generates replies, or nothing at all —
/// transcription mode, where each utterance is appended to the log verbatim. Future conversation
/// flavours slot in as new cases.
enum Engine {
    case llm(model: Model)
    case transcription

    var isTranscription: Bool {
        switch self {
        case .llm: false
        case .transcription: true
        }
    }

    var displayName: String {
        switch self {
        case let .llm(model): model.variant.displayName
        case .transcription: "Transcription"
        }
    }

    var supportsImageInputs: Bool {
        switch self {
        case let .llm(model): model.variant.architecture.supportsImageInputs
        case .transcription: false
        }
    }

    var historyPath: URL {
        switch self {
        case let .llm(model): model.modelHistoryPath
        case .transcription: Model.appDocumentsUrl.appendingPathComponent("transcription-history.json")
        }
    }

    func makeBrain() -> Brain? {
        switch self {
        case let .llm(model): Brain(model: model)
        case .transcription: nil
        }
    }
}
