import Cocoa

class SummaryWindowController: NSWindowController {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Video Summary"
        panel.minSize = NSSize(width: 320, height: 400)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(white: 0.08, alpha: 1)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

        let headerLabel = NSTextField(labelWithString: "Summary")
        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closePanel))
        closeButton.isBordered = false
        closeButton.bezelStyle = .recessed

        let copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!, target: self, action: #selector(copyContent))
        copyButton.isBordered = false
        copyButton.bezelStyle = .recessed

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [headerLabel, spacer, copyButton, closeButton])
        headerStack.orientation = .horizontal
        headerStack.spacing = 6
        headerStack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerStack)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        contentView.addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        contentView.addSubview(statusLabel)

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        scrollView.documentView = textView
        scrollView.contentView.drawsBackground = false
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func showLoading(title: String) {
        titleLabel.stringValue = title
        spinner.isHidden = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Summarizing…"
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.isHidden = false
        textView.string = ""
    }

    func showSummary(_ text: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.isHidden = true
        textView.string = text
    }

    func showError(_ message: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        statusLabel.isHidden = false
    }

    @objc private func closePanel() {
        window?.close()
    }

    @objc private func copyContent() {
        let text = textView.string
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
