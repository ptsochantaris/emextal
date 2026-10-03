import Foundation

enum ConversationMode: Equatable {
    case startup
    case booting
    case warmup
    case loading(progress: CGFloat, status: [LoadingProgressDisplay.Status])
    case loaded
    case waiting
    case listening(state: MicState)
    case transcribing
    case transcribingDone
    case processingPrompt(task: Task<Void, Never>)
    case replying(task: Task<Void, Never>)
    case shutdown
    case error(any Error)

    var canRespond: Bool {
        switch self {
        case .transcribingDone, .waiting:
            true
        case .booting, .error, .listening, .loaded, .loading, .processingPrompt, .replying, .shutdown, .startup, .transcribing, .warmup:
            false
        }
    }

    /// True in the states that represent a running conversation. Transcription mode runs without a
    /// chat session, so this, not the session's presence, is the "are we live" check.
    var isActive: Bool {
        switch self {
        case .listening, .processingPrompt, .replying, .transcribing, .transcribingDone, .waiting:
            true
        case .booting, .error, .loaded, .loading, .shutdown, .startup, .warmup:
            false
        }
    }

    var isLoaded: Bool {
        if case .loaded = self {
            true
        } else {
            false
        }
    }

    var isWaiting: Bool {
        if case .waiting = self {
            true
        } else {
            false
        }
    }

    var isReplying: Bool {
        if case .replying = self {
            true
        } else {
            false
        }
    }

    var isQuietListening: Bool {
        if case let .listening(state) = self, state == .quiet {
            true
        } else {
            false
        }
    }

    var task: Task<Void, Never>? {
        switch self {
        case .booting,
             .error,
             .listening,
             .loaded,
             .loading,
             .shutdown,
             .startup,
             .transcribing,
             .transcribingDone,
             .waiting,
             .warmup:
            nil

        case let .processingPrompt(task),
             let .replying(task):
            task
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.booting, .booting),
             (.error, .error),
             (.processingPrompt, .processingPrompt),
             (.replying, .replying),
             (.shutdown, .shutdown),
             (.startup, .startup),
             (.transcribing, .transcribing),
             (.transcribingDone, .transcribingDone),
             (.waiting, .waiting),
             (.warmup, .warmup):
            true
        case let (.loading(p1, s1), .loading(p2, s2)):
            p1 == p2 && s1 == s2
        case let (.listening(stateL), .listening(stateR)):
            stateL == stateR
        case (.loaded, .loaded):
            true
        default:
            false
        }
    }

    var nominal: Bool {
        switch self {
        case .listening, .replying, .waiting:
            true
        case .booting, .error, .loaded, .loading, .processingPrompt, .shutdown, .startup, .transcribing, .transcribingDone, .warmup:
            false
        }
    }

    var showGenie: Bool {
        switch self {
        case .processingPrompt, .replying, .transcribing, .transcribingDone:
            true
        case .booting, .error, .listening, .loaded, .loading, .shutdown, .startup, .waiting, .warmup:
            false
        }
    }

    var showAlwaysOn: Bool {
        switch self {
        case .booting, .error, .loaded, .loading, .processingPrompt, .replying, .shutdown, .startup, .transcribing, .transcribingDone, .warmup:
            false
        case .listening, .waiting:
            true
        }
    }

    var pushButtonActive: Bool {
        switch self {
        case .listening, .replying, .waiting:
            true
        case .booting, .error, .loaded, .loading, .processingPrompt, .shutdown, .startup, .transcribing, .transcribingDone, .warmup:
            false
        }
    }
}
