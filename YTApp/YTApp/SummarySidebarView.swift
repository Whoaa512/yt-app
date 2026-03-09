import Cocoa

protocol SummarySidebarDelegate: AnyObject {
    func summarySidebarDidClose(_ sidebar: SummarySidebarView)
}

class SummarySidebarView: NSView {
    weak var delegate: SummarySidebarDelegate?

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let headerLabel = NSTextField(labelWithString: "Summary")
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    static let width: CGFloat = 380

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

        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closeSidebar))
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
        addSubview(headerStack)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        addSubview(statusLabel)

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
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.widthAnchor.constraint(equalToConstant: 1),

            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerStack.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func showLoading(title: String) {
        titleLabel.stringValue = title
        spinner.isHidden = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Summarizing…"
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

    @objc private func closeSidebar() {
        delegate?.summarySidebarDidClose(self)
    }

    @objc private func copyContent() {
        let text = textView.string
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
