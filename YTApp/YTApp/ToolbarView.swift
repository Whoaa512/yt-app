import Cocoa

protocol ToolbarDelegate: AnyObject {
    func toolbarGoBack(_ toolbar: ToolbarView)
    func toolbarGoForward(_ toolbar: ToolbarView)
    func toolbarRefresh(_ toolbar: ToolbarView)
    func toolbarPlayPause(_ toolbar: ToolbarView)
    func toolbarPrevTrack(_ toolbar: ToolbarView)
    func toolbarNextTrack(_ toolbar: ToolbarView)
    func toolbar(_ toolbar: ToolbarView, didChangePlaybackRate rate: Float)
    func toolbarResetSpeed(_ toolbar: ToolbarView)
}

class ToolbarView: NSView, NSTextFieldDelegate {
    weak var delegate: ToolbarDelegate?

    let rateField = NSTextField()
    private let rateStepper = NSStepper()
    private var currentRate: Float = 1.0
    private var hoverButtons: [ToolbarButton] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        // Navigation group
        let back = ToolbarButton(symbolName: "chevron.left", tooltip: "Back", target: self, action: #selector(goBack))
        let forward = ToolbarButton(symbolName: "chevron.right", tooltip: "Forward", target: self, action: #selector(goForward))
        let refresh = ToolbarButton(symbolName: "arrow.clockwise", tooltip: "Reload", target: self, action: #selector(doRefresh))

        // Playback group
        let prev = ToolbarButton(symbolName: "backward.fill", tooltip: "Back 10s", target: self, action: #selector(prevTrack))
        let playPause = ToolbarButton(symbolName: "playpause.fill", tooltip: "Play / Pause", target: self, action: #selector(doPlayPause))
        let next = ToolbarButton(symbolName: "forward.fill", tooltip: "Next", target: self, action: #selector(nextTrack))

        hoverButtons = [back, forward, refresh, prev, playPause, next]

        // Rate controls
        let rateLabel = NSTextField(labelWithString: "Speed")
        rateLabel.translatesAutoresizingMaskIntoConstraints = false
        rateLabel.font = .systemFont(ofSize: 10, weight: .medium)
        rateLabel.textColor = .tertiaryLabelColor

        rateField.translatesAutoresizingMaskIntoConstraints = false
        rateField.stringValue = "1.0"
        rateField.alignment = .center
        rateField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        rateField.isBordered = false
        rateField.drawsBackground = false
        rateField.focusRingType = .none
        rateField.target = self
        rateField.action = #selector(rateFieldChanged)
        rateField.delegate = self
        rateField.wantsLayer = true
        rateField.layer?.cornerRadius = 4

        // Rate pill container
        let ratePill = NSView()
        ratePill.wantsLayer = true
        ratePill.layer?.cornerRadius = 6
        ratePill.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        ratePill.translatesAutoresizingMaskIntoConstraints = false

        let rateDown = ToolbarButton(symbolName: "minus", tooltip: "Slower", target: self, action: #selector(rateDown), small: true)
        let rateUp = ToolbarButton(symbolName: "plus", tooltip: "Faster", target: self, action: #selector(rateUp), small: true)
        hoverButtons += [rateDown, rateUp]

        let rateStack = NSStackView(views: [rateDown, rateField, rateUp])
        rateStack.orientation = .horizontal
        rateStack.spacing = 0
        rateStack.alignment = .centerY
        rateStack.translatesAutoresizingMaskIntoConstraints = false

        ratePill.addSubview(rateStack)
        NSLayoutConstraint.activate([
            rateStack.leadingAnchor.constraint(equalTo: ratePill.leadingAnchor, constant: 2),
            rateStack.trailingAnchor.constraint(equalTo: ratePill.trailingAnchor, constant: -2),
            rateStack.topAnchor.constraint(equalTo: ratePill.topAnchor, constant: 1),
            rateStack.bottomAnchor.constraint(equalTo: ratePill.bottomAnchor, constant: -1),
            rateField.widthAnchor.constraint(equalToConstant: 36),
        ])

        // Navigation group
        let navStack = NSStackView(views: [back, forward, refresh])
        navStack.orientation = .horizontal
        navStack.spacing = 2
        navStack.translatesAutoresizingMaskIntoConstraints = false

        // Playback group
        let playStack = NSStackView(views: [prev, playPause, next])
        playStack.orientation = .horizontal
        playStack.spacing = 2
        playStack.translatesAutoresizingMaskIntoConstraints = false

        // Reset to default button
        let resetBtn = makeQuickRateButton(title: "↺", rate: -1)
        resetBtn.toolTip = "Reset to default speed"
        resetBtn.target = self
        resetBtn.action = #selector(resetSpeedTapped)

        // Rate group
        let speedStack = NSStackView(views: [rateLabel, ratePill, resetBtn])
        speedStack.orientation = .horizontal
        speedStack.spacing = 4
        speedStack.alignment = .centerY
        speedStack.translatesAutoresizingMaskIntoConstraints = false

        // Separators
        let sep1 = makeDot()
        let sep2 = makeDot()

        // Center container
        let centerStack = NSStackView(views: [navStack, sep1, playStack, sep2, speedStack])
        centerStack.orientation = .horizontal
        centerStack.spacing = 10
        centerStack.alignment = .centerY
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(centerStack)

        // Bottom hairline
        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            centerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func makeQuickRateButton(title: String, rate: Float) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(quickRateTapped(_:)))
        btn.bezelStyle = .recessed
        btn.isBordered = false
        btn.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 24).isActive = true
        btn.tag = Int(rate * 100)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        return btn
    }

    @objc private func quickRateTapped(_ sender: NSButton) {
        let rate = Float(sender.tag) / 100.0
        currentRate = rate
        rateField.stringValue = formatRate(rate)
        delegate?.toolbar(self, didChangePlaybackRate: rate)
    }

    @objc private func resetSpeedTapped() {
        delegate?.toolbarResetSpeed(self)
    }

    private func makeDot() -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        dot.layer?.cornerRadius = 1.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 3).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 3).isActive = true
        return dot
    }

    func updatePlaybackRate(_ rate: Float) {
        currentRate = rate
        rateField.stringValue = formatRate(rate)
    }

    private func formatRate(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return String(format: "%.0f×", rate)
        }
        return String(format: "%.2g×", rate)
    }

    // MARK: - Actions

    @objc private func goBack() { delegate?.toolbarGoBack(self) }
    @objc private func goForward() { delegate?.toolbarGoForward(self) }
    @objc private func doRefresh() { delegate?.toolbarRefresh(self) }
    @objc private func doPlayPause() { delegate?.toolbarPlayPause(self) }
    @objc private func prevTrack() { delegate?.toolbarPrevTrack(self) }
    @objc private func nextTrack() { delegate?.toolbarNextTrack(self) }

    @objc private func rateDown() {
        let newRate = max(0.25, currentRate - 0.25)
        currentRate = newRate
        rateField.stringValue = formatRate(newRate)
        delegate?.toolbar(self, didChangePlaybackRate: newRate)
    }

    @objc private func rateUp() {
        let newRate = min(4.0, currentRate + 0.25)
        currentRate = newRate
        rateField.stringValue = formatRate(newRate)
        delegate?.toolbar(self, didChangePlaybackRate: newRate)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitRateField()
    }

    @objc private func rateFieldChanged() {
        commitRateField()
    }

    private func commitRateField() {
        let cleaned = rateField.stringValue.replacingOccurrences(of: "×", with: "").trimmingCharacters(in: .whitespaces)
        if let val = Float(cleaned), val >= 0.25, val <= 4.0 {
            currentRate = val
            rateField.stringValue = formatRate(val)
            delegate?.toolbar(self, didChangePlaybackRate: val)
        } else {
            rateField.stringValue = formatRate(currentRate)
        }
    }
}

// MARK: - ToolbarButton

class ToolbarButton: NSView {
    private let imageView = NSImageView()
    private var trackingArea: NSTrackingArea?
    private let isSmall: Bool

    init(symbolName: String, tooltip: String, target: AnyObject, action: Selector, small: Bool = false) {
        self.isSmall = small
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = small ? 4 : 6
        toolTip = tooltip
        translatesAutoresizingMaskIntoConstraints = false

        let size: CGFloat = small ? 10 : 12
        let boxSize: CGFloat = small ? 22 : 28

        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?.withSymbolConfiguration(config)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: boxSize),
            heightAnchor.constraint(equalToConstant: boxSize - 4),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: target, action: action)
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            imageView.contentTintColor = .labelColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            layer?.backgroundColor = NSColor.clear.cgColor
            imageView.contentTintColor = .secondaryLabelColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        super.mouseUp(with: event)
    }
}
