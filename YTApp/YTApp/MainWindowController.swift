import Cocoa
import WebKit

class MainWindowController: NSWindowController, NSWindowDelegate, TabManagerDelegate,
    AddressBarDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
    HistoryViewControllerDelegate, ToolbarDelegate, QueueSidebarDelegate, QueueManagerDelegate,
    KeyboardShortcutDelegate, HelpModalDelegate, PluginManagerDelegate, PluginSettingsDelegate, SettingsDelegate,
    TreeTabSidebarDelegate {

    let tabManager = TabManager()
    private let addressBar = AddressBarView(frame: .zero)
    private let toolbar = ToolbarView(frame: .zero)
    private let loadingProgressBar = LoadingProgressBar(frame: .zero)
    private let tabBar = NSSegmentedControl()
    private let webViewContainer = NSView()
    private var tabBarScrollView: NSScrollView!
    private let keyboardHandler = KeyboardShortcutHandler()
    private var helpModal: HelpModalViewController?

    // Custom tab bar
    private let tabStackView = NSStackView()
    private var jsConsoleController: JSConsoleWindowController?
    private var progressObservation: NSKeyValueObservation?
    private var progressFadeWorkItem: DispatchWorkItem?
    private var activeToast: ToastView?
    private var toastDismissWorkItem: DispatchWorkItem?
    private let darkFlashOverlay = NSView()
    private var findBar: FindBarView?
    private var handoffActivity: NSUserActivity?
    private lazy var playbackRateFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter
    }()

    // Queue sidebar
    private var queueSidebar: QueueSidebarView?
    private var queueSidebarWidth: NSLayoutConstraint?
    private var isQueueVisible = false

    // Tree tab sidebar
    private var treeTabSidebar: TreeTabSidebarView?
    private var treeTabSidebarWidth: NSLayoutConstraint?
    private var treeTabLeading: NSLayoutConstraint?
    private var treeTabTrailing: NSLayoutConstraint?
    private var webViewLeading: NSLayoutConstraint?
    private var webViewTrailingToTree: NSLayoutConstraint?

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
        window.collectionBehavior = [.fullScreenPrimary]

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
        if Settings.queueEnabled {
            tabManager.sharedConfiguration.userContentController.add(self, name: "queueBridge")
        }
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

        loadingProgressBar.translatesAutoresizingMaskIntoConstraints = false

        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        webViewContainer.wantsLayer = true
        webViewContainer.layer?.backgroundColor = NSColor.black.cgColor

        darkFlashOverlay.translatesAutoresizingMaskIntoConstraints = false
        darkFlashOverlay.wantsLayer = true
        darkFlashOverlay.layer?.backgroundColor = NSColor.black.cgColor
        darkFlashOverlay.alphaValue = 0
        darkFlashOverlay.layer?.zPosition = 100

        // Queue sidebar
        let sidebar = QueueSidebarView(frame: .zero)
        sidebar.delegate = self
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        self.queueSidebar = sidebar

        // Tree tab sidebar
        let treeSidebar = TreeTabSidebarView(frame: .zero)
        treeSidebar.delegate = self
        treeSidebar.tabManager = tabManager
        treeSidebar.translatesAutoresizingMaskIntoConstraints = false
        self.treeTabSidebar = treeSidebar

        // Body container (tree sidebar + webview + queue sidebar)
        let bodyContainer = NSView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(treeSidebar)
        bodyContainer.addSubview(webViewContainer)
        bodyContainer.addSubview(sidebar)

        contentView.addSubview(tabBarContainer)
        contentView.addSubview(addressBar)
        contentView.addSubview(toolbar)
        contentView.addSubview(loadingProgressBar)
        contentView.addSubview(bodyContainer)

        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 0)
        self.queueSidebarWidth = sidebarWidth

        let treeWidth = treeSidebar.widthAnchor.constraint(equalToConstant: Settings.treeTabsEnabled ? TreeTabSidebarView.width : 0)
        self.treeTabSidebarWidth = treeWidth

        // Hide horizontal tab bar when tree tabs enabled
        let tabBarHeight: CGFloat = Settings.treeTabsEnabled ? 0 : 30

        NSLayoutConstraint.activate([
            tabBarContainer.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
            tabBarContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBarContainer.heightAnchor.constraint(equalToConstant: tabBarHeight),

            addressBar.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor),
            addressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            addressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            addressBar.heightAnchor.constraint(equalToConstant: 36),

            toolbar.topAnchor.constraint(equalTo: addressBar.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 30),

            loadingProgressBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            loadingProgressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            loadingProgressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            loadingProgressBar.heightAnchor.constraint(equalToConstant: 2),

            bodyContainer.topAnchor.constraint(equalTo: loadingProgressBar.bottomAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            treeSidebar.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            treeSidebar.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            treeWidth,

            webViewContainer.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),

            sidebar.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            sidebar.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            sidebarWidth,
        ])

        applyTreeTabSideLayout(bodyContainer: bodyContainer)

        webViewContainer.addSubview(darkFlashOverlay)
        NSLayoutConstraint.activate([
            darkFlashOverlay.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            darkFlashOverlay.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
            darkFlashOverlay.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
            darkFlashOverlay.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
        ])
    }

    /// Layout order: Left → [treeSidebar?] [webView] [treeSidebar?] [queueSidebar] → Right
    private func applyTreeTabSideLayout(bodyContainer: NSView) {
        guard let treeSidebar = treeTabSidebar, let queueSidebar = queueSidebar else { return }

        treeTabLeading?.isActive = false
        treeTabTrailing?.isActive = false
        webViewLeading?.isActive = false
        webViewTrailingToTree?.isActive = false

        if Settings.treeTabsSide == .left {
            // [tree] [webView] [queue]
            treeTabLeading = treeSidebar.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor)
            webViewLeading = webViewContainer.leadingAnchor.constraint(equalTo: treeSidebar.trailingAnchor)
            treeTabTrailing = nil
            webViewTrailingToTree = webViewContainer.trailingAnchor.constraint(equalTo: queueSidebar.leadingAnchor)
        } else {
            // [webView] [tree] [queue]
            webViewLeading = webViewContainer.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor)
            webViewTrailingToTree = webViewContainer.trailingAnchor.constraint(equalTo: treeSidebar.leadingAnchor)
            treeTabTrailing = treeSidebar.trailingAnchor.constraint(equalTo: queueSidebar.leadingAnchor)
            treeTabLeading = nil
        }

        treeTabLeading?.isActive = true
        treeTabTrailing?.isActive = true
        webViewLeading?.isActive = true
        webViewTrailingToTree?.isActive = true
        treeSidebar.updateBorderSide()
    }

    // MARK: - Menu / Keyboard Shortcuts

    func setupMenus() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About YTApp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
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
        let findItem = NSMenuItem(title: "Find…", action: #selector(showFindBar), keyEquivalent: "f")
        editMenu.addItem(findItem)
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
        let reloadItem = NSMenuItem(title: "Reload Page", action: #selector(reloadPage), keyEquivalent: "r")
        reloadItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(reloadItem)
        viewMenu.addItem(.separator())
        if Settings.queueEnabled {
            let queueItem = NSMenuItem(title: "Toggle Queue", action: #selector(toggleQueue), keyEquivalent: "q")
            queueItem.keyEquivalentModifierMask = [.command, .shift]
            viewMenu.addItem(queueItem)
        }
        viewMenu.addItem(.separator())
        for i in 1...9 {
            let item = NSMenuItem(title: "Tab \(i)", action: #selector(switchToTabByNumber(_:)), keyEquivalent: "\(i)")
            item.keyEquivalentModifierMask = [.command]
            item.tag = i
            viewMenu.addItem(item)
        }
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let tabMenu = NSMenu(title: "Tab")
        tabMenu.addItem(withTitle: "Suspend Tab", action: #selector(suspendCurrentTab), keyEquivalent: "")
        tabMenu.addItem(withTitle: "Suspend Other Tabs", action: #selector(suspendOtherTabs), keyEquivalent: "")
        tabMenu.addItem(withTitle: "Unsuspend All Tabs", action: #selector(unsuspendAllTabs), keyEquivalent: "")
        let tabMenuItem = NSMenuItem()
        tabMenuItem.submenu = tabMenu
        mainMenu.addItem(tabMenuItem)

        let devMenu = NSMenu(title: "Develop")
        let jsConsoleItem = NSMenuItem(title: "JS Console", action: #selector(toggleJSConsole), keyEquivalent: "j")
        jsConsoleItem.keyEquivalentModifierMask = [.command, .option]
        devMenu.addItem(jsConsoleItem)
        let devMenuItem = NSMenuItem()
        devMenuItem.submenu = devMenu
        mainMenu.addItem(devMenuItem)

        let pluginMenu = NSMenu(title: "Plugins")
        pluginMenu.addItem(withTitle: "Manage Plugins…", action: #selector(showPluginSettings), keyEquivalent: "")
        let openPluginDir = NSMenuItem(title: "Open Plugin Folder", action: #selector(openPluginFolder), keyEquivalent: "")
        pluginMenu.addItem(openPluginDir)
        pluginMenu.addItem(.separator())
        let reloadPlugins = NSMenuItem(title: "Reload Plugins", action: #selector(reloadAllPlugins), keyEquivalent: "r")
        reloadPlugins.keyEquivalentModifierMask = [.command, .shift]
        pluginMenu.addItem(reloadPlugins)
        let pluginMenuItem = NSMenuItem()
        pluginMenuItem.submenu = pluginMenu
        mainMenu.addItem(pluginMenuItem)

        let fileMenu2 = mainMenu.item(withTitle: "File")?.submenu
        fileMenu2?.addItem(.separator())
        let shareItem = NSMenuItem(title: "Share…", action: #selector(shareCurrentPage), keyEquivalent: "")
        shareItem.keyEquivalentModifierMask = []
        fileMenu2?.addItem(shareItem)

        if Settings.queueEnabled {
            let queueMenu = NSMenu(title: "Queue")
            queueMenu.addItem(withTitle: "Export Queue…", action: #selector(exportQueue), keyEquivalent: "")
            queueMenu.addItem(withTitle: "Import Queue…", action: #selector(importQueue), keyEquivalent: "")
            let queueMenuItem = NSMenuItem()
            queueMenuItem.submenu = queueMenu
            mainMenu.addItem(queueMenuItem)
        }

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

    @objc func suspendCurrentTab() {
        let wasSuspended = tabManager.activeTab?.isSuspended ?? false
        tabManager.toggleSuspendTab(at: tabManager.selectedIndex)
        if !wasSuspended {
            showToast("Tab suspended")
        }
    }

    @objc func suspendOtherTabs() {
        tabManager.suspendOtherTabs()
    }

    @objc func unsuspendAllTabs() {
        tabManager.unsuspendAllTabs()
    }

    @objc func suspendTabAtIndex(_ sender: NSMenuItem) {
        tabManager.toggleSuspendTab(at: sender.tag)
    }

    @objc func suspendOtherTabsFromIndex(_ sender: NSMenuItem) {
        let index = sender.tag
        // Suspend all except the one at index
        for (i, tab) in tabManager.tabs.enumerated() {
            guard i != index, !tab.isSuspended, tab.webView != nil else { continue }
            tab.suspend()
            tabManager.updateTab(tab)
        }
    }

    @objc func closeTabFromMenu(_ sender: NSMenuItem) {
        tabManager.closeTab(at: sender.tag)
    }

    @objc func focusAddressBar() {
        addressBar.focus()
    }

    @objc func showFindBar() {
        if let existing = findBar {
            existing.focus()
            return
        }
        let bar = FindBarView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onSearch = { [weak self] query in
            self?.tabManager.activeTab?.webView?.evaluateJavaScript(
                "window.find('\(query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))', false, false, true)"
            )
        }
        bar.onDismiss = { [weak self] in
            self?.dismissFindBar()
        }
        webViewContainer.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
            bar.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            bar.widthAnchor.constraint(equalToConstant: 300),
            bar.heightAnchor.constraint(equalToConstant: 32),
        ])
        findBar = bar
        bar.focus()
    }

    private func dismissFindBar() {
        findBar?.removeFromSuperview()
        findBar = nil
    }

    @objc func switchToTabByNumber(_ sender: NSMenuItem) {
        let index = sender.tag == 9 ? tabManager.tabs.count - 1 : sender.tag - 1
        guard index >= 0, index < tabManager.tabs.count else { return }
        tabManager.selectTab(at: index)
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

    @objc func reloadPage() {
        tabManager.activeTab?.webView?.reload()
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

    @objc func exportQueue() {
        guard let data = QueueManager.shared.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "queue.json"
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    @objc func importQueue() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.beginSheetModal(for: window!) { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            QueueManager.shared.importJSON(data)
            self.showToast("Queue imported")
        }
    }

    @objc func shareCurrentPage() {
        guard let url = tabManager.activeTab?.webView?.url else { return }
        let title = tabManager.activeTab?.title ?? ""
        let picker = NSSharingServicePicker(items: [url, title])
        picker.show(relativeTo: .zero, of: addressBar, preferredEdge: .minY)
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

        // Save tabs with tree structure
        let tabData = tabManager.tabs.map { tab -> [String: Any] in
            let url = tab.webView?.url ?? tab.url
            let title = tab.webView?.title ?? tab.title
            var d: [String: Any] = [
                "url": url.absoluteString,
                "title": title,
                "id": tab.id.uuidString,
            ]
            if let ch = tab.pinnedChannel { d["pinnedChannel"] = ch }
            if let parent = tab.parent { d["parentId"] = parent.id.uuidString }
            return d
        }
        UserDefaults.standard.set(tabData, forKey: "savedTabs")
        UserDefaults.standard.set(tabManager.selectedIndex, forKey: "savedTabSelectedIndex")
    }

    private func restoreTabs() {
        if let tabData = UserDefaults.standard.array(forKey: "savedTabs") as? [[String: Any]], !tabData.isEmpty {
            let savedIndex = UserDefaults.standard.integer(forKey: "savedTabSelectedIndex")
            var tabById: [String: Tab] = [:]

            for (i, entry) in tabData.enumerated() {
                guard let urlStr = entry["url"] as? String, let url = URL(string: urlStr) else { continue }
                let tab = tabManager.addTab(url: url, select: false)
                if let title = entry["title"] as? String, !title.isEmpty {
                    tab.title = title
                }
                if let ch = entry["pinnedChannel"] as? String {
                    tab.pinnedChannel = ch
                    if let speed = Settings.speedForChannel(ch) {
                        tab.playbackRate = speed
                    }
                }
                if i != savedIndex {
                    tab.isSuspended = true
                }
                if let idStr = entry["id"] as? String {
                    tabById[idStr] = tab
                }
            }

            // Restore parent-child relationships
            for entry in tabData {
                guard let idStr = entry["id"] as? String,
                      let parentIdStr = entry["parentId"] as? String,
                      let tab = tabById[idStr],
                      let parent = tabById[parentIdStr] else { continue }
                parent.addChild(tab)
            }

            let idx = (savedIndex >= 0 && savedIndex < tabManager.tabs.count) ? savedIndex : 0
            tabManager.selectTab(at: idx)
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

    func rebuildTabBar() {
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (i, tab) in tabManager.tabs.enumerated() {
            let button = TabBarButton(title: tab.title, index: i, isSuspended: tab.isSuspended, isSelected: i == tabManager.selectedIndex, isPlaying: tab.isPlayingMedia, url: tab.webView?.url ?? tab.url)
            button.target = self
            button.action = #selector(tabButtonClicked(_:))
            button.closeTarget = self
            button.closeAction = #selector(tabCloseClicked(_:))
            button.contextMenuTarget = self
            button.tag = i
            tabStackView.addArrangedSubview(button)
        }
    }

    private func openBackgroundTab(url: URL) {
        if Settings.treeTabsEnabled, let parent = tabManager.activeTab {
            tabManager.addChildTab(url: url, parent: parent)
        } else {
            tabManager.addTab(url: url, select: false, suspended: true)
            scrollTabBarToEnd()
        }
    }

    private func scrollTabBarToEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let docView = self.tabBarScrollView.documentView else { return }
            let maxX = docView.frame.width - self.tabBarScrollView.contentSize.width
            if maxX > 0 {
                self.tabBarScrollView.contentView.scroll(to: NSPoint(x: maxX, y: 0))
            }
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
        let keepViews: Set<ObjectIdentifier> = [
            ObjectIdentifier(darkFlashOverlay),
            tab.webView.map { ObjectIdentifier($0) },
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        let oldSubviews = webViewContainer.subviews.filter {
            !keepViews.contains(ObjectIdentifier($0)) && !($0 is FindBarView) && !($0 is ToastView)
        }
        oldSubviews.forEach { view in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                view.animator().alphaValue = 0
            }, completionHandler: {
                view.removeFromSuperview()
            })
        }

        if tab.isSuspended {
            let overlay = SuspendedTabOverlay(title: tab.title, url: tab.url)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.onUnsuspend = { [weak self] in
                guard let self = self,
                      let idx = self.tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                self.tabManager.unsuspendTab(at: idx)
            }
            webViewContainer.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            ])
            addressBar.setURL(tab.url)
            jsConsoleController?.updateWebView(nil)
            return
        }

        guard let wv = tab.webView else { return }

        if tab.url.absoluteString == "https://www.youtube.com" || tab.url.absoluteString == "https://www.youtube.com/" {
            if wv.url == nil {
                let ntp = NewTabPageView()
                ntp.translatesAutoresizingMaskIntoConstraints = false
                ntp.onNavigate = { [weak self] url in
                    tab.webView?.load(URLRequest(url: url))
                }
                webViewContainer.addSubview(ntp, positioned: .below, relativeTo: darkFlashOverlay)
                NSLayoutConstraint.activate([
                    ntp.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                    ntp.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
                    ntp.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                    ntp.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
                ])
            }
        }

        darkFlashOverlay.alphaValue = 0

        wv.translatesAutoresizingMaskIntoConstraints = false
        if wv.superview !== webViewContainer {
            wv.alphaValue = 0
            webViewContainer.addSubview(wv, positioned: .below, relativeTo: darkFlashOverlay)
            NSLayoutConstraint.activate([
                wv.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                wv.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor),
                wv.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
            ])
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                wv.animator().alphaValue = 1
            }
        } else {
            wv.alphaValue = 1
        }
        addressBar.setURL(tab.webView?.url ?? tab.url)
        jsConsoleController?.updateWebView(tab.webView)
    }

    // MARK: - TabManagerDelegate

    func tabManager(_ manager: TabManager, didAddTab tab: Tab, at index: Int) {
        rebuildTabBar()
        treeTabSidebar?.reload()
    }

    func tabManager(_ manager: TabManager, didRemoveTabAt index: Int) {
        rebuildTabBar()
        treeTabSidebar?.reload()
    }

    func tabManager(_ manager: TabManager, didSelectTab tab: Tab, at index: Int) {
        displayWebView(for: tab)
        observeLoadingProgress(for: tab.webView)
        rebuildTabBar()
        treeTabSidebar?.reload()
        window?.title = tab.title
        toolbar.updatePlaybackRate(tab.playbackRate, pinned: tab.pinnedChannel)
        applyPlaybackRate(tab.playbackRate, to: tab)
    }

    func tabManager(_ manager: TabManager, didUpdateTab tab: Tab, at index: Int) {
        rebuildTabBar()
        treeTabSidebar?.reload()
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
            // Cmd+click, middle-click, or three-finger tap → background tab
            if navigationAction.modifierFlags.contains(.command) ||
                navigationAction.buttonNumber == 1 ||
                navigationAction.buttonNumber == 2 {
                decisionHandler(.cancel)
                openBackgroundTab(url: url)
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
        if tab.id == tabManager.activeTab?.id {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                darkFlashOverlay.animator().alphaValue = 0
            }
        }
        tab.url = webView.url ?? tab.url
        tab.title = webView.title ?? tab.title
        if tab.title.hasSuffix(" - YouTube") {
            tab.title = String(tab.title.dropLast(10))
        }
        tabManager.updateTab(tab)
        if tab.id == tabManager.activeTab?.id {
            addressBar.setURL(webView.url)
            window?.title = tab.title
            if let url = webView.url { updateHandoff(url: url, title: tab.title) }
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
            if url.absoluteString.contains("/watch") {
                resumePlaybackIfNeeded(url: url, webView: webView)
            }
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
            darkFlashOverlay.alphaValue = 1
        }
    }

    // Handle auth challenges — let the system handle passkeys/WebAuthn
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    // MARK: - WKUIDelegate — handle target=_blank links

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            openBackgroundTab(url: url)
        }
        return nil
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "newTab" {
            if let urlString = message.body as? String, let url = URL(string: urlString) {
                if Settings.treeTabsEnabled, let parent = tabManager.activeTab {
                    tabManager.addChildTab(url: url, parent: parent, select: true, suspended: false)
                } else {
                    tabManager.addTab(url: url)
                }
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
                let displayTitle = title.isEmpty ? "Video" : title
                showToast("Added to queue: \(displayTitle)")
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
                updateHandoff(url: url, title: tab.title)
            }
            // Dispatch navigate event to plugins
            PluginManager.shared.dispatchEvent("navigate", data: [
                "url": url.absoluteString,
                "title": tab.title,
            ], webView: webView)
            // Record history for watch pages
            if url.absoluteString.contains("youtube.com/watch") {
                applyPlaybackSettings(to: webView)
                resumePlaybackIfNeeded(url: url, webView: webView)
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

        let channel = json["channel"] as? String ?? ""
        if !channel.isEmpty && channel != tab.currentChannel {
            tab.currentChannel = channel
            if let speed = Settings.speedForChannel(channel) {
                tab.pinnedChannel = channel
                tab.playbackRate = speed
                applyPlaybackRate(speed, to: tab)
                if tab.id == tabManager.activeTab?.id {
                    toolbar.updatePlaybackRate(speed, pinned: channel)
                }
            } else if tab.pinnedChannel != nil {
                tab.pinnedChannel = nil
                tab.playbackRate = Settings.defaultPlaybackRate
                applyPlaybackRate(tab.playbackRate, to: tab)
                if tab.id == tabManager.activeTab?.id {
                    toolbar.updatePlaybackRate(tab.playbackRate, pinned: nil)
                }
            }
        }

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

        let currentTime = json["currentTime"] as? Double ?? 0
        let duration = json["duration"] as? Double ?? 0
        if currentTime > 5 && duration > 0 && currentTime < duration - 5,
           let urlStr = webView.url?.absoluteString {
            HistoryManager.shared.savePlaybackPosition(url: urlStr, position: currentTime)
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
                toolbar.updateNowPlaying(title: title, channel: channel)
                toolbar.updateSeekPosition(currentTime: currentTime, duration: duration)
            } else {
                MediaKeyHandler.shared.clearNowPlaying()
                toolbar.clearNowPlaying()
                toolbar.hideSeek()
            }

            if Settings.queueEnabled && ended && QueueManager.shared.hasNext {
                handleVideoEnded()
            }
        }
    }

    // MARK: - Queue

    @objc func toggleQueue() {
        guard Settings.queueEnabled else { return }
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

    // MARK: - TreeTabSidebarDelegate

    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didSelectTab tab: Tab) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabManager.selectTab(at: index)
    }

    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didCloseTab tab: Tab) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabManager.closeTab(at: index)
    }

    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didCloseTabWithChildren tab: Tab) {
        guard let index = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabManager.closeTabWithChildren(at: index)
    }

    func treeTabSidebarDidClose(_ sidebar: TreeTabSidebarView) {}

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
            if tab.pinnedChannel != nil {
                tab.pinnedChannel = nil
                toolbar.updatePlaybackRate(rate, pinned: nil)
            }
            tab.playbackRate = rate
            applyPlaybackRate(rate, to: tab)
            showToast("Speed: \(playbackRateText(rate))x")
        }
    }

    func toolbar(_ toolbar: ToolbarView, didSeekTo fraction: Double) {
        tabManager.activeTab?.webView?.evaluateJavaScript("""
            (function() { const v = document.querySelector('video'); if (v && v.duration) v.currentTime = v.duration * \(fraction); })()
        """)
    }

    func toolbar(_ toolbar: ToolbarView, didChangeVolume volume: Float) {
        tabManager.activeTab?.webView?.evaluateJavaScript(
            "document.querySelector('video').volume = \(volume)"
        )
    }

    func toolbarResetSpeed(_ toolbar: ToolbarView) {
        guard let tab = tabManager.activeTab else { return }
        if tab.pinnedChannel != nil { return }
        let defaultRate = Settings.defaultPlaybackRate
        let rate: Float = (defaultRate != 1.0 && tab.playbackRate != 1.0) ? 1.0 : defaultRate
        tab.playbackRate = rate
        applyPlaybackRate(rate, to: tab)
        toolbar.updatePlaybackRate(rate)
        showToast("Speed: \(playbackRateText(rate))x")
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

    func addressBarBackList(_ bar: AddressBarView) -> [(title: String, url: URL)] {
        guard let list = tabManager.activeTab?.webView?.backForwardList else { return [] }
        return list.backList.reversed().map { ($0.title ?? "", $0.url) }
    }

    func addressBarForwardList(_ bar: AddressBarView) -> [(title: String, url: URL)] {
        guard let list = tabManager.activeTab?.webView?.backForwardList else { return [] }
        return list.forwardList.map { ($0.title ?? "", $0.url) }
    }

    func addressBar(_ bar: AddressBarView, navigateTo url: URL, inNewTab: Bool) {
        if inNewTab {
            if Settings.treeTabsEnabled, let parent = tabManager.activeTab {
                tabManager.addChildTab(url: url, parent: parent, select: true, suspended: false)
            } else {
                tabManager.addTab(url: url)
            }
        } else {
            tabManager.activeTab?.webView?.load(URLRequest(url: url))
        }
    }

    // MARK: - HistoryViewControllerDelegate

    func historyViewController(_ vc: HistoryViewController, didSelectURL url: URL) {
        tabManager.activeTab?.webView?.load(URLRequest(url: url))
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        progressObservation?.invalidate()
        progressFadeWorkItem?.cancel()
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

    @objc func showSettings() {
        let vc = SettingsViewController()
        vc.settingsDelegate = self
        presentAsSheet(vc)
    }

    func settingsDidChange() {}

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

    func shortcutToggleSuspendTab() {
        tabManager.toggleSuspendTab(at: tabManager.selectedIndex)
    }

    func shortcutSuspendOtherTabs() {
        tabManager.suspendOtherTabs()
    }

    func shortcutUnsuspendAllTabs() {
        tabManager.unsuspendAllTabs()
    }

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

    func shortcutTogglePiP() {
        tabManager.activeTab?.webView?.evaluateJavaScript("""
            (function() {
                const v = document.querySelector('video');
                if (!v) return;
                if (document.pictureInPictureElement === v) {
                    document.exitPictureInPicture();
                } else {
                    v.requestPictureInPicture();
                }
            })()
        """)
        showToast("Picture-in-Picture toggled")
    }

    func shortcutTogglePinSpeed() {
        guard let tab = tabManager.activeTab else { return }
        let channel = tab.currentChannel
        guard !channel.isEmpty else {
            showToast("No channel detected")
            return
        }

        if tab.pinnedChannel != nil {
            Settings.removeSpeedForChannel(channel)
            tab.pinnedChannel = nil
            tab.playbackRate = Settings.defaultPlaybackRate
            applyPlaybackRate(tab.playbackRate, to: tab)
            showToast("Speed unpinned for \(channel)")
        } else {
            let rate = tab.playbackRate
            Settings.setSpeedForChannel(channel, speed: rate)
            tab.pinnedChannel = channel
            showToast("📌 \(playbackRateText(rate))× for \(channel)")
        }
        toolbar.updatePlaybackRate(tab.playbackRate, pinned: tab.pinnedChannel)
    }

    func shortcutDownloadVideo() {
        guard let urlStr = tabManager.activeTab?.webView?.url?.absoluteString,
              urlStr.contains("youtube.com/watch") else {
            showToast("Not a video page")
            return
        }
        showToast("Downloading…")
        VideoDownloader.download(url: urlStr) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let path): self?.showToast("Downloaded: \(path)")
                case .failure(let err): self?.showToast("Download failed: \(err.localizedDescription)")
                }
            }
        }
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

    private func updateHandoff(url: URL, title: String) {
        let activity = NSUserActivity(activityType: "com.ytapp.browsing")
        activity.title = title
        activity.webpageURL = url
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        handoffActivity = activity
    }

    private func resumePlaybackIfNeeded(url: URL, webView: WKWebView) {
        guard let position = HistoryManager.shared.getPlaybackPosition(url: url.absoluteString),
              position > 10 else { return }
        let mins = Int(position) / 60
        let secs = Int(position) % 60
        showToast("Resuming at \(mins):\(String(format: "%02d", secs))")
        webView.evaluateJavaScript("""
            (function() {
                function seek() {
                    const v = document.querySelector('video');
                    if (v && v.duration > 0) { v.currentTime = \(position); return true; }
                    return false;
                }
                if (!seek()) {
                    const obs = new MutationObserver(function() { if (seek()) obs.disconnect(); });
                    obs.observe(document.body, { childList: true, subtree: true });
                    setTimeout(function() { obs.disconnect(); }, 10000);
                }
            })()
        """)
    }

    private func tabForWebView(_ webView: WKWebView) -> Tab? {
        tabManager.tabs.first { $0.webView === webView }
    }

    private func observeLoadingProgress(for webView: WKWebView?) {
        progressObservation?.invalidate()
        progressObservation = nil
        progressFadeWorkItem?.cancel()

        guard let webView else {
            loadingProgressBar.alphaValue = 0
            loadingProgressBar.setProgress(0, animated: false)
            return
        }

        progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
            self?.updateLoadingProgress(webView.estimatedProgress)
        }
    }

    private func updateLoadingProgress(_ progress: Double) {
        let clamped = max(0, min(progress, 1))
        progressFadeWorkItem?.cancel()

        if clamped >= 1 {
            loadingProgressBar.alphaValue = 1
            loadingProgressBar.setProgress(1, animated: true)

            let fadeItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    self.loadingProgressBar.animator().alphaValue = 0
                }, completionHandler: {
                    self.loadingProgressBar.setProgress(0, animated: false)
                })
            }

            progressFadeWorkItem = fadeItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: fadeItem)
            return
        }

        guard clamped > 0 else {
            loadingProgressBar.alphaValue = 0
            loadingProgressBar.setProgress(0, animated: false)
            return
        }

        loadingProgressBar.alphaValue = 1
        loadingProgressBar.setProgress(max(clamped, 0.03), animated: true)
    }

    func showToast(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        toastDismissWorkItem?.cancel()
        activeToast?.removeFromSuperview()
        activeToast = nil

        let toast = ToastView(message: trimmed)
        toast.alphaValue = 0
        webViewContainer.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: webViewContainer.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor, constant: -60),
            toast.widthAnchor.constraint(lessThanOrEqualTo: webViewContainer.widthAnchor, constant: -24),
        ])
        activeToast = toast

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toast.animator().alphaValue = 1
        }

        let dismissItem = DispatchWorkItem { [weak self, weak toast] in
            guard let self, let toast, self.activeToast === toast else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                toast.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak toast] in
                guard let self, let toast, self.activeToast === toast else { return }
                toast.removeFromSuperview()
                self.activeToast = nil
            })
        }

        toastDismissWorkItem = dismissItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: dismissItem)
    }

    private func playbackRateText(_ rate: Float) -> String {
        playbackRateFormatter.string(from: NSNumber(value: rate)) ?? String(format: "%.2f", rate)
    }
}

