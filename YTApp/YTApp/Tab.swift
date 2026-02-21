import Cocoa
import WebKit

class Tab {
    let id: UUID
    var url: URL
    var title: String
    var webView: WKWebView?
    var isSuspended: Bool
    var lastActiveTime: Date
    var isPlayingMedia: Bool = false

    init(url: URL, title: String = "New Tab") {
        self.id = UUID()
        self.url = url
        self.title = title
        self.isSuspended = false
        self.lastActiveTime = Date()
        self.webView = nil
    }

    func createWebView(configuration: WKWebViewConfiguration, navigationDelegate: WKNavigationDelegate?, uiDelegate: WKUIDelegate?) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.navigationDelegate = navigationDelegate
        wv.uiDelegate = uiDelegate
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.allowsLinkPreview = true
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        self.webView = wv
        self.isSuspended = false
        self.lastActiveTime = Date()
        return wv
    }

    func suspend() {
        guard !isPlayingMedia else { return }
        if let wv = webView {
            url = wv.url ?? url
            title = wv.title ?? title
        }
        webView = nil
        isSuspended = true
    }

    func markActive() {
        lastActiveTime = Date()
    }
}
