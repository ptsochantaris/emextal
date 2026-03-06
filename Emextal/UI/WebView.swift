import Foundation
import Ink
import SwiftUI
import WebKit

#if canImport(AppKit)
    struct WebView: NSViewRepresentable {
        let viewModel: ViewModel
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
        let viewModel: ViewModel
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
    final class Coordinator {
        let webView: WKWebView
        private let viewModel: ViewModel

        deinit {
            log("\(Self.self) deinit")
        }

        init(viewModel: ViewModel) {
            log("Coordinator init")

            let logView = Bundle.main.url(forResource: "log", withExtension: "html")!
            let config = WKWebViewConfiguration()
            config.suppressesIncrementalRendering = true
            webView = WKWebView(frame: .zero, configuration: config)
            webView.loadFileURL(logView, allowingReadAccessTo: logView.deletingLastPathComponent())

            #if canImport(AppKit)
                webView.setValue(false, forKey: "drawsBackground")
                webView.enclosingScrollView?.horizontalScrollElasticity = .none
            #else
                webView.isOpaque = false
                webView.scrollView.alwaysBounceHorizontal = false
            #endif

            self.viewModel = viewModel
            Task {
                await viewModel.messageLog.setWebView(webView)
            }
        }
    }
}