// MARK: - TabBarButton

class TabBarButton: NSView {
    var target: AnyObject?
    var action: Selector?
    var closeTarget: AnyObject?
    var closeAction: Selector?
    weak var contextMenuTarget: MainWindowController?

    private let faviconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let isSelected: Bool
    private let isSuspended: Bool

    private static var faviconCache: NSImage?

    override var tag: Int {
        get { titleLabel.tag }
        set {
            titleLabel.tag = newValue
            closeButton.tag = newValue
        }
    }

    var tabIndex: Int = 0

    init(title: String, index: Int, isSuspended: Bool, isSelected: Bool, isPlaying: Bool, url: URL?) {
        self.isSelected = isSelected
        self.isSuspended = isSuspended
        self.tabIndex = index
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

        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyDown
        faviconView.alphaValue = isSuspended ? 0.4 : 0.8

        if isSuspended {
            faviconView.image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Suspended")
            faviconView.contentTintColor = .secondaryLabelColor
        } else if isPlaying {
            faviconView.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Playing")
            faviconView.contentTintColor = .systemGreen
            faviconView.alphaValue = 1.0
            addPulseAnimation(to: faviconView)
        } else {
            loadFavicon(for: url)
        }

        titleLabel.stringValue = title
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

        addSubview(faviconView)
        addSubview(titleLabel)
        addSubview(closeButton)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            heightAnchor.constraint(equalToConstant: 26),

            faviconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 14),
            faviconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)

        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDragged(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: NSString(string: "\(tabIndex)"))
        item.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func snapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    private func loadFavicon(for url: URL?) {
        if let cached = TabBarButton.faviconCache {
            faviconView.image = cached
            return
        }
        guard let host = url?.host else {
            faviconView.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web")
            faviconView.contentTintColor = .secondaryLabelColor
            return
        }
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")!
        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            TabBarButton.faviconCache = image
            DispatchQueue.main.async { self?.faviconView.image = image }
        }.resume()
    }

    private func addPulseAnimation(to view: NSView) {
        view.wantsLayer = true
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.4
        anim.duration = 0.8
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer?.add(anim, forKey: "pulse")
    }

    @objc private func clicked() {
        _ = target?.perform(action, with: self)
    }

    @objc private func closeClicked() {
        _ = closeTarget?.perform(closeAction, with: closeButton)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let controller = contextMenuTarget else { return }
        let menu = NSMenu()

        let suspendItem = NSMenuItem(
            title: isSuspended ? "Unsuspend Tab" : "Suspend Tab",
            action: #selector(MainWindowController.suspendTabAtIndex(_:)),
            keyEquivalent: ""
        )
        suspendItem.target = controller
        suspendItem.tag = tag
        menu.addItem(suspendItem)

        let suspendOthers = NSMenuItem(
            title: "Suspend Other Tabs",
            action: #selector(MainWindowController.suspendOtherTabsFromIndex(_:)),
            keyEquivalent: ""
        )
        suspendOthers.target = controller
        suspendOthers.tag = tag
        menu.addItem(suspendOthers)

        let unsuspendAll = NSMenuItem(
            title: "Unsuspend All Tabs",
            action: #selector(MainWindowController.unsuspendAllTabs),
            keyEquivalent: ""
        )
        unsuspendAll.target = controller
        menu.addItem(unsuspendAll)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "Close Tab",
            action: #selector(MainWindowController.closeTabFromMenu(_:)),
            keyEquivalent: ""
        )
        closeItem.target = controller
        closeItem.tag = tag
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
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

