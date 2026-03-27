import Cocoa

protocol OfflineLibraryViewDelegate: AnyObject {
    func offlineLibraryDidSelectVideo(_ view: OfflineLibraryView, video: DownloadedVideo)
    func offlineLibraryDidRequestDismiss(_ view: OfflineLibraryView)
    func offlineLibraryDidRequestAddFolder(_ view: OfflineLibraryView)
}

class OfflineLibraryView: NSView, NSSearchFieldDelegate {
    weak var delegate: OfflineLibraryViewDelegate?

    private var videos: [DownloadedVideo] = []
    private let scrollView = NSScrollView()
    private let gridContainer = NSView()
    private let searchField = NSSearchField()
    private let headerLabel = NSTextField(labelWithString: "Offline Library")
    private let countLabel = NSTextField(labelWithString: "")
    private let addFolderButton = NSButton()
    private let backButton = NSButton()
    private let emptyState = NSView()
    private var cardViews: [VideoCardView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor

        let topBar = NSView()
        topBar.wantsLayer = true
        topBar.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        topBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.bezelStyle = .recessed
        backButton.isBordered = false
        backButton.contentTintColor = .secondaryLabelColor
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.toolTip = "Back to YouTube (Esc)"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backButton)

        headerLabel.font = .systemFont(ofSize: 18, weight: .bold)
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(headerLabel)

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(countLabel)

        searchField.placeholderString = "Search offline videos..."
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(searchField)

        addFolderButton.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Folder")
        addFolderButton.bezelStyle = .recessed
        addFolderButton.isBordered = false
        addFolderButton.contentTintColor = .secondaryLabelColor
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolder)
        addFolderButton.toolTip = "Add external video folder"
        addFolderButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(addFolderButton)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        addSubview(scrollView)

        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = gridContainer

        setupEmptyState()

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 52),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            headerLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            headerLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            searchField.trailingAnchor.constraint(equalTo: addFolderButton.leadingAnchor, constant: -8),
            searchField.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 220),

            addFolderButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            addFolderButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            addFolderButton.widthAnchor.constraint(equalToConstant: 28),
            addFolderButton.heightAnchor.constraint(equalToConstant: 28),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        gridContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        addSubview(emptyState)

        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)!)
        icon.contentTintColor = .tertiaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .ultraLight)
        icon.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(icon)

        let label = NSTextField(labelWithString: "No offline videos yet")
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(label)

        let hint = NSTextField(labelWithString: "Download videos with ⌘D or right-click → Download")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(hint)

        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyState.widthAnchor.constraint(equalToConstant: 300),
            emptyState.heightAnchor.constraint(equalToConstant: 120),

            icon.topAnchor.constraint(equalTo: emptyState.topAnchor),
            icon.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),

            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),

            hint.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            hint.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
        ])
    }

    func reload(query: String = "") {
        videos = DownloadManager.shared.allVideos(query: query)
        emptyState.isHidden = !videos.isEmpty
        scrollView.isHidden = videos.isEmpty
        countLabel.stringValue = videos.isEmpty ? "" : "\(videos.count) video\(videos.count == 1 ? "" : "s")"
        layoutGrid()
    }

    private func layoutGrid() {
        for card in cardViews { card.removeFromSuperview() }
        cardViews.removeAll()

        let padding: CGFloat = 20
        let spacing: CGFloat = 16
        let availableWidth = max(bounds.width - padding * 2, 400)
        let cardWidth: CGFloat = 320
        let columns = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))
        let actualCardWidth = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let thumbHeight = actualCardWidth * 9 / 16
        let cardHeight = thumbHeight + 68

        for (i, video) in videos.enumerated() {
            let col = i % columns
            let row = i / columns
            let x = padding + CGFloat(col) * (actualCardWidth + spacing)
            let y = padding + CGFloat(row) * (cardHeight + spacing)

            let card = VideoCardView(frame: NSRect(x: x, y: y, width: actualCardWidth, height: cardHeight))
            card.configure(with: video)
            card.onSelect = { [weak self] in
                guard let self else { return }
                self.delegate?.offlineLibraryDidSelectVideo(self, video: video)
            }
            card.onDelete = { [weak self] in
                guard let self else { return }
                self.confirmDelete(video)
            }
            gridContainer.addSubview(card)
            cardViews.append(card)
        }

        let rows = videos.isEmpty ? 0 : (videos.count - 1) / columns + 1
        let totalHeight = padding * 2 + CGFloat(rows) * (cardHeight + spacing) - (rows > 0 ? spacing : 0)
        gridContainer.frame = NSRect(x: 0, y: 0, width: availableWidth + padding * 2, height: totalHeight)
    }

    override func layout() {
        super.layout()
        layoutGrid()
    }

    private func confirmDelete(_ video: DownloadedVideo) {
        guard !video.isExternal else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(video.title)\"?"
        alert.informativeText = "This will remove the video file (\(video.fileSizeFormatted))."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DownloadManager.shared.deleteVideo(video)
        reload(query: searchField.stringValue)
    }

    func controlTextDidChange(_ obj: Notification) {
        reload(query: searchField.stringValue)
    }

    @objc private func goBack() {
        delegate?.offlineLibraryDidRequestDismiss(self)
    }

    @objc private func addFolder() {
        delegate?.offlineLibraryDidRequestAddFolder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            goBack()
            return
        }
        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - VideoCardView

