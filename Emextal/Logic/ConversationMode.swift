import Foundation
import MLXLMCommon

enum ConversationMode: Equatable {
    case startup
    case booting
    case warmup
    case loading(progress: CGFloat, status: [LoadingProgressDisplay.Status])
    case loaded
    case waiting(session: ChatSession)
    case listening(state: MicState, session: ChatSession)
    case transcribing(session: ChatSession)
    case transcribingDone(session: ChatSession)
    case processingPrompt(session: ChatSession, task: Task<Void, any Error>)
    case replying(session: ChatSession, task: Task<Void, any Error>)
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

    var shouldIgnoreMic: Bool {
        switch self {
        case .listening, .waiting:
            false
        case .booting, .error, .loaded, .loading, .processingPrompt, .replying, .shutdown, .startup, .transcribing, .transcribingDone, .warmup:
            true
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
        if case let .listening(state, _) = self, state == .quiet {
            true
        } else {
            false
        }
    }

    var session: ChatSession? {
        switch self {
        case .booting,
             .error,
             .loaded,
             .loading,
             .shutdown,
             .startup,
             .warmup:
            nil

        case let .listening(_, session),
             let .processingPrompt(session, _),
             let .replying(session, _),
             let .transcribing(session),
             let .transcribingDone(session),
             let .waiting(session):
            session
        }
    }

    var task: Task<Void, any Error>? {
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

        case let .processingPrompt(_, task),
             let .replying(_, task):
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
        case let (.listening(stateL, _), .listening(stateR, _)):
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
