import Cocoa

protocol QueueSidebarDelegate: AnyObject {
    func queueSidebar(_ sidebar: QueueSidebarView, didSelectItem item: QueueItem)
    func queueSidebarDidClose(_ sidebar: QueueSidebarView)
}

class QueueSidebarView: NSView {
    weak var delegate: QueueSidebarDelegate?

    private let headerLabel = NSTextField(labelWithString: "Queue")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let closeButton: NSButton = {
        let btn = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: nil, action: nil)
        btn.isBordered = false
        btn.bezelStyle = .recessed
        return btn
    }()
    private let scrollView = NSScrollView()
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Queue is empty")

    static let width: CGFloat = 300

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
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        clearButton.target = self
        clearButton.action = #selector(clearQueue)
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        closeButton.target = self
        closeButton.action = #selector(closeSidebar)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [headerLabel, NSView(), clearButton, closeButton])
        headerStack.orientation = .horizontal
        headerStack.spacing = 8
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerStack)

        // Scroll view with stack
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        stackView.orientation = .vertical
        stackView.spacing = 1
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = stackView
        scrollView.contentView = clipView
        addSubview(scrollView)

        // Empty label
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center
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

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        reload()
    }

    func reload() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = QueueManager.shared.items
        let currentIndex = QueueManager.shared.currentIndex
        emptyLabel.isHidden = !items.isEmpty

        for (i, item) in items.enumerated() {
            let row = QueueRowView(item: item, index: i, isCurrent: i == currentIndex)
            row.onPlay = { [weak self] idx in
                guard let item = QueueManager.shared.playItem(at: idx) else { return }
                self?.delegate?.queueSidebar(self!, didSelectItem: item)
                self?.reload()
            }
            row.onRemove = { [weak self] idx in
                QueueManager.shared.removeItem(at: idx)
                self?.reload()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        }
    }

    @objc private func clearQueue() {
        QueueManager.shared.clear()
        reload()
    }

    @objc private func closeSidebar() {
        delegate?.queueSidebarDidClose(self)
    }
}

// MARK: - Queue Row

class QueueRowView: NSView {
    var onPlay: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    private let index: Int

    private var trackingArea: NSTrackingArea?
    private let removeButton: NSButton
    private var isHovering = false

    init(item: QueueItem, index: Int, isCurrent: Bool) {
        self.index = index
        self.removeButton = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")!, target: nil, action: nil)
        super.init(frame: .zero)

        wantsLayer = true
        if isCurrent {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }

        let indexLabel = NSTextField(labelWithString: isCurrent ? "▶" : "\(index + 1)")
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: isCurrent ? .bold : .regular)
        indexLabel.textColor = isCurrent ? .controlAccentColor : .tertiaryLabelColor
        indexLabel.alignment = .center
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        indexLabel.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.font = .systemFont(ofSize: 12, weight: isCurrent ? .medium : .regular)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let channelLabel = NSTextField(labelWithString: item.channel)
        channelLabel.font = .systemFont(ofSize: 10)
        channelLabel.textColor = .secondaryLabelColor
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.isHidden = item.channel.isEmpty
        channelLabel.translatesAutoresizingMaskIntoConstraints = false

        let textStack = NSStackView(views: [titleLabel, channelLabel])
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isHidden = true

        let rowStack = NSStackView(views: [indexLabel, textStack, removeButton])
        rowStack.orientation = .horizontal
        rowStack.spacing = 6
        rowStack.alignment = .centerY
        rowStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowClicked))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        if layer?.backgroundColor == nil || layer?.backgroundColor == NSColor.clear.cgColor {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        }
        removeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        // Only clear if not the current item
        if layer?.backgroundColor != NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        removeButton.isHidden = true
    }

    @objc private func rowClicked() {
        onPlay?(index)
    }

    @objc private func removeTapped() {
        onRemove?(index)
    }
}
