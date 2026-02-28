import Cocoa

protocol TreeTabSidebarDelegate: AnyObject {
    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didSelectTab tab: Tab)
    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didCloseTab tab: Tab)
    func treeTabSidebar(_ sidebar: TreeTabSidebarView, didCloseTabWithChildren tab: Tab)
    func treeTabSidebarDidClose(_ sidebar: TreeTabSidebarView)
}

class TreeTabSidebarView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    weak var delegate: TreeTabSidebarDelegate?
    weak var tabManager: TabManager?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()

    static let width: CGFloat = 240

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowHeight = 28
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.target = self
        outlineView.action = #selector(rowClicked)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = outlineView
        scrollView.contentView.drawsBackground = false
        addSubview(scrollView)

        // Border constraint depends on side — will be updated by updateBorderSide
        self.borderView = border
        self.borderLeading = border.leadingAnchor.constraint(equalTo: leadingAnchor)
        self.borderTrailing = border.trailingAnchor.constraint(equalTo: trailingAnchor)

        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateBorderSide()
    }

    private var borderView: NSView!
    private var borderLeading: NSLayoutConstraint!
    private var borderTrailing: NSLayoutConstraint!

    func updateBorderSide() {
        borderLeading.isActive = false
        borderTrailing.isActive = false
        if Settings.treeTabsSide == .left {
            borderTrailing.isActive = true
        } else {
            borderLeading.isActive = true
        }
    }

    func reload() {
        let selectedTab = tabManager?.activeTab
        outlineView.reloadData()

        // Expand all items
        guard let tm = tabManager else { return }
        for tab in tm.rootTabs {
            outlineView.expandItem(tab, expandChildren: true)
        }

        // Restore selection
        if let sel = selectedTab {
            let row = outlineView.row(forItem: sel)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let tab = outlineView.item(atRow: row) as? Tab else { return }
        delegate?.treeTabSidebar(self, didSelectTab: tab)
    }

    // MARK: - Context Menu

    func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu? { nil }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return tabManager?.rootTabs.count ?? 0
        }
        return (item as? Tab)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return tabManager?.rootTabs[index] as Any
        }
        return (item as! Tab).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let tab = item as? Tab else { return false }
        return !tab.children.isEmpty
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let tab = item as? Tab else { return nil }

        let cellId = NSUserInterfaceItemIdentifier("TreeTabCell")
        let cell: TreeTabCellView
        if let reused = outlineView.makeView(withIdentifier: cellId, owner: nil) as? TreeTabCellView {
            cell = reused
        } else {
            cell = TreeTabCellView()
            cell.identifier = cellId
        }

        let isSelected = tab.id == tabManager?.activeTab?.id
        cell.configure(tab: tab, isSelected: isSelected)
        cell.onClose = { [weak self] in
            guard let self else { return }
            self.delegate?.treeTabSidebar(self, didCloseTab: tab)
        }
        cell.onContextMenu = { [weak self] event in
            guard let self else { return }
            self.showContextMenu(for: tab, event: event)
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        28
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let tab = outlineView.item(atRow: row) as? Tab else { return }
        delegate?.treeTabSidebar(self, didSelectTab: tab)
    }

    private func showContextMenu(for tab: Tab, event: NSEvent) {
        let menu = NSMenu()

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(contextClose(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = tab
        menu.addItem(closeItem)

        if !tab.children.isEmpty {
            let closeTree = NSMenuItem(title: "Close Tab & Children", action: #selector(contextCloseTree(_:)), keyEquivalent: "")
            closeTree.target = self
            closeTree.representedObject = tab
            menu.addItem(closeTree)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextClose(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        delegate?.treeTabSidebar(self, didCloseTab: tab)
    }

    @objc private func contextCloseTree(_ sender: NSMenuItem) {
        guard let tab = sender.representedObject as? Tab else { return }
        delegate?.treeTabSidebar(self, didCloseTabWithChildren: tab)
    }
}

// MARK: - TreeTabCellView

class TreeTabCellView: NSTableCellView {
    private let faviconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?
    var onClose: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 4

        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.bezelStyle = .inline
        closeButton.title = "×"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 12, weight: .bold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.alphaValue = 0
        closeButton.target = self
        closeButton.action = #selector(closeTapped)

        addSubview(faviconView)
        addSubview(titleLabel)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            faviconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            faviconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 14),
            faviconView.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(tab: Tab, isSelected: Bool) {
        titleLabel.stringValue = tab.title

        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            titleLabel.textColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = .secondaryLabelColor
        }

        if tab.isSuspended {
            faviconView.image = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Suspended")
            faviconView.contentTintColor = .tertiaryLabelColor
            faviconView.alphaValue = 0.5
            titleLabel.alphaValue = 0.5
        } else if tab.isPlayingMedia {
            faviconView.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Playing")
            faviconView.contentTintColor = .systemGreen
            faviconView.alphaValue = 1.0
            titleLabel.alphaValue = 1.0
        } else {
            faviconView.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Web")
            faviconView.contentTintColor = .secondaryLabelColor
            faviconView.alphaValue = 0.8
            titleLabel.alphaValue = 1.0
        }
    }

    @objc private func closeTapped() {
        onClose?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.alphaValue = 1.0
        if layer?.backgroundColor == NSColor.clear.cgColor {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0
        if layer?.backgroundColor != NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
