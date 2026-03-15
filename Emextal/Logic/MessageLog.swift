import Foundation
import Ink
import MLXLMCommon
import WebKit

final actor MessageLog {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        LowPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private enum Change {
        case prompt(text: String, image: NSImage?),
             appendResponse(text: String),
             commitTurn,
             save(to: URL, @Sendable (Error?) -> Void),
             isEmpty(@Sendable (Bool) -> Void),
             synchronize(@Sendable () -> Void),
             reset
    }

    private weak var webView: WKWebView?

    var asSessionHistory: [Chat.Message] {
        get async {
            await withCheckedContinuation { continuation in
                changeContinuation.yield(.synchronize {
                    continuation.resume()
                })
            }

            var result = [Chat.Message]()
            result.reserveCapacity(history.count * 2)
            for item in history {
                result.append(
                    Chat.Message(role: .user, content: item.prompt, images: [item.image].compactMap(\.self).map { .url($0) }, videos: [])
                )
                result.append(
                    Chat.Message(role: .assistant, content: item.text, images: [], videos: [])
                )
            }
            return result
        }
    }

    func setWebView(_ webView: WKWebView) async {
        self.webView = webView

        do {
            await Task { @MainActor in
                while webView.isLoading {
                    await Task.yield()
                    if Task.isCancelled {
                        return
                    }
                }
            }.value

            for turn in history {
                let js = "addHistory('\(turn.id)', '\(turn.renderHtml(parser: parser))');"
                try await Task { @MainActor in
                    _ = try await webView.evaluateJavaScript(js)
                }.value
            }
        } catch {
            log("Error evaluating JS: \(error)")
        }
    }

    nonisolated var isEmpty: Bool {
        get async {
            await withCheckedContinuation { [weak self] continuation in
                if let self {
                    changeContinuation.yield(.isEmpty {
                        continuation.resume(returning: $0)
                    })
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    nonisolated func prompt(text: String, image: NSImage?) {
        changeContinuation.yield(.prompt(text: text, image: image))
    }

    nonisolated func appendResponse(text: String) {
        changeContinuation.yield(.appendResponse(text: text))
    }

    nonisolated func reset() {
        changeContinuation.yield(.reset)
    }

    nonisolated func commitTurn() {
        changeContinuation.yield(.commitTurn)
    }

    nonisolated func save(to url: URL) async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            if let self {
                changeContinuation.yield(.save(to: url) { exception in
                    if let exception {
                        continuation.resume(throwing: exception)
                    } else {
                        continuation.resume()
                    }
                })
            } else {
                continuation.resume()
            }
        }
    }

    func loadHistory(from url: URL?) {
        history = if let url, let data = try? Data(contentsOf: url), let history = try? JSONDecoder().decode([Turn].self, from: data) {
            history
        } else {
            [Turn]()
        }
        displayedHistoryCount = history.count
    }

    nonisolated func shutdown() {
        changeContinuation.finish()
    }

    init() {
        (changeStream, changeContinuation) = AsyncStream.makeStream(of: Change.self, bufferingPolicy: .unbounded)

        Task { [weak self] in
            log("Messagelog queue started")
            guard let stream = self?.changeStream else { return }
            for await change in stream {
                await self?.process(change: change)
            }
            log("Messagelog queue done")
        }
    }

    deinit {
        log("\(Self.self) deinit")
    }

    private var displayedHistoryCount = 0
    private var displayedBuildingCount = 0
    private var history = [Turn]()
    private var newTurn: Turn?

    private let changeStream: AsyncStream<Change>
    private let changeContinuation: AsyncStream<Change>.Continuation
    private let parser = MarkdownParser()

    private func process(change: Change) async {
        log("Messagelog: \(change)")

        switch change {
        case let .save(url, callback):
            do {
                let encoder = JSONEncoder()
                try encoder.encode(history).write(to: url)
                callback(nil)
            } catch {
                callback(error)
            }
            return

        case let .isEmpty(callback):
            let isEmpty = newTurn == nil && history.isEmpty
            callback(isEmpty)
            return

        case let .prompt(text, image):
            newTurn = Turn(prompt: text, text: "", image: image)

        case let .appendResponse(text):
            newTurn?.text += text

        case .reset:
            history.removeAll()
            newTurn = nil

        case let .synchronize(callback):
            callback()
            return

        case .commitTurn:
            if let turn = newTurn {
                history.append(turn)
                newTurn = nil
            }
        }

        guard let webView else {
            return
        }

        var latestHistoryChunk: (String, String)?
        var historyReset = false
        let newHistoryCount = history.count
        if displayedHistoryCount != newHistoryCount {
            if let latestChunk = history.last {
                latestHistoryChunk = (latestChunk.id.uuidString, latestChunk.renderHtml(parser: parser))
            } else {
                historyReset = true
            }
            displayedHistoryCount = newHistoryCount
        }

        var newTextChunk: String?
        let newBuildingCount = newTurn?.count ?? 0
        if displayedBuildingCount != newBuildingCount {
            if let newTurn {
                newTextChunk = newTurn.renderHtml(parser: parser)
                displayedBuildingCount = newBuildingCount
            } else {
                newTextChunk = ""
                displayedBuildingCount = 0
            }
        }

        await Task { @MainActor [weak webView] in
            guard let webView else { return }
            do {
                if let latestHistoryChunk {
                    let js = "addHistory('\(latestHistoryChunk.0)', '\(latestHistoryChunk.1)');"
                    try await webView.evaluateJavaScript(js)

                } else if historyReset {
                    try await webView.evaluateJavaScript("reset();")
                }

                if let newTextChunk {
                    let js = "setNewText('\(newTextChunk)');"
                    try await webView.evaluateJavaScript(js)
                }
            } catch {
                log("Error evaluating JS: \(error)")
            }
        }.value
    }
}
