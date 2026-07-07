import Cocoa

struct PaletteItem {
    let title: String
    let subtitle: String?
    let symbol: String
    let action: () -> Void
}

/// Cmd+K command palette: floating panel with fuzzy-searchable actions.
final class CommandPaletteController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var panel: KeyablePanel?
    private var searchField: PaletteTextField!
    private var tableView: NSTableView!
    private var items: [PaletteItem] = []
    private var filtered: [FuzzyMatcher.Ranked<PaletteItem>] = []
    private weak var parentWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(over window: NSWindow, items: [PaletteItem]) {
        if isVisible { hide(); return }
        self.items = items
        self.parentWindow = window
        self.filtered = FuzzyMatcher.rank(query: "", items: items, text: { $0.title })

        let panel = buildPanel()
        self.panel = panel

        let w: CGFloat = 560
        let h: CGFloat = 380
        let frame = window.frame
        let x = frame.midX - w / 2
        let y = frame.midY - h / 2 + 60
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)

        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        searchField.stringValue = ""
        tableView.reloadData()
        selectRow(0)

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = panel else { return }
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
    }

    // MARK: - Panel construction

    private func buildPanel() -> KeyablePanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.onEscape = { [weak self] in self?.hide() }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        effect.layer?.masksToBounds = true

        searchField = PaletteTextField()
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 18, weight: .regular)
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Type a command…",
            attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 18)]
        )
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(searchField)
        effect.addSubview(divider)
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            divider.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),
        ])

        panel.contentView = effect
        return panel
    }

    // MARK: - Filtering

    func controlTextDidChange(_ obj: Notification) {
        filtered = FuzzyMatcher.rank(query: searchField.stringValue, items: items, text: { $0.title })
        tableView.reloadData()
        selectRow(0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            selectRow(tableView.selectedRow + 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            selectRow(tableView.selectedRow - 1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            executeSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        default:
            return false
        }
    }

    private func selectRow(_ row: Int) {
        guard !filtered.isEmpty else { return }
        let clamped = max(0, min(row, filtered.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    @objc private func rowClicked() {
        executeSelected()
    }

    private func executeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row].item
        hide()
        item.action()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let ranked = filtered[row]
        let cell = PaletteRowView()
        cell.configure(item: ranked.item, match: ranked.match)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaletteRowBackgroundView()
    }
}

// MARK: - Views

private final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func resignKey() {
        super.resignKey()
        onEscape?()
    }
}

private final class PaletteTextField: NSTextField {}

private final class PaletteRowBackgroundView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 6, dy: 1)
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }
}

private final class PaletteRowView: NSView {
    func configure(item: PaletteItem, match: FuzzyMatcher.Match) {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 16, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithAttributedString: highlighted(item.title, match: match))
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(title)
        var constraints = [
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        if let subtitle = item.subtitle, !subtitle.isEmpty {
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .tertiaryLabelColor
            sub.lineBreakMode = .byTruncatingTail
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(sub)
            constraints.append(contentsOf: [
                sub.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
                sub.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                sub.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            constraints.append(title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func highlighted(_ text: String, match: FuzzyMatcher.Match) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ])
        for range in match.ranges {
            let ns = NSRange(range, in: text)
            attr.addAttributes([
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
            ], range: ns)
        }
        return attr
    }
}
