import Cocoa

protocol TranscriptSidebarDelegate: AnyObject {
    func transcriptSidebar(_ sidebar: TranscriptSidebarView, didSelectTime time: Double)
    func transcriptSidebarDidClose(_ sidebar: TranscriptSidebarView)
}

/// Right-edge overlay drawer showing the video transcript with clickable,
/// searchable, auto-following cues.
final class TranscriptSidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let width: CGFloat = 340

    weak var delegate: TranscriptSidebarDelegate?

    private var cues: [TranscriptCue] = []
    private var filtered: [TranscriptCue] = []
    private var activeIndex: Int?
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)

        let title = NSTextField(labelWithString: "Transcript")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeTapped))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor

        let header = NSStackView(views: [title, NSView(), closeButton])
        header.orientation = .horizontal
        header.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search transcript"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.font = .systemFont(ofSize: 12)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.style = .plain
        tableView.usesAutomaticRowHeights = true
        tableView.selectionHighlightStyle = .none
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cue"))
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

        effect.addSubview(header)
        effect.addSubview(searchField)
        effect.addSubview(statusLabel)
        effect.addSubview(scroll)
        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),

            header.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),

            searchField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: effect.centerXAnchor),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public

    func showLoading() {
        cues = []
        filtered = []
        tableView.reloadData()
        statusLabel.stringValue = "Loading transcript…"
        statusLabel.isHidden = false
    }

    func showError(_ message: String) {
        cues = []
        filtered = []
        tableView.reloadData()
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }

    func show(cues: [TranscriptCue]) {
        self.cues = cues
        statusLabel.isHidden = !cues.isEmpty
        if cues.isEmpty { statusLabel.stringValue = "No transcript available" }
        applyFilter()
    }

    /// Highlight + follow the cue playing at `time`. No-op while searching.
    func updateTime(_ time: Double) {
        guard searchField.stringValue.isEmpty else { return }
        let newIndex = TranscriptParser.cueIndex(at: time, in: filtered)
        guard newIndex != activeIndex else { return }
        let old = activeIndex
        activeIndex = newIndex
        var rows = IndexSet()
        if let old { rows.insert(old) }
        if let newIndex { rows.insert(newIndex) }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        if let newIndex { tableView.scrollRowToVisible(newIndex) }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        delegate?.transcriptSidebarDidClose(self)
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        delegate?.transcriptSidebar(self, didSelectTime: filtered[row].start)
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    private func applyFilter() {
        filtered = TranscriptParser.filter(cues: cues, query: searchField.stringValue)
        activeIndex = nil
        tableView.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cue = filtered[row]
        let cell = NSView()

        let time = NSTextField(labelWithString: TranscriptParser.timestamp(cue.start))
        time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        time.textColor = .controlAccentColor
        time.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(wrappingLabelWithString: cue.text)
        text.font = .systemFont(ofSize: 12)
        text.textColor = row == activeIndex ? .labelColor : .secondaryLabelColor
        text.translatesAutoresizingMaskIntoConstraints = false

        if row == activeIndex {
            cell.wantsLayer = true
            cell.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            cell.layer?.cornerRadius = 6
        }

        cell.addSubview(time)
        cell.addSubview(text)
        NSLayoutConstraint.activate([
            time.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            time.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            time.widthAnchor.constraint(equalToConstant: 52),
            text.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
            text.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            text.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3),
        ])
        return cell
    }
}
