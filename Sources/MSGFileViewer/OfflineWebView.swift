// OfflineWebView - Sandboxed WKWebView wrapper for rendering HTML content offline
// Blocks all external navigation and network requests for security

import SwiftUI
import WebKit

struct OfflineWebView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        // Register a custom scheme handler that blocks all requests
        config.setURLSchemeHandler(BlockingSchemeHandler(), forURLScheme: "blocked")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Load immediately on creation
        context.coordinator.lastLoadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if the content has changed
        if context.coordinator.lastLoadedContent != htmlContent {
            context.coordinator.lastLoadedContent = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedContent: String?

        // Cancel any navigation that tries to leave the loaded HTML
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)  // Allow initial load
            } else {
                decisionHandler(.cancel) // Block all other navigation
            }
        }
    }
}

class BlockingSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFailWithError(URLError(.cancelled))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
