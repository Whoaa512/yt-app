import Cocoa
import AVKit
import AVFoundation

protocol OfflinePlayerDelegate: AnyObject {
    func offlinePlayerDidRequestDismiss(_ player: OfflinePlayerView)
}

class OfflinePlayerView: NSView {
    weak var delegate: OfflinePlayerDelegate?

    private let playerView = AVPlayerView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let channelLabel = NSTextField(labelWithString: "")
    private let navLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let backButton = NSButton()
    private let infoBar = NSView()

    private var playlist: [DownloadedVideo] = []
    private var currentIndex = 0
    private var endObserver: Any?

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
        layer?.backgroundColor = NSColor.black.cgColor

        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)

        infoBar.wantsLayer = true
        infoBar.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoBar)

        backButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Back to YouTube")
        backButton.bezelStyle = .recessed
        backButton.isBordered = false
        backButton.contentTintColor = .secondaryLabelColor
        backButton.target = self
        backButton.action = #selector(dismissPlayer)
        backButton.toolTip = "Back to YouTube (Esc)"
        backButton.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(backButton)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(titleLabel)

        channelLabel.font = .systemFont(ofSize: 11)
        channelLabel.textColor = .secondaryLabelColor
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(channelLabel)

        prevButton.image = NSImage(systemSymbolName: "backward.fill", accessibilityDescription: "Previous")
        prevButton.bezelStyle = .recessed
        prevButton.isBordered = false
        prevButton.contentTintColor = .labelColor
        prevButton.target = self
        prevButton.action = #selector(playPrev)
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(prevButton)

        navLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        navLabel.textColor = .tertiaryLabelColor
        navLabel.alignment = .center
        navLabel.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(navLabel)

        nextButton.image = NSImage(systemSymbolName: "forward.fill", accessibilityDescription: "Next")
        nextButton.bezelStyle = .recessed
        nextButton.isBordered = false
        nextButton.contentTintColor = .labelColor
        nextButton.target = self
        nextButton.action = #selector(playNext)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(nextButton)

        NSLayoutConstraint.activate([
            infoBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            infoBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 44),

            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: infoBar.topAnchor),

            backButton.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 10),
            backButton.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: infoBar.topAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -12),

            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.bottomAnchor.constraint(equalTo: infoBar.bottomAnchor, constant: -5),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            nextButton.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -12),
            nextButton.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 24),
            nextButton.heightAnchor.constraint(equalToConstant: 24),

            navLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -6),
            navLabel.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            navLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            prevButton.trailingAnchor.constraint(equalTo: navLabel.leadingAnchor, constant: -6),
            prevButton.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 24),
            prevButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    func play(video: DownloadedVideo, playlist: [DownloadedVideo]) {
        self.playlist = playlist
        self.currentIndex = playlist.firstIndex(where: { $0.id == video.id }) ?? 0
        loadCurrent()
    }

    private func loadCurrent() {
        guard currentIndex >= 0, currentIndex < playlist.count else { return }
        let video = playlist[currentIndex]

        removeEndObserver()

        let url = URL(fileURLWithPath: video.videoPath)
        let item = AVPlayerItem(url: url)

        if let player = playerView.player {
            player.replaceCurrentItem(with: item)
        } else {
            playerView.player = AVPlayer(playerItem: item)
        }

        playerView.player?.play()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            self?.playNext()
        }

        titleLabel.stringValue = video.title
        channelLabel.stringValue = video.channel
        updateNavUI()
    }

    private func updateNavUI() {
        let hasMultiple = playlist.count > 1
        prevButton.isHidden = !hasMultiple
        nextButton.isHidden = !hasMultiple
        navLabel.isHidden = !hasMultiple

        prevButton.isEnabled = currentIndex > 0
        nextButton.isEnabled = currentIndex < playlist.count - 1
        prevButton.alphaValue = prevButton.isEnabled ? 1 : 0.3
        nextButton.alphaValue = nextButton.isEnabled ? 1 : 0.3

        if hasMultiple {
            navLabel.stringValue = "\(currentIndex + 1) / \(playlist.count)"
        }
    }

    @objc private func playNext() {
        guard currentIndex < playlist.count - 1 else { return }
        currentIndex += 1
        loadCurrent()
    }

    @objc private func playPrev() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        loadCurrent()
    }

    @objc private func dismissPlayer() {
        cleanup()
        delegate?.offlinePlayerDidRequestDismiss(self)
    }

    func cleanup() {
        removeEndObserver()
        playerView.player?.pause()
        playerView.player = nil
    }

    private func removeEndObserver() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            dismissPlayer()
        case 124 where event.modifierFlags.contains(.command): // Cmd+Right
            playNext()
        case 123 where event.modifierFlags.contains(.command): // Cmd+Left
            playPrev()
        default:
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    deinit {
        cleanup()
    }
}
