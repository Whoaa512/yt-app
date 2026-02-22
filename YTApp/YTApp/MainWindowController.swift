import Cocoa
import WebKit

class MainWindowController: NSWindowController, NSWindowDelegate, TabManagerDelegate,
    AddressBarDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    HistoryViewControllerDelegate, ToolbarDelegate, QueueSidebarDelegate, QueueManagerDelegate,
    KeyboardShortcutDelegate, HelpModalDelegate, PluginManagerDelegate, PluginSettingsDelegate {

    let tabManager = TabManager()
    private let addressBar = AddressBarView(frame: .zero)
    private let toolbar = ToolbarView(frame: .zero)
    private let tabBar = NSSegmentedControl()
    private let webViewContainer = NSView()
    private var tabBarScrollView: NSScrollView!
    private let keyboardHandler = KeyboardShortcutHandler()
    private var helpModal: HelpModalViewController?

    // Custom tab bar
    private let tabStackView = NSStackView()
    private var jsConsoleController: JSConsoleWindowController?

    // Queue sidebar
    private var queueSidebar: QueueSidebarView?
    private var queueSidebarWidth: NSLayoutConstraint?
    private var isQueueVisible = false

    private let durationExtractorJS: String = {
        if let url = Bundle.main.url(forResource: "DurationExtractor", withExtension: "js"),
           let source = try? String(contentsOf: url) {
            return source
        }
        return ""
    }()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "YTApp"
        window.minSize = NSSize(width: 600, height: 400)
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        // Need a content view controller for sheet presentation
        let contentVC = NSViewController()
        contentVC.view = window.contentView!
        window.contentViewController = contentVC

        restoreWindowState()
        setupLayout()
        setupMenus()

        tabManager.delegate = self
        tabManager.sharedConfiguration.userContentController.add(self, name: "mediaBridge")
        tabManager.sharedConfiguration.userContentController.add(self, name: "urlChanged")
        tabManager.sharedConfiguration.userContentController.add(self, name: "theaterChanged")
        tabManager.sharedConfiguration.userContentController.add(self, name: "consoleLog")
        tabManager.sharedConfiguration.userContentController.add(self, name: "queueBridge")
        tabManager.sharedConfiguration.userContentController.add(self, name: "newTab")
        tabManager.sharedConfiguration.userContentController.add(self, name: "elementPicked")
        tabManager.sharedConfiguration.userContentController.add(self, name: "pluginBridge")
        QueueManager.shared.delegate = self
        keyboardHandler.delegate = self
        keyboardHandler.start()

        // Plugin system
        PluginManager.shared.delegate = self
        PluginManager.shared.ensurePluginDirectories()
        PluginManager.shared.discoverAndLoad()
        tabManager.pluginManager = PluginManager.shared
        PluginManager.shared.startWatching()
        toolbar.updatePlaybackRate(Settings.defaultPlaybackRate)

        // Ensure theater cookie is set before any tabs load
        tabManager.ensureTheaterCookie {
            self.restoreTabs()
        }
        tabManager.startSuspensionTimer()

        MediaKeyHandler.shared.setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        // Tab bar
        tabBarScrollView = NSScrollView()
        tabBarScrollView.hasHorizontalScroller = false
        tabBarScrollView.hasVerticalScroller = false
        tabBarScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabStackView.orientation = .horizontal
        tabStackView.spacing = 1
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabBarScrollView.documentView = tabStackView

        let newTabButton = NSButton()
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")
        newTabButton.target = self
        newTabButton.action = #selector(newTab)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.setContentHuggingPriority(.required, for: .horizontal)

        let tabBarContainer = NSView()
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.addSubview(tabBarScrollView)
        tabBarContainer.addSubview(newTabButton)

        NSLayoutConstraint.activate([
            tabBarScrollView.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor),
            tabBarScrollView.topAnchor.constraint(equalTo: tabBarContainer.topAnchor),
            tabBarScrollView.bottomAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
            tabBarScrollView.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -4),

            newTabButton.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor, constant: -4),
            newTabButton.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),
        ])

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        addressBar.delegate = self

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.delegate = self

        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.wantsLayer = true
        webViewContainer.layer?.backgroundColor = NSColor.black.cgColor

        // Queue sidebar
        let sidebar = QueueSidebarView(frame: .zero)
        sidebar.delegate = self
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        self.queueSidebar = sidebar

        // Body container (webview + optional queue sidebar)
        let bodyContainer = NSView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(webViewContainer)
        bodyContainer.addSubview(sidebar)

        contentView.addSubview(tabBarContainer)
        contentView.addSubview(addressBar)
        contentView.addSubview(toolbar)
        contentView.addSubview(bodyContainer)

        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 0)
        self.queueSidebarWidth = sidebarWidth

        NSLayoutConstraint.activate([
            tabBarContainer.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            tabBarContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBarContainer.heightAnchor.constraint(equalToConstant: 30),

            addressBar.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
            addressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            addressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            addressBar.heightAnchor.constraint(equalToConstant: 36),

            toolbar.topAnchor.constraint(equalTo: addressBar.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 30),

            bodyContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            webViewContainer.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            sidebar.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            sidebar.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            sidebarWidth,

            webViewContainer.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
        ])
    }

    // MARK: - Menu / Keyboard Shortcuts

    func setupMenus() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About YTApp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit YTApp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let focusItem = NSMenuItem(title: "Focus Address Bar", action: #selector(focusAddressBar), keyEquivalent: "l")
        editMenu.addItem(focusItem)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenu = NSMenu(title: "View")
        let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(nextTab), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(nextTabItem)
        let nextTabItem2 = NSMenuItem(title: "Next Tab", action: #selector(nextTab), keyEquivalent: "\t")
        nextTabItem2.keyEquivalentModifierMask = [.control]
        nextTabItem2.isHidden = true
        viewMenu.addItem(nextTabItem2)
        let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(prevTab), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(prevTabItem)
        let prevTabItem2 = NSMenuItem(title: "Previous Tab", action: #selector(prevTab), keyEquivalent: "\u{0019}")
        prevTabItem2.keyEquivalentModifierMask = [.control, .shift]
        prevTabItem2.isHidden = true
        viewMenu.addItem(prevTabItem2)
        viewMenu.addItem(.separator())
        let backItem = NSMenuItem(title: "Back", action: #selector(goBack), keyEquivalent: "[")
        backItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(backItem)
        let forwardItem = NSMenuItem(title: "Forward", action: #selector(goForward), keyEquivalent: "]")
        forwardItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(forwardItem)
        viewMenu.addItem(.separator())
        let queueItem = NSMenuItem(title: "Toggle Queue", action: #selector(toggleQueue), keyEquivalent: "q")
        queueItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(queueItem)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let devMenu = NSMenu(title: "Develop")
        let jsConsoleItem = NSMenuItem(title: "JS Console", action: #selector(toggleJSConsole), keyEquivalent: "j")
        jsConsoleItem.keyEquivalentModifierMask = [.command, .option]
        devMenu.addItem(jsConsoleItem)
        let devMenuItem = NSMenuItem()
        devMenuItem.submenu = devMenu
        mainMenu.addItem(devMenuItem)

        let pluginMenu = NSMenu(title: "Plugins")
        pluginMenu.addItem(withTitle: "Manage Plugins…", action: #selector(showPluginSettings), keyEquivalent: ",")
        let openPluginDir = NSMenuItem(title: "Open Plugin Folder", action: #selector(openPluginFolder), keyEquivalent: "")
        pluginMenu.addItem(openPluginDir)
        pluginMenu.addItem(.separator())
        let reloadPlugins = NSMenuItem(title: "Reload Plugins", action: #selector(reloadAllPlugins), keyEquivalent: "r")
        reloadPlugins.keyEquivalentModifierMask = [.command, .shift]
        pluginMenu.addItem(reloadPlugins)
        let pluginMenuItem = NSMenuItem()
        pluginMenuItem.submenu = pluginMenu
        mainMenu.addItem(pluginMenuItem)

        let historyMenu = NSMenu(title: "History")
        historyMenu.addItem(withTitle: "Show History", action: #selector(showHistory), keyEquivalent: "y")
        let historyMenuItem = NSMenuItem()
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Actions

    @objc func newTab() {
        tabManager.addTab()
    }

    @objc func closeCurrentTab() {
        tabManager.closeTab(at: tabManager.selectedIndex)
    }

    @objc func focusAddressBar() {
        addressBar.focus()
    }

    @objc func nextTab() {
        let next = (tabManager.selectedIndex + 1) % tabManager.tabs.count
        tabManager.selectTab(at: next)
    }

    @objc func prevTab() {
        let prev = (tabManager.selectedIndex - 1 + tabManager.tabs.count) % tabManager.tabs.count
        tabManager.selectTab(at: prev)
    }

    @objc func goBack() {
        tabManager.activeTab?.webView?.goBack()
    }

    @objc func goForward() {
        tabManager.activeTab?.webView?.goForward()
    }

    @objc func toggleJSConsole() {
        if let controller = jsConsoleController, controller.window?.isVisible == true {
            controller.window?.close()
            jsConsoleController = nil
        } else {
            let controller = JSConsoleWindowController(webView: tabManager.activeTab?.webView)
            controller.showWindow(nil)
            controller.window?.orderFront(nil)
            jsConsoleController = controller
        }
    }

    @objc func showHistory() {
        let vc = HistoryViewController()
        vc.historyDelegate = self
        presentAsSheet(vc)
    }

    private func presentAsSheet(_ vc: NSViewController) {
        guard let window = self.window else { return }
        window.contentViewController?.presentAsSheet(vc)
    }

    // MARK: - Window State

    func saveWindowState() {
        guard let frame = window?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "windowFrame")

        // Save tabs
        let tabData = tabManager.tabs.map { tab -> [String: String] in
            let url = tab.webView?.url ?? tab.url
            let title = tab.webView?.title ?? tab.title
            return ["url": url.absoluteString, "title": title]
        }
        UserDefaults.standard.set(tabData, forKey: "savedTabs")
        UserDefaults.standard.set(tabManager.selectedIndex, forKey: "savedTabSelectedIndex")
    }

    private func restoreTabs() {
        if let tabData = UserDefaults.standard.array(forKey: "savedTabs") as? [[String: String]], !tabData.isEmpty {
            for entry in tabData {
                if let urlStr = entry["url"], let url = URL(string: urlStr) {
                    let tab = tabManager.addTab(url: url)
                    if let title = entry["title"], !title.isEmpty {
                        tab.title = title
                    }
                }
            }
            let savedIndex = UserDefaults.standard.integer(forKey: "savedTabSelectedIndex")
            if savedIndex >= 0 && savedIndex < tabManager.tabs.count {
                tabManager.selectTab(at: savedIndex)
            }
        } else {
            tabManager.addTab()
        }
    }

    private func restoreWindowState() {
        if let frameStr = UserDefaults.standard.string(forKey: "windowFrame") {
            let frame = NSRectFromString(frameStr)
            if frame.width > 100 && frame.height > 100 {
                window?.setFrame(frame, display: true)
            }
        } else {
            window?.center()
        }
    }

    // MARK: - Tab Bar UI

    private func rebuildTabBar() {
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, tab) in tabManager.tabs.enumerated() {
            let button = TabBarButton(title: tab.title, index: i, isSuspended: tab.isSuspended, isSelected: i == tabManager.selectedIndex, isPlaying: tab.isPlayingMedia)
            button.target = self
            button.action = #selector(tabButtonClicked(_:))
            button.closeTarget = self
            button.closeAction = #selector(tabCloseClicked(_:))
            button.tag = i
            tabStackView.addArrangedSubview(button)
        }
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        tabManager.selectTab(at: sender.tag)
    }

    @objc private func tabCloseClicked(_ sender: NSButton) {
        tabManager.closeTab(at: sender.tag)
    }

    // MARK: - Display WebView

    private func displayWebView(for tab: Tab) {
        webViewContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let wv = tab.webView else { return }
        wv.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            wv.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
        ])
        addressBar.setURL(tab.webView?.url ?? tab.url)
        jsConsoleController?.updateWebView(tab.webView)
    }

    // MARK: - TabManagerDelegate

    func tabManager(_ manager: TabManager, didAddTab tab: Tab, at index: Int) {
        rebuildTabBar()
    }

    func tabManager(_ manager: TabManager, didRemoveTabAt index: Int) {
        rebuildTabBar()
    }

    func tabManager(_ manager: TabManager, didSelectTab tab: Tab, at index: Int) {
        displayWebView(for: tab)
        rebuildTabBar()
        window?.title = tab.title
        toolbar.updatePlaybackRate(tab.playbackRate)
        applyPlaybackRate(tab.playbackRate, to: tab)
    }

    func tabManager(_ manager: TabManager, didUpdateTab tab: Tab, at index: Int) {
        rebuildTabBar()
    }

    func tabManagerNavigationDelegate(_ manager: TabManager) -> WKNavigationDelegate? { self }
    func tabManagerUIDelegate(_ manager: TabManager) -> WKUIDelegate? { self }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Allow about:blank etc
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
            return
        }

        if URLRouter.isAllowed(url) {
            // Cmd+click, middle-click, or three-finger tap → new tab
            if navigationAction.modifierFlags.contains(.command) ||
                navigationAction.buttonNumber == 1 ||
                navigationAction.buttonNumber == 2 {
                decisionHandler(.cancel)
                tabManager.addTab(url: url)
                return
            }
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            URLRouter.openInDefaultBrowser(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tabForWebView(webView) else { return }
        tab.url = webView.url ?? tab.url
        tab.title = webView.title ?? tab.title
        if tab.title.hasSuffix(" - YouTube") {
            tab.title = String(tab.title.dropLast(10))
        }
        tabManager.updateTab(tab)
        if tab.id == tabManager.activeTab?.id {
            addressBar.setURL(webView.url)
            window?.title = tab.title
        }

        // Record history for watch pages
        if let url = webView.url, url.absoluteString.contains("youtube.com/watch") {
            webView.evaluateJavaScript(durationExtractorJS) { result, _ in
                let duration = result as? String
                HistoryManager.shared.recordVisit(url: url.absoluteString, title: tab.title, duration: duration)
            }
        }

        // Apply saved playback rate and theater mode on watch pages
        if let url = webView.url, url.absoluteString.contains("youtube.com") {
            applyPlaybackSettings(to: webView)
        }
    }

    private func applyPlaybackRate(_ rate: Float, to tab: Tab) {
        guard let webView = tab.webView else { return }
        webView.evaluateJavaScript("document.querySelector('video').playbackRate = \(rate)")
    }

    private func applyPlaybackSettings(to webView: WKWebView) {
        let tab = tabForWebView(webView)
        let rate = tab?.playbackRate ?? Settings.defaultPlaybackRate
        let theater = Settings.theaterMode

        // Apply playback rate once video element exists
        webView.evaluateJavaScript("""
            (function() {
                function applyRate() {
                    const v = document.querySelector('video');
                    if (v) { v.playbackRate = \(rate); return true; }
                    return false;
                }
                if (!applyRate()) {
                    const obs = new MutationObserver(function() {
                        if (applyRate()) obs.disconnect();
                    });
                    obs.observe(document.body, { childList: true, subtree: true });
                    setTimeout(function() { obs.disconnect(); }, 10000);
                }
            })()
        """)

        // Log theater cookie status to JS console
        webView.evaluateJavaScript("""
            (function() {
                var wide = document.cookie.split(';').map(c=>c.trim()).find(c=>c.startsWith('wide='));
                var theater = document.querySelector('ytd-watch-flexy')?.hasAttribute('theater');
                if (window.webkit && window.webkit.messageHandlers.consoleLog) {
                    window.webkit.messageHandlers.consoleLog.postMessage(
                        'cookie: ' + (wide||'wide NOT set') + ' | flexy theater=' + theater
                    );
                }
            })()
        """)

        // Theater mode — click button on SPA navigation if needed
        if theater {
            webView.evaluateJavaScript("""
                (function() {
                    function applyTheater() {
                        const page = document.querySelector('ytd-watch-flexy');
                        if (!page) return false;
                        if (page.hasAttribute('theater')) return true;
                        const btn = document.querySelector('.ytp-size-button');
                        if (btn) { btn.click(); return true; }
                        return false;
                    }
                    let attempts = 0;
                    function tryApply() {
                        if (applyTheater() || ++attempts > 20) return;
                        setTimeout(tryApply, 250);
                    }
                    tryApply();
                })()
            """)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let tab = tabForWebView(webView), tab.id == tabManager.activeTab?.id {
            addressBar.setURL(webView.url)
        }
    }

    // Handle auth challenges — let the system handle passkeys/WebAuthn
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - WKUIDelegate — handle target=_blank links

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            tabManager.addTab(url: url)
        }
        return nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "newTab" {
            if let urlString = message.body as? String, let url = URL(string: urlString) {
                tabManager.addTab(url: url)
            }
            return
        }

        if message.name == "elementPicked" {
            if let selector = message.body as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.showHelpWithPickedElement(selector)
                }
            }
            return
        }

        if message.name == "pluginBridge" {
            PluginManager.shared.handleMessage(message.body, webView: message.webView ?? tabManager.activeTab?.webView ?? WKWebView())
            return
        }

        if message.name == "consoleLog" {
            if let text = message.body as? String {
                jsConsoleController?.appendSystemLog(text)
            }
            return
        }

        if message.name == "queueBridge" {
            if let body = message.body as? String,
               let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let videoId = json["videoId"] as? String {
                let title = json["title"] as? String ?? ""
                let channel = json["channel"] as? String ?? ""
                let duration = json["duration"] as? String ?? ""
                let viewCount = json["viewCount"] as? String ?? ""
                let publishedText = json["publishedText"] as? String ?? ""
                let thumbnail = json["thumbnail"] as? String
                QueueManager.shared.addItem(
                    videoId: videoId, title: title, channel: channel,
                    duration: duration, viewCount: viewCount, publishedText: publishedText,
                    thumbnailURL: thumbnail
                )
                // Auto-show queue sidebar when adding
                if !isQueueVisible { toggleQueue() }
            }
            return
        }

        if message.name == "theaterChanged" {
            if let isTheater = message.body as? Bool {
                Settings.theaterMode = isTheater
                tabManager.updateTheaterModeScript()
            }
            return
        }

        if message.name == "urlChanged" {
            guard let urlString = message.body as? String,
                  let url = URL(string: urlString),
                  let webView = message.webView,
                  let tab = tabForWebView(webView) else { return }
            tab.url = url
            let title = webView.title ?? tab.title
            if title != tab.title {
                tab.title = title
                if tab.title.hasSuffix(" - YouTube") {
                    tab.title = String(tab.title.dropLast(10))
                }
            }
            tabManager.updateTab(tab)
            if tab.id == tabManager.activeTab?.id {
                addressBar.setURL(url)
                window?.title = tab.title
            }
            // Dispatch navigate event to plugins
            PluginManager.shared.dispatchEvent("navigate", data: [
                "url": url.absoluteString,
                "title": tab.title,
            ], webView: webView)
            // Record history for watch pages
            if url.absoluteString.contains("youtube.com/watch") {
                // Re-apply playback rate on SPA navigation
                applyPlaybackSettings(to: webView)
                webView.evaluateJavaScript(durationExtractorJS) { result, _ in
                    let duration = result as? String
                    HistoryManager.shared.recordVisit(url: url.absoluteString, title: tab.title, duration: duration)
                }
            }
            return
        }

        guard message.name == "mediaBridge",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let webView = message.webView, let tab = tabForWebView(webView) else { return }

        let paused = json["paused"] as? Bool ?? true
        let ended = json["ended"] as? Bool ?? false
        let wasPlaying = tab.isPlayingMedia
        tab.isPlayingMedia = !paused && !ended

        if tab.isPlayingMedia != wasPlaying {
            rebuildTabBar()
        }

        // If this tab just started playing, pause all other tabs
        if tab.isPlayingMedia && !wasPlaying {
            for other in tabManager.tabs where other.id != tab.id && other.isPlayingMedia {
                other.webView?.evaluateJavaScript("document.querySelector('video')?.pause()")
            }
        }

        // Dispatch videoState event to plugins
        PluginManager.shared.dispatchEvent("videoState", data: json, webView: webView)
        if ended {
            PluginManager.shared.dispatchEvent("videoEnd", data: json, webView: webView)
        }

        if tab.id == tabManager.activeTab?.id {
            let title = json["title"] as? String ?? ""
            let channel = json["channel"] as? String ?? ""
            let duration = json["duration"] as? Double ?? 0
            let currentTime = json["currentTime"] as? Double ?? 0

            if !paused || (duration > 0 && !ended) {
                MediaKeyHandler.shared.updateNowPlaying(
                    title: title, channel: channel,
                    duration: duration, currentTime: currentTime, paused: paused
                )
            } else {
                MediaKeyHandler.shared.clearNowPlaying()
            }

            // Auto-play next in queue when video ends
            if ended && QueueManager.shared.hasNext {
                handleVideoEnded()
            }
        }
    }

    // MARK: - Queue

    @objc func toggleQueue() {
        isQueueVisible.toggle()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            queueSidebarWidth?.animator().constant = isQueueVisible ? QueueSidebarView.width : 0
        }
        queueSidebar?.reload()
    }

    func queueSidebar(_ sidebar: QueueSidebarView, didSelectItem item: QueueItem) {
        tabManager.activeTab?.webView?.load(URLRequest(url: item.watchURL))
    }

    func queueSidebarDidClose(_ sidebar: QueueSidebarView) {
        toggleQueue()
    }

    func queueDidUpdate() {
        queueSidebar?.reload()
    }

    private func handleVideoEnded() {
        guard let next = QueueManager.shared.playNext() else { return }
        tabManager.activeTab?.webView?.load(URLRequest(url: next.watchURL))
        queueSidebar?.reload()
    }

    // MARK: - ToolbarDelegate

    func toolbarGoBack(_ toolbar: ToolbarView) { goBack() }
    func toolbarGoForward(_ toolbar: ToolbarView) { goForward() }
    func toolbarRefresh(_ toolbar: ToolbarView) { tabManager.activeTab?.webView?.reload() }

    func toolbarPlayPause(_ toolbar: ToolbarView) {
        tabManager.activeTab?.webView?.evaluateJavaScript("""
            (function() { const v = document.querySelector('video'); if (v) { v.paused ? v.play() : v.pause(); } })()
        """)
    }

    func toolbarPrevTrack(_ toolbar: ToolbarView) {
        tabManager.activeTab?.webView?.evaluateJavaScript("""
            (function() { const v = document.querySelector('video'); if (v) { v.currentTime = Math.max(0, v.currentTime - 10); } })()
        """)
    }

    func toolbarNextTrack(_ toolbar: ToolbarView) {
        tabManager.activeTab?.webView?.evaluateJavaScript("document.querySelector('.ytp-next-button')?.click()")
    }

    func toolbar(_ toolbar: ToolbarView, didChangePlaybackRate rate: Float) {
        if let tab = tabManager.activeTab {
            tab.playbackRate = rate
            applyPlaybackRate(rate, to: tab)
        }
    }

    func toolbarResetSpeed(_ toolbar: ToolbarView) {
        let rate = Settings.defaultPlaybackRate
        if let tab = tabManager.activeTab {
            tab.playbackRate = rate
            applyPlaybackRate(rate, to: tab)
        }
        toolbar.updatePlaybackRate(rate)
    }

    // MARK: - AddressBarDelegate

    func addressBar(_ bar: AddressBarView, didSubmitInput input: String) {
        let url = URLRouter.resolveInput(input)
        if let tab = tabManager.activeTab {
            tab.webView?.load(URLRequest(url: url))
        }
    }

    func addressBarGoBack(_ bar: AddressBarView) { goBack() }
    func addressBarGoForward(_ bar: AddressBarView) { goForward() }

    // MARK: - HistoryViewControllerDelegate

    func historyViewController(_ vc: HistoryViewController, didSelectURL url: URL) {
        tabManager.activeTab?.webView?.load(URLRequest(url: url))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveWindowState()
    }

    // MARK: - PluginManagerDelegate

    func pluginManager(_ manager: PluginManager, didReceiveNotification message: String, type: String) {
        // Show as JS toast via the active webview
        let escaped = message.replacingOccurrences(of: "'", with: "\\'")
        tabManager.activeTab?.webView?.evaluateJavaScript("window.YTApp && window.YTApp.ui.toast('\(escaped)')")
    }

    func pluginManager(_ manager: PluginManager, openTab url: URL) {
        tabManager.addTab(url: url)
    }

    func pluginManager(_ manager: PluginManager, navigate url: URL) {
        tabManager.activeTab?.webView?.load(URLRequest(url: url))
    }

    func pluginManager(_ manager: PluginManager, queueAdd videoId: String, title: String, channel: String, duration: String) {
        QueueManager.shared.addItem(videoId: videoId, title: title, channel: channel, duration: duration, viewCount: "", publishedText: "", thumbnailURL: nil)
        if !isQueueVisible { toggleQueue() }
    }

    func pluginManagerQueueClear(_ manager: PluginManager) {
        QueueManager.shared.clear()
        queueSidebar?.reload()
    }

    func pluginManagerQueuePlayNext(_ manager: PluginManager) {
        handleVideoEnded()
    }

    func pluginManager(_ manager: PluginManager, setRate rate: Float) {
        if let tab = tabManager.activeTab {
            tab.playbackRate = rate
            applyPlaybackRate(rate, to: tab)
        }
        toolbar.updatePlaybackRate(rate)
    }

    func pluginManagerPluginsDidReload(_ manager: PluginManager) {
        // Re-inject plugin scripts into active tab
        if let wv = tabManager.activeTab?.webView {
            for script in manager.userScripts() {
                wv.evaluateJavaScript(script.source)
            }
            PluginManager.shared.dispatchEvent("reload", data: [:], webView: wv)
        }
    }

    // MARK: - PluginSettingsDelegate

    func pluginSettingsDidChange() {
        pluginManagerPluginsDidReload(PluginManager.shared)
    }

    func pluginSettingsOpenPluginDir() {
        let dir = PluginManager.pluginDirectories.first!
        NSWorkspace.shared.open(dir)
    }

    @objc func openPluginFolder() {
        let dir = PluginManager.pluginDirectories.first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func reloadAllPlugins() {
        PluginManager.shared.reload()
    }

    @objc func showPluginSettings() {
        let vc = PluginSettingsViewController()
        vc.settingsDelegate = self
        presentAsSheet(vc)
    }

    // MARK: - KeyboardShortcutDelegate

    func shortcutNewTab() { newTab() }
    func shortcutCloseTab() { closeCurrentTab() }
    func shortcutNextTab() { nextTab() }
    func shortcutPrevTab() { prevTab() }
    func shortcutFocusAddressBar() { focusAddressBar() }
    func shortcutGoBack() { goBack() }
    func shortcutGoForward() { goForward() }
    func shortcutRefresh() { tabManager.activeTab?.webView?.reload() }
    func shortcutPlayPause() { toolbar.delegate?.toolbarPlayPause(toolbar) }
    func shortcutToggleQueue() { toggleQueue() }
    func shortcutShowHistory() { showHistory() }

    func shortcutShowHelp() {
        let vc = HelpModalViewController()
        vc.helpDelegate = self
        self.helpModal = vc
        presentAsSheet(vc)
    }

    func shortcutShowLinkHints(newTab: Bool) {
        let arg = newTab ? "true" : "false"
        tabManager.activeTab?.webView?.evaluateJavaScript("window.__ytShowLinkHints && window.__ytShowLinkHints(\(arg))")
    }

    func shortcutScrollTop() {
        tabManager.activeTab?.webView?.evaluateJavaScript("window.scrollTo({top:0,behavior:'smooth'})")
    }

    func shortcutScrollBottom() {
        tabManager.activeTab?.webView?.evaluateJavaScript("window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})")
    }

    func shortcutStartElementPicker() {
        tabManager.activeTab?.webView?.evaluateJavaScript("window.__ytStartElementPicker && window.__ytStartElementPicker()")
    }

    func shortcutActiveWebView() -> WKWebView? { tabManager.activeTab?.webView }
    func shortcutActiveURL() -> String? { tabManager.activeTab?.webView?.url?.absoluteString }

    // MARK: - HelpModalDelegate

    func helpModalDidRequestElementPicker() {
        // Dismiss sheet, start picker
        helpModal?.dismiss(nil)
        shortcutStartElementPicker()
    }

    private func showHelpWithPickedElement(_ selector: String) {
        let vc = HelpModalViewController()
        vc.helpDelegate = self
        self.helpModal = vc
        presentAsSheet(vc)
        // Fill in the picked selector after a tiny delay so the view loads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            vc.didPickElement(selector: selector)
        }
    }

    // MARK: - Helpers

    private func tabForWebView(_ webView: WKWebView) -> Tab? {
        tabManager.tabs.first { $0.webView === webView }
    }
}

// MARK: - TabBarButton

class TabBarButton: NSView {
    var target: AnyObject?
    var action: Selector?
    var closeTarget: AnyObject?
    var closeAction: Selector?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool

    override var tag: Int {
        get { titleLabel.tag }
        set {
            titleLabel.tag = newValue
            closeButton.tag = newValue
        }
    }

    init(title: String, index: Int, isSuspended: Bool, isSelected: Bool, isPlaying: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)

        wantsLayer = true
        if isSelected && isPlaying {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        } else if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        } else if isPlaying {
            layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        layer?.cornerRadius = 4

        var prefix = ""
        if isSuspended { prefix = "💤 " }
        else if isPlaying { prefix = "🔊 " }
        titleLabel.stringValue = prefix + title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alphaValue = isSuspended ? 0.5 : 1.0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.bezelStyle = .inline
        closeButton.title = "×"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 14, weight: .bold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.alphaValue = 0.5
        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        addSubview(titleLabel)
        addSubview(closeButton)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() {
        _ = target?.perform(action, with: self)
    }

    @objc private func closeClicked() {
        _ = closeTarget?.perform(closeAction, with: closeButton)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0.5
    }
}
