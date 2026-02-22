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

        // Inject URLObserver.js for SPA navigation tracking
        if let jsURL = Bundle.main.url(forResource: "URLObserver", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Inject AuxClickNewTab.js for three-finger tap / middle-click new tab
        if let jsURL = Bundle.main.url(forResource: "AuxClickNewTab", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Inject LinkHints.js
        if let jsURL = Bundle.main.url(forResource: "LinkHints", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Inject ElementPicker.js
        if let jsURL = Bundle.main.url(forResource: "ElementPicker", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Inject QueueInterceptor.js at document start (capture phase needs early registration)
        if let jsURL = Bundle.main.url(forResource: "QueueInterceptor", withExtension: "js"),
           let jsSource = try? String(contentsOf: jsURL) {
            let script = WKUserScript(source: jsSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            config.userContentController.addUserScript(script)
        }

        // Inject TheaterMode.js at document start (before YouTube reads prefs)
        updateTheaterModeScript(on: config.userContentController)

        // PiP support
        config.preferences.isElementFullscreenEnabled = true

        // Enable password/passkey autofill
        if #available(macOS 14.0, *) {
            config.preferences.isTextInteractionEnabled = true
        }

        return config
    }()

    /// Rebuilds the theater-mode document-start script with the current setting.
    /// Sets the 'wide=1' cookie via WKHTTPCookieStore so it's present before page load.
    func ensureTheaterCookie(completion: @escaping () -> Void) {
        guard Settings.theaterMode else {
            completion()
            return
        }
        let cookieStore = sharedConfiguration.websiteDataStore.httpCookieStore
        let properties: [HTTPCookiePropertyKey: Any] = [
            .name: "wide",
            .value: "1",
            .domain: ".youtube.com",
            .path: "/",
            .expires: Date(timeIntervalSinceNow: 365 * 24 * 60 * 60),
        ]
        if let cookie = HTTPCookie(properties: properties) {
            cookieStore.setCookie(cookie) {
                completion()
            }
        } else {
            completion()
        }
    }

    /// Re-sets YouTube's session-only 'wide' cookie with an expiration so it persists.
    func updateTheaterModeScript(on controller: WKUserContentController? = nil) {
        let uc = controller ?? sharedConfiguration.userContentController
        let enabled = Settings.theaterMode ? "true" : "false"
        if let url = Bundle.main.url(forResource: "TheaterMode", withExtension: "js"),
           var source = try? String(contentsOf: url) {
            source = source.replacingOccurrences(of: "%THEATER_ENABLED%", with: enabled)
            // Remove existing theater scripts and re-add all scripts
            // (WKUserContentController doesn't support removing individual scripts,
            //  so we track and re-add)
            let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            // We can't selectively remove, but adding another is fine — last write to localStorage wins
            uc.addUserScript(script)
        }
    }

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

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    private func isVideoURL(_ url: URL) -> Bool {
        let path = url.absoluteString
        return path.contains("/watch") || path.contains("/shorts/") || path.contains("/live/")
    }

    private func suspendInactiveTabs() {
        guard currentMemoryMB() > 750 else { return }

        let timeout = TimeInterval(Settings.suspensionTimeoutMinutes * 60)
        let now = Date()

        // Collect eligible tabs, preferring video URLs over homepage
        var candidates: [(index: Int, tab: Tab)] = []
        for (i, tab) in tabs.enumerated() {
            guard i != selectedIndex,
                  !tab.isSuspended,
                  tab.webView != nil,
                  !tab.isPlayingMedia,
                  now.timeIntervalSince(tab.lastActiveTime) > timeout else { continue }
            candidates.append((i, tab))
        }

        // Sort so video URLs come first (suspended before homepage tabs)
        candidates.sort { isVideoURL($0.tab.url) && !isVideoURL($1.tab.url) }

        for candidate in candidates {
            candidate.tab.suspend()
            delegate?.tabManager(self, didUpdateTab: candidate.tab, at: candidate.index)
        }
    }
}
