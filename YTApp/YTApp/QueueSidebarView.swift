import Cocoa

protocol QueueSidebarDelegate: AnyObject {
    func queueSidebar(_ sidebar: QueueSidebarView, didSelectItem item: QueueItem)
    func queueSidebarDidClose(_ sidebar: QueueSidebarView)
}

private let kQueueDragType = NSPasteboard.PasteboardType("com.ytapp.queue-row")

class QueueSidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: QueueSidebarDelegate?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Queue is empty\nRight-click a video → Add to queue")
    private let countLabel = NSTextField(labelWithString: "")

    static let width: CGFloat = 340

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

        // Left edge border
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        // Header
        let headerLabel = NSTextField(labelWithString: "Queue")
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearQueue))
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.contentTintColor = .secondaryLabelColor

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeSidebar))
        closeButton.isBordered = false
        closeButton.bezelStyle = .recessed

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [headerLabel, countLabel, spacer, clearButton, closeButton])
        headerStack.orientation = .horizontal
        headerStack.spacing = 6
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("queue"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 72
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.registerForDraggedTypes([kQueueDragType])
        tableView.draggingDestinationFeedbackStyle = .gap
        tableView.doubleAction = #selector(tableDoubleClick)
        tableView.target = self

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        scrollView.documentView = tableView
        scrollView.contentView.drawsBackground = false
        addSubview(scrollView)

        // Empty state
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 1),

            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])

        reload()
    }

    func reload() {
        let items = QueueManager.shared.items
        emptyLabel.isHidden = !items.isEmpty
        scrollView.isHidden = items.isEmpty
        countLabel.stringValue = items.isEmpty ? "" : "\(items.count) video\(items.count == 1 ? "" : "s")"
        tableView.reloadData()
    }

    @objc private func clearQueue() {
        QueueManager.shared.clear()
        reload()
    }

    @objc private func closeSidebar() {
        delegate?.queueSidebarDidClose(self)
    }

    @objc private func tableDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, let item = QueueManager.shared.playItem(at: row) else { return }
        delegate?.queueSidebar(self, didSelectItem: item)
        reload()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        QueueManager.shared.items.count
    }

    // MARK: - Drag & Drop reorder

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: kQueueDragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .above { return .move }
        return []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let rowStr = item.string(forType: kQueueDragType),
              let from = Int(rowStr) else { return false }
        let to = from < row ? row - 1 : row
        QueueManager.shared.moveItem(from: from, to: to)
        reload()
        return true
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = QueueManager.shared.items
        guard row < items.count else { return nil }
        let item = items[row]
        let isCurrent = row == QueueManager.shared.currentIndex

        let cellId = NSUserInterfaceItemIdentifier("QueueCell")
        let cell: QueueRowCell
        if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? QueueRowCell {
            cell = reused
        } else {
            cell = QueueRowCell()
            cell.identifier = cellId
        }
        cell.configure(item: item, index: row, isCurrent: isCurrent)
        cell.onRemove = { [weak self] idx in
            QueueManager.shared.removeItem(at: idx)
            self?.reload()
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        72
    }
}

// MARK: - Queue Row Cell

class QueueRowCell: NSTableCellView {
    private let thumbView = NSImageView()
    private let durationBadge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let channelLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let indexLabel = NSTextField(labelWithString: "")
    private let removeBtn: NSButton
    private var trackingArea: NSTrackingArea?
    private var currentIndex = 0
    var onRemove: ((Int) -> Void)?

    override init(frame: NSRect) {
        removeBtn = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")!, target: nil, action: nil)
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        wantsLayer = true

        // Thumbnail (16:9 aspect)
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 4
        thumbView.layer?.masksToBounds = true
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false

        // Duration badge on thumbnail
        durationBadge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        durationBadge.textColor = .white
        durationBadge.wantsLayer = true
        durationBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        durationBadge.layer?.cornerRadius = 2
        durationBadge.alignment = .center
        durationBadge.translatesAutoresizingMaskIntoConstraints = false
        durationBadge.isBezeled = false
        durationBadge.drawsBackground = false

        // Index / now-playing indicator
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        indexLabel.alignment = .center
        indexLabel.translatesAutoresizingMaskIntoConstraints = false

        // Title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.cell?.truncatesLastVisibleLine = true

        // Channel
        channelLabel.font = .systemFont(ofSize: 10)
        channelLabel.textColor = .secondaryLabelColor
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.maximumNumberOfLines = 1
        channelLabel.translatesAutoresizingMaskIntoConstraints = false

        // Meta (views · date)
        metaLabel.font = .systemFont(ofSize: 9)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        // Remove button
        removeBtn.target = self
        removeBtn.action = #selector(removeTapped)
        removeBtn.isBordered = false
        removeBtn.contentTintColor = .tertiaryLabelColor
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.isHidden = true
        removeBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        removeBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Layout
        let textStack = NSStackView(views: [titleLabel, channelLabel, metaLabel])
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(indexLabel)
        addSubview(thumbView)
        addSubview(durationBadge)
        addSubview(textStack)
        addSubview(removeBtn)

        let thumbWidth: CGFloat = 80
        let thumbHeight: CGFloat = 45

        NSLayoutConstraint.activate([
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 18),

            thumbView.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 2),
            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: thumbWidth),
            thumbView.heightAnchor.constraint(equalToConstant: thumbHeight),

            durationBadge.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -2),
            durationBadge.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -2),

            textStack.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -4),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 6),

            removeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            removeBtn.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])
    }

    func configure(item: QueueItem, index: Int, isCurrent: Bool) {
        currentIndex = index

        // Index
        if isCurrent {
            indexLabel.stringValue = "▶"
            indexLabel.textColor = .controlAccentColor
            indexLabel.font = .systemFont(ofSize: 10, weight: .bold)
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            indexLabel.stringValue = "\(index + 1)"
            indexLabel.textColor = .tertiaryLabelColor
            indexLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Title
        titleLabel.stringValue = item.title

        // Channel
        channelLabel.stringValue = item.channel
        channelLabel.isHidden = item.channel.isEmpty

        // Meta line: views · date
        var metaParts: [String] = []
        if !item.viewCount.isEmpty { metaParts.append(item.viewCount) }
        if !item.publishedText.isEmpty { metaParts.append(item.publishedText) }
        metaLabel.stringValue = metaParts.joined(separator: " · ")
        metaLabel.isHidden = metaParts.isEmpty
        if !item.publishedText.isEmpty {
            metaLabel.toolTip = item.publishedText
        }

        // Duration badge
        durationBadge.stringValue = " \(item.duration) "
        durationBadge.isHidden = item.duration.isEmpty

        // Thumbnail
        thumbView.image = nil
        if let url = item.thumbnailURL {
            ThumbnailCache.shared.image(for: url) { [weak self] img in
                // Verify still same item
                guard self?.currentIndex == index else { return }
                self?.thumbView.image = img
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        if layer?.backgroundColor == NSColor.clear.cgColor || layer?.backgroundColor == nil {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        }
        removeBtn.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        if layer?.backgroundColor != NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        removeBtn.isHidden = true
    }

    @objc private func removeTapped() {
        onRemove?(currentIndex)
    }
}
