import Foundation
import Ink
import MLXLMCommon
import SwiftUI
import WebKit

extension Chat.Message: @unchecked @retroactive Sendable {}

final actor MessageLog {
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        LowPriorityExecutor.sharedExecutor.asUnownedSerialExecutor()
    }

    private enum Change {
        case append(text: String, image: NSImage?),
             commit,
             save(to: URL, @Sendable (Error?) -> Void),
             isEmpty(@Sendable (Bool) -> Void),
             setHistory(newHistory: [Turn]),
             reset,
             allText(@Sendable (String) -> Void)
    }

    private weak var webView: WKWebView?

    var asSessionHistory: [Chat.Message] {
        [] // TODO:
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        Task { [weak self] in
            log("Messagelog queue started")
            guard let stream = self?.changeStream else { return }
            for await change in stream {
                await self?.process(change: change)
            }
            log("Messagelog queue done")
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

    nonisolated var allText: String {
        get async {
            await withCheckedContinuation { [weak self] continuation in
                if let self {
                    changeContinuation.yield(.allText {
                        continuation.resume(returning: $0)
                    })
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    nonisolated func append(text: String, image: NSImage?) {
        changeContinuation.yield(.append(text: text, image: image))
    }

    nonisolated func reset() {
        changeContinuation.yield(.reset)
    }

    nonisolated func commitNewText() {
        changeContinuation.yield(.commit)
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

    nonisolated func setHistory(from _: URL?) {
        // TODO: enable after asSessionHistory is implemented
        /* let turns = if let url, let data = try? Data(contentsOf: url), let history = try? JSONDecoder().decode([Turn].self, from: data) {
             history
         } else {
             [Turn]()
         }
         changeContinuation.yield(.setHistory(newHistory: turns))
          */
    }

    nonisolated func shutdown() {
        changeContinuation.finish()
    }

    init() {
        (changeStream, changeContinuation) = AsyncStream.makeStream(of: Change.self, bufferingPolicy: .unbounded)
    }

    deinit {
        log("\(Self.self) deinit")
    }

    private struct Turn: Codable {
        let id: UUID
        let text: String

        init(text: String) {
            id = UUID()
            self.text = text
        }
    }

    private var displayedHistoryCount = 0
    private var displayedBuildingCount = 0
    private var history = [Turn]()
    private var newText = ""

    private let changeStream: AsyncStream<Change>
    private let changeContinuation: AsyncStream<Change>.Continuation
    private let parser = MarkdownParser()

    private func markdownToHtml(_ markdown: String) -> String {
        let source = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return if source.isEmpty {
            ""
        } else {
            parser.html(from: source)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
    }

    private func process(change: Change) async {
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

        case let .allText(callback):
            let text = history.map(\.text).joined()
            callback(text + newText)
            return

        case let .isEmpty(callback):
            let isEmpty = newText.isEmpty && history.isEmpty
            callback(isEmpty)
            return

        case let .append(text, image):
            if let image,
               let data = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: data),
               let imgData = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(floatLiteral: 0.8)]) {
                let filename = UUID().uuidString + "-attachment.jpg"
                let path = WebView.temporaryDirectory.appendingPathComponent(filename)
                do {
                    try imgData.write(to: path)
                    newText += text + "![Image](\(path.absoluteString))\n"
                } catch {
                    log("Warning: Error saving image: \(error)")
                    newText += text
                }
            } else {
                newText += text
            }

        case .reset:
            history.removeAll()
            newText = ""

        case .commit:
            history.append(Turn(text: newText))
            newText = ""

        case let .setHistory(newHistory):
            history = newHistory
            newText = ""
        }

        guard let webView else {
            log("Update \(change) without active webview!")
            return
        }

        var latestHistoryChunk: (String, String)?
        var historyReset = false
        let newHistoryCount = history.count
        if displayedHistoryCount != newHistoryCount {
            if let latestChunk = history.last {
                latestHistoryChunk = (latestChunk.id.uuidString, markdownToHtml(latestChunk.text))
            } else {
                historyReset = true
            }
            displayedHistoryCount = newHistoryCount
        }

        var newTextChunk: String?
        let newBuildingCount = newText.count
        if displayedBuildingCount != newBuildingCount {
            newTextChunk = markdownToHtml(newText)
            displayedBuildingCount = newBuildingCount
        }

        await Task { @MainActor [weak webView] in
            guard let webView else { return }
            while webView.isLoading {
                await Task.yield()
                if Task.isCancelled {
                    return
                }
            }

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