class VideoCardView: NSView {
    var onSelect: (() -> Void)?
    var onDelete: (() -> Void)?

    private let thumbnailView = NSImageView()
    private let durationBadge = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let channelLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private var isExternal = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.clear.cgColor

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 10
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        durationBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        durationBadge.textColor = .white
        durationBadge.wantsLayer = true
        durationBadge.layer?.backgroundColor = NSColor(white: 0, alpha: 0.8).cgColor
        durationBadge.layer?.cornerRadius = 4
        durationBadge.alignment = .center
        durationBadge.translatesAutoresizingMaskIntoConstraints = false
        durationBadge.isHidden = true
        addSubview(durationBadge)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        channelLabel.font = .systemFont(ofSize: 11)
        channelLabel.textColor = .secondaryLabelColor
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(channelLabel)

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metaLabel)

        deleteButton.image = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Delete")
        deleteButton.bezelStyle = .recessed
        deleteButton.isBordered = false
        deleteButton.contentTintColor = NSColor(white: 1, alpha: 0.7)
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        addSubview(deleteButton)

        let thumbHeight = frame.width * 9 / 16

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: thumbHeight),

            durationBadge.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -6),
            durationBadge.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -6),
            durationBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 38),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: metaLabel.leadingAnchor, constant: -8),

            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            metaLabel.centerYAnchor.constraint(equalTo: channelLabel.centerYAnchor),

            deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(trackingArea)
    }

    func configure(with video: DownloadedVideo) {
        titleLabel.stringValue = video.title
        channelLabel.stringValue = video.channel
        isExternal = video.isExternal

        var meta: [String] = []
        if video.fileSize > 0 { meta.append(video.fileSizeFormatted) }
        metaLabel.stringValue = meta.joined(separator: " · ")

        if video.duration > 0 {
            durationBadge.stringValue = " \(video.durationFormatted) "
            durationBadge.isHidden = false
        } else {
            durationBadge.isHidden = true
        }

        if !video.thumbnailPath.isEmpty, FileManager.default.fileExists(atPath: video.thumbnailPath) {
            thumbnailView.image = NSImage(contentsOfFile: video.thumbnailPath)
        } else {
            thumbnailView.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Video")
            thumbnailView.contentTintColor = .tertiaryLabelColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        if !isExternal { deleteButton.isHidden = false }
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        deleteButton.isHidden = true
    }

    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.contains(loc) else { return }
        if !deleteButton.isHidden && deleteButton.frame.contains(loc) { return }
        onSelect?()
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}