extension TabBarButton: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
}

extension TabBarButton {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0
        guard let str = sender.draggingPasteboard.string(forType: .string),
              let fromIndex = Int(str) else { return false }
        let toIndex = tabIndex
        guard fromIndex != toIndex else { return false }
        contextMenuTarget?.tabManager.moveTab(from: fromIndex, to: toIndex)
        contextMenuTarget?.rebuildTabBar()
        return true
    }
}

class LoadingProgressBar: NSView {
    private let fillView = NSView(frame: .zero)
    private var fillWidthConstraint: NSLayoutConstraint!
    private var progress: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.wantsLayer = true
        fillView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        addSubview(fillView)

        fillWidthConstraint = fillView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillWidthConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        fillWidthConstraint.constant = bounds.width * progress
    }

    func setProgress(_ value: Double, animated: Bool) {
        progress = max(0, min(value, 1))
        let target = bounds.width * progress

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                fillWidthConstraint.animator().constant = target
                layoutSubtreeIfNeeded()
            }
        } else {
            fillWidthConstraint.constant = target
        }
    }
}

class FindBarView: NSView {
    var onSearch: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    private let textField = NSTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 4

        textField.placeholderString = "Find in page…"
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.bezelStyle = .roundedBezel
        textField.target = self
        textField.action = #selector(search)

