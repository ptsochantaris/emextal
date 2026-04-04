import Foundation

nonisolated enum Harmony {
    case notApplicable, idle, channel, message, assistant, system, developer, user, tool, start
}

final class TextProcessor {
    let output: AsyncStream<TokenIngestion.Output>

    @LowPriorityActor
    private let continuation: AsyncStream<TokenIngestion.Output>.Continuation

    @LowPriorityActor
    private var harmony: Harmony

    @LowPriorityActor
    private var buffer = ""

    @LowPriorityActor
    private var inThink = false

    init(harmony: Harmony) {
        self.harmony = harmony
        (output, continuation) = AsyncStream.makeStream(of: TokenIngestion.Output.self)
    }

    func ingest(token: TokenIngestion.Output) {
        Task { @LowPriorityActor in
            switch token {
            case let .text(text):
                switch harmony {
                case .idle, .message, .notApplicable:
                    continuation.yield(token)

                case .assistant, .channel, .developer, .start, .system, .tool, .user:
                    buffer.append(text)
                }

            case let .tag(tag):
                switch harmony {
                case .notApplicable:
                    continuation.yield(token)

                default:
                    if tag == "<|channel|>" {
                        harmony = .channel
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|start|>" {
                        harmony = .start
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|message|>" {
                        harmony = .message
                        inThink = buffer == "analysis" || buffer == "commentary"
                        if inThink {
                            continuation.yield(.text("<think>"))
                        }
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|assistant|>" {
                        harmony = .assistant
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|developer|>" {
                        harmony = .developer
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|tool|>" {
                        harmony = .tool
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|system|>" {
                        harmony = .system
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|user|>" {
                        harmony = .user
                        buffer.removeAll(keepingCapacity: true)
                    } else if tag == "<|end|>" {
                        harmony = .idle
                        if inThink {
                            continuation.yield(.text("</think>"))
                        }
                    }
                }
            }
        }
    }

    func done() {
        Task { @LowPriorityActor in
            if inThink {
                continuation.yield(.text("</think>"))
            }
            continuation.finish()
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
