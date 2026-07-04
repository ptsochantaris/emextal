import Foundation
import Ink
import SwiftUI
import UniformTypeIdentifiers
import WebKit

#if canImport(AppKit)
    struct WebView: NSViewRepresentable {
        let viewModel: Conversation
        func makeNSView(context: Context) -> WKWebView {
            context.coordinator.webView
        }

        func updateNSView(_: WKWebView, context _: Context) {}
        func makeCoordinator() -> Coordinator {
            Coordinator(viewModel: viewModel)
        }
    }
#else
    struct WebView: UIViewRepresentable {
        let viewModel: Conversation
        func makeUIView(context: Context) -> WKWebView {
            context.coordinator.webView
        }

        func updateUIView(_: WKWebView, context _: Context) {}
        func makeCoordinator() -> Coordinator {
            Coordinator(viewModel: viewModel)
        }
    }
#endif

extension WebView {
    nonisolated static let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("emextal-webview", conformingTo: .directory)

    /// The user content controller retains its message handlers, and the coordinator retains the
    /// web view (whose configuration owns that controller), so registering the coordinator
    /// directly would create a retain cycle. This forwarder breaks it.
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        private weak var delegate: (any WKScriptMessageHandler)?

        init(delegate: any WKScriptMessageHandler) {
            self.delegate = delegate
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let webView: WKWebView
        private let viewModel: Conversation

        deinit {
            log("\(Self.self) deinit")
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "deleteTurn", let id = message.body as? String {
                viewModel.deleteTurn(id: id)
            }
        }

        init(viewModel: Conversation) {
            log("Coordinator init")

            self.viewModel = viewModel

            // Move to RW directory
            let itemsToCopy = [Bundle.main.url(forResource: "log", withExtension: "html")!,
                               Bundle.main.url(forResource: "log", withExtension: "js")!,
                               Bundle.main.url(forResource: "highlight", withExtension: "css")!,
                               Bundle.main.url(forResource: "highlight", withExtension: "js")!,
                               Bundle.main.url(forResource: "style", withExtension: "css")!]
            let fm = FileManager.default
            if !fm.fileExists(atPath: WebView.temporaryDirectory.path) {
                try! fm.createDirectory(at: WebView.temporaryDirectory, withIntermediateDirectories: true)
            }
            for item in itemsToCopy {
                let destination = WebView.temporaryDirectory.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    try! fm.removeItem(at: destination)
                }
                try! fm.copyItem(at: item, to: destination)
            }

            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true
            webView = WKWebView(frame: .zero, configuration: config)

            super.init()

            config.userContentController.add(WeakScriptMessageHandler(delegate: self), name: "deleteTurn")
            webView.loadFileURL(WebView.temporaryDirectory.appending(path: "log.html"), allowingReadAccessTo: WebView.temporaryDirectory)

            #if canImport(AppKit)
                webView.setValue(false, forKey: "drawsBackground")
                webView.enclosingScrollView?.horizontalScrollElasticity = .none
            #else
                webView.isOpaque = false
                webView.scrollView.alwaysBounceHorizontal = false
            #endif

            Task {
                await viewModel.setWebView(webView)
            }
        }
    }
}
