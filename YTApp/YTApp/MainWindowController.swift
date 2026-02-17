import Cocoa
import WebKit

class MainWindowController: NSWindowController, NSWindowDelegate, TabManagerDelegate,
    AddressBarDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    HistoryViewControllerDelegate {

    let tabManager = TabManager()
    private let addressBar = AddressBarView(frame: .zero)
    private let tabBar = NSSegmentedControl()
    private let webViewContainer = NSView()
    private var tabBarScrollView: NSScrollView!

    // Custom tab bar
    private let tabStackView = NSStackView()

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
        tabManager.addTab()
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

        webViewContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(tabBarContainer)
        contentView.addSubview(addressBar)
        contentView.addSubview(webViewContainer)

        NSLayoutConstraint.activate([
            tabBarContainer.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            tabBarContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBarContainer.heightAnchor.constraint(equalToConstant: 30),

            addressBar.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
            addressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            addressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            addressBar.heightAnchor.constraint(equalToConstant: 36),

            webViewContainer.topAnchor.constraint(equalTo: addressBar.bottomAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
        let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(prevTab), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(prevTabItem)
        viewMenu.addItem(.separator())
        let backItem = NSMenuItem(title: "Back", action: #selector(goBack), keyEquivalent: "[")
        backItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(backItem)
        let forwardItem = NSMenuItem(title: "Forward", action: #selector(goForward), keyEquivalent: "]")
        forwardItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(forwardItem)
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

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
            let button = TabBarButton(title: tab.title, index: i, isSuspended: tab.isSuspended, isSelected: i == tabManager.selectedIndex)
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
            // Cmd+click or middle-click → new tab
            if navigationAction.modifierFlags.contains(.command) ||
                navigationAction.buttonNumber == 1 {
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
        guard message.name == "mediaBridge",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let webView = message.webView, let tab = tabForWebView(webView) else { return }

        let paused = json["paused"] as? Bool ?? true
        let ended = json["ended"] as? Bool ?? false
        tab.isPlayingMedia = !paused && !ended

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
        }
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

    init(title: String, index: Int, isSuspended: Bool, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            : NSColor.clear.cgColor
        layer?.cornerRadius = 4

        titleLabel.stringValue = isSuspended ? "💤 \(title)" : title
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