        let close = NSButton(title: "✕", target: self, action: #selector(dismiss))
        close.isBordered = false
        close.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        addSubview(close)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func focus() { window?.makeFirstResponder(textField) }

    @objc private func search() {
        let q = textField.stringValue
        guard !q.isEmpty else { return }
        onSearch?(q)
    }

    @objc private func dismiss() { onDismiss?() }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

class NewTabPageView: NSView {
    var onNavigate: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        container.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

        let titleLabel = NSTextField(labelWithString: "New Tab")
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        container.addArrangedSubview(titleLabel)

        let recentHistory = HistoryManager.shared.search(limit: 12)
        if !recentHistory.isEmpty {
            let sectionLabel = NSTextField(labelWithString: "Recent")
            sectionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            sectionLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(sectionLabel)

            let grid = NSStackView()
            grid.orientation = .vertical
            grid.spacing = 2
            grid.translatesAutoresizingMaskIntoConstraints = false

            for entry in recentHistory {
                let row = NewTabRow(title: entry.title ?? "Untitled", subtitle: entry.url)
                row.onTap = { [weak self] in
                    if let url = URL(string: entry.url) { self?.onNavigate?(url) }
                }
                grid.addArrangedSubview(row)
            }
            container.addArrangedSubview(grid)
        }

        let queueItems = QueueManager.shared.items
        if !queueItems.isEmpty {
            let qLabel = NSTextField(labelWithString: "Queue")
            qLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            qLabel.textColor = .secondaryLabelColor
            container.addArrangedSubview(qLabel)

            let qGrid = NSStackView()
            qGrid.orientation = .vertical
            qGrid.spacing = 2

            for item in queueItems.prefix(8) {
                let row = NewTabRow(title: item.title, subtitle: item.channel)
                row.onTap = { [weak self] in self?.onNavigate?(item.watchURL) }
                qGrid.addArrangedSubview(row)
            }
            container.addArrangedSubview(qGrid)
        }

        let goYT = NSButton(title: "Go to YouTube →", target: self, action: #selector(goToYouTube))
        goYT.bezelStyle = .recessed
        goYT.contentTintColor = .controlAccentColor
        container.addArrangedSubview(goYT)

        scrollView.documentView = container
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    @objc private func goToYouTube() {
        onNavigate?(URL(string: "https://www.youtube.com")!)
    }
}

class NewTabRow: NSView {
    var onTap: (() -> Void)?

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = .systemFont(ofSize: 10)
        subField.textColor = .tertiaryLabelColor
        subField.lineBreakMode = .byTruncatingTail
        subField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subField)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            subField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            subField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            subField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onTap?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

class VideoDownloader {
    static func download(url: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["yt-dlp", "-o", "\(downloadsDir)/%(title)s.%(ext)s", "--no-playlist", url]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    let filename = output.components(separatedBy: "\n")
                        .last(where: { $0.contains("Destination:") || $0.contains("has already been downloaded") })?
                        .components(separatedBy: "/").last ?? "video"
                    completion(.success(filename))
                } else {
                    completion(.failure(NSError(domain: "YTApp", code: 1, userInfo: [NSLocalizedDescriptionKey: output])))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
