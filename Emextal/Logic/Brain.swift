import Foundation
import MLXLMCommon

/// Owns the language-model inference behind a reply: building the chat session from the installed
/// model, and turning a prompt into a stream of display- and speech-ready tokens.
///
/// `Conversation` coordinates with it the same way it does with `Mic` and `Speaker` — it feeds the
/// input and consumes the resulting async stream, while the raw decoding and token parsing stay in
/// here rather than being woven into the conversation hub.
final class Brain {
    private let model: Model

    init(model: Model) {
        self.model = model
    }

    deinit {
        log("\(Self.self) deinit")
    }

    /// Downloads (if needed) and loads the language model into memory, reporting into the supplied
    /// parent progress. Must complete before `makeSession` can produce a session.
    func install(parentProgress: Progress, progressCount: Int64) async throws {
        try await model.install(parentProgress: parentProgress, progressCount: progressCount)
    }

    /// Builds a fresh chat session seeded with prior history. Returns `nil` if the model isn't
    /// installed yet.
    func makeSession(history: [Chat.Message]) -> ChatSession? {
        guard let modelContainer = model.modelContainer else {
            log("Warning: The model is not installed.")
            return nil
        }
        return ChatSession(
            modelContainer,
            history: history,
            generateParameters: model.params.mlx,
            additionalContext: model.additionalContext
        )
    }

    /// Streams a reply to `text`, yielding parsed text/tag tokens. Encapsulates the raw token stream
    /// plus the thinking-tag and Harmony post-processing (`TokenIngestion` → `TextProcessor`).
    ///
    /// Cancelling the task that consumes the returned stream tears the generation down promptly: the
    /// internal token/processor tasks are unstructured, so they don't get cancelled on their own;
    /// the stream's `onTermination` (which fires on normal completion *and* on consumer cancellation)
    /// forwards the cancellation so reset/barge-in doesn't block until the full reply generates.
    func reply(in session: ChatSession, to text: String, images: [UserInput.Image]) -> AsyncStream<TokenIngestion.Output> {
        let tokenIngestion = TokenIngestion(initialBuffer: model.variant.injectThinkingTag ? "<think>" : "")
        let textProcessor = TextProcessor(harmony: model.variant.usesHarmony ? .idle : .notApplicable)

        let tokenTask = Task {
            defer {
                tokenIngestion.done()
            }
            for try await item in session.streamResponse(to: text, images: images, videos: []) {
                tokenIngestion.ingest(text: item)
            }
        }

        let processorTask = Task {
            defer {
                textProcessor.done()
            }
            for await item in tokenIngestion.output {
                textProcessor.ingest(token: item)
            }
        }

        let (stream, continuation) = AsyncStream.makeStream(of: TokenIngestion.Output.self)

        let pump = Task {
            for await token in textProcessor.output {
                continuation.yield(token)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            tokenTask.cancel()
            processorTask.cancel()
            pump.cancel()
        }

        return stream
    }
}
