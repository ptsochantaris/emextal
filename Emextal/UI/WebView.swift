import Foundation
import Ink
import SwiftUI
import UniformTypeIdentifiers
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
    nonisolated static let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("emextal-webview", conformingTo: .directory)

    final class Coordinator {
        let webView: WKWebView

        deinit {
            log("\(Self.self) deinit")
        }

        init(viewModel: ViewModel) {
            log("Coordinator init")

            // Move to RW directory
            let itemsToCopy = [Bundle.main.url(forResource: "log", withExtension: "html")!,
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
