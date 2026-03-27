import Cocoa
import WebKit

protocol OfflineLibraryDelegate: AnyObject {
    func offlineLibrary(_ vc: OfflineLibraryViewController, playVideo video: DownloadedVideo)
}

class OfflineLibraryViewController: NSViewController, NSSearchFieldDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    weak var libraryDelegate: OfflineLibraryDelegate?

    private var videos: [DownloadedVideo] = []
    private let searchField = NSSearchField()
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No downloaded videos")
    private let addDirButton = NSButton()
    private let itemIdentifier = NSUserInterfaceItemIdentifier("VideoCell")

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Offline Library"
        setupUI()
        loadVideos()
    }

    private func setupUI() {
        view.wantsLayer = true

        searchField.placeholderString = "Search downloads..."
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        addDirButton.title = "Add Folder"
        addDirButton.bezelStyle = .rounded
        addDirButton.target = self
        addDirButton.action = #selector(addExternalDirectory)
        addDirButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addDirButton)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 220, height: 200)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(VideoCollectionViewItem.self, forItemWithIdentifier: itemIdentifier)
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        view.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: addDirButton.leadingAnchor, constant: -8),

            addDirButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            addDirButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            addDirButton.widthAnchor.constraint(equalToConstant: 100),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func loadVideos(query: String = "") {
        videos = DownloadManager.shared.allVideos(query: query)
        collectionView.reloadData()
        emptyLabel.isHidden = !videos.isEmpty
        scrollView.isHidden = videos.isEmpty
    }

    func controlTextDidChange(_ obj: Notification) {
        loadVideos(query: searchField.stringValue)
    }

    @objc private func addExternalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders containing .mp4 or .webm files"

        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard response == .OK else { return }
            var dirs = Settings.offlineExtraDirectories
            for url in panel.urls {
                let path = url.path
                if !dirs.contains(path) { dirs.append(path) }
            }
            Settings.offlineExtraDirectories = dirs
            self?.loadVideos(query: self?.searchField.stringValue ?? "")
        }
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        videos.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: itemIdentifier, for: indexPath) as! VideoCollectionViewItem
        item.configure(with: videos[indexPath.item])
        item.onPlay = { [weak self] in
            guard let self else { return }
            self.libraryDelegate?.offlineLibrary(self, playVideo: self.videos[indexPath.item])
        }
        item.onDelete = { [weak self] in
            guard let self else { return }
            let video = self.videos[indexPath.item]
            if video.isExternal { return }
            let alert = NSAlert()
            alert.messageText = "Delete \"\(video.title)\"?"
            alert.informativeText = "This will remove the video file (\(video.fileSizeFormatted))."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() == .alertFirstButtonReturn {
                DownloadManager.shared.deleteVideo(video)
                self.loadVideos(query: self.searchField.stringValue)
            }
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first, indexPath.item < videos.count else { return }
        libraryDelegate?.offlineLibrary(self, playVideo: videos[indexPath.item])
        collectionView.deselectItems(at: indexPaths)
    }
}

// MARK: - VideoCollectionViewItem

class VideoCollectionViewItem: NSCollectionViewItem {
    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let channelLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()

    var onPlay: (() -> Void)?
    var onDelete: (() -> Void)?

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 200))
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thumbnailView)

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.wantsLayer = true
        durationLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        durationLabel.layer?.cornerRadius = 3
        durationLabel.alignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(durationLabel)

        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        channelLabel.font = .systemFont(ofSize: 10)
        channelLabel.textColor = .secondaryLabelColor
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(channelLabel)

        sizeLabel.font = .systemFont(ofSize: 9)
        sizeLabel.textColor = .tertiaryLabelColor
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeLabel)

        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
        deleteButton.bezelStyle = .recessed
        deleteButton.isBordered = false
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = true
        view.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            thumbnailView.heightAnchor.constraint(equalToConstant: 124),

            durationLabel.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -4),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -4),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -4),

            sizeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            sizeLabel.centerYAnchor.constraint(equalTo: channelLabel.centerYAnchor),

            deleteButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            deleteButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        let trackingArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        view.addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        deleteButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        deleteButton.isHidden = true
    }

    func configure(with video: DownloadedVideo) {
        titleLabel.stringValue = video.title
        channelLabel.stringValue = video.channel
        sizeLabel.stringValue = video.fileSizeFormatted

        if video.duration > 0 {
            durationLabel.stringValue = " \(video.durationFormatted) "
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        deleteButton.isHidden = true

        if !video.thumbnailPath.isEmpty, FileManager.default.fileExists(atPath: video.thumbnailPath) {
            thumbnailView.image = NSImage(contentsOfFile: video.thumbnailPath)
        } else {
            thumbnailView.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Video")
            thumbnailView.contentTintColor = .tertiaryLabelColor
        }
    }

    @objc private func deleteTapped() {
        onDelete?()
    }
}
