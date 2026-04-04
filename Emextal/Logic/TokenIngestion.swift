import Foundation

final class TokenIngestion {
    enum Output {
        case text(String), tag(String)
    }

    let output: AsyncStream<Output>

    @LowPriorityActor
    private let continuation: AsyncStream<Output>.Continuation

    @LowPriorityActor
    private var charBuffer = ""

    init(initialBuffer: String) {
        charBuffer = initialBuffer
        charBuffer.reserveCapacity(1024)
        (output, continuation) = AsyncStream.makeStream(of: Output.self)
    }

    private enum TagState {
        case nominal, tag(String)
    }

    @LowPriorityActor
    private var tagState = TagState.nominal

    func ingest(text: String) {
        Task { @LowPriorityActor in
            for char in text {
                switch tagState {
                case .nominal:
                    switch char {
                    case "<":
                        if !charBuffer.isEmpty {
                            continuation.yield(.text(charBuffer))
                            charBuffer.removeAll(keepingCapacity: true)
                        }
                        tagState = .tag("<")

                    case ",", ":", "!", "?", ".", ")", "\n":
                        charBuffer.append(char)
                        continuation.yield(.text(charBuffer))
                        charBuffer.removeAll(keepingCapacity: true)

                    default:
                        charBuffer.append(char)
                    }

                case let .tag(string):
                    switch char {
                    case "<":
                        // abort tag
                        charBuffer.append(string)
                        tagState = .nominal

                    case ">":
                        // signal tag
                        continuation.yield(.tag(string + ">"))
                        tagState = .nominal

                    default:
                        tagState = .tag(string + [char])
                    }
                }
            }
        }
    }

    func done() {
        Task { @LowPriorityActor in
            if !charBuffer.isEmpty {
                continuation.yield(.text(charBuffer))
            }
            continuation.finish()
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }
}
