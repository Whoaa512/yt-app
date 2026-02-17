import Cocoa
import WebKit

protocol TabManagerDelegate: AnyObject {
    func tabManager(_ manager: TabManager, didAddTab tab: Tab, at index: Int)
    func tabManager(_ manager: TabManager, didRemoveTabAt index: Int)
    func tabManager(_ manager: TabManager, didSelectTab tab: Tab, at index: Int)
    func tabManager(_ manager: TabManager, didUpdateTab tab: Tab, at index: Int)
    func tabManagerNavigationDelegate(_ manager: TabManager) -> WKNavigationDelegate?
    func tabManagerUIDelegate(_ manager: TabManager) -> WKUIDelegate?
}

class TabManager {
    weak var delegate: TabManagerDelegate?
    private(set) var tabs: [Tab] = []
    private(set) var selectedIndex: Int = -1
    private var suspensionTimer: Timer?

    var activeTab: Tab? {
        guard selectedIndex >= 0 && selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    lazy var sharedConfiguration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Inject MediaBridge.js
        if let jsURL = Bundle.main.url(forResource: "MediaBridge", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // PiP support
        config.preferences.isElementFullscreenEnabled = true

        // Enable password/passkey autofill
        if #available(macOS 14.0, *) {
            config.preferences.isTextInteractionEnabled = true
        }

        return config
    }()

    func startSuspensionTimer() {
        suspensionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.suspendInactiveTabs()
        }
    }

    @discardableResult
    func addTab(url: URL = URL(string: "https://www.youtube.com")!) -> Tab {
        let tab = Tab(url: url)
        tabs.append(tab)
        let index = tabs.count - 1
        delegate?.tabManager(self, didAddTab: tab, at: index)
        selectTab(at: index)
        return tab
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let tab = tabs[index]
        tab.webView = nil
        tabs.remove(at: index)
        delegate?.tabManager(self, didRemoveTabAt: index)

        if tabs.isEmpty {
            addTab()
        } else {
            let newIndex = min(index, tabs.count - 1)
            selectTab(at: newIndex)
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        selectedIndex = index
        let tab = tabs[index]
        tab.markActive()

        if tab.isSuspended || tab.webView == nil {
            ensureWebView(for: tab)
            tab.webView?.load(URLRequest(url: tab.url))
        }

        delegate?.tabManager(self, didSelectTab: tab, at: index)
    }

    func moveTab(from: Int, to: Int) {
        guard from != to, from >= 0, from < tabs.count, to >= 0, to < tabs.count else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        if selectedIndex == from {
            selectedIndex = to
        } else if from < selectedIndex && to >= selectedIndex {
            selectedIndex -= 1
        } else if from > selectedIndex && to <= selectedIndex {
            selectedIndex += 1
        }
    }

    func ensureWebView(for tab: Tab) {
        guard tab.webView == nil else { return }
        let navDelegate = delegate?.tabManagerNavigationDelegate(self)
        let uiDelegate = delegate?.tabManagerUIDelegate(self)
        _ = tab.createWebView(configuration: sharedConfiguration, navigationDelegate: navDelegate, uiDelegate: uiDelegate)
        // Add mediaBridge message handler
        tab.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mediaBridge")
        // Message handler is added by the WebViewController
    }

    func updateTab(_ tab: Tab) {
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            delegate?.tabManager(self, didUpdateTab: tab, at: index)
        }
    }

    private func suspendInactiveTabs() {
        let timeout = TimeInterval(Settings.suspensionTimeoutMinutes * 60)
        let now = Date()
        for (i, tab) in tabs.enumerated() {
            guard i != selectedIndex,
                  !tab.isSuspended,
                  tab.webView != nil,
                  !tab.isPlayingMedia,
                  now.timeIntervalSince(tab.lastActiveTime) > timeout else { continue }
            tab.suspend()
            delegate?.tabManager(self, didUpdateTab: tab, at: i)
        }
    }
}
