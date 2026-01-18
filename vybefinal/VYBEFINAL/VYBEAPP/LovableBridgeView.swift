import SwiftUI
import WebKit

final class VybeWebViewStore: ObservableObject {
    weak var webView: WKWebView?

    func sendToWeb(_ payload: [String: Any]) {
        guard let webView else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        let js = "window.__onNativeEvent && window.__onNativeEvent(\(json));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

struct VybeLovableWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var store: VybeWebViewStore
    let onMessage: (Any) -> Void
    let onLoaded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage, onLoaded: onLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "native")
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        store.webView = webView

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onMessage: (Any) -> Void
        let onLoaded: () -> Void

        init(onMessage: @escaping (Any) -> Void, onLoaded: @escaping () -> Void) {
            self.onMessage = onMessage
            self.onLoaded = onLoaded
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "native" else { return }
            onMessage(message.body)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
        }
    }
}
