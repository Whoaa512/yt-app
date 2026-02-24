import Cocoa

protocol AddressBarDelegate: AnyObject {
    func addressBar(_ bar: AddressBarView, didSubmitInput input: String)
    func addressBarGoBack(_ bar: AddressBarView)
    func addressBarGoForward(_ bar: AddressBarView)
    func addressBarBackList(_ bar: AddressBarView) -> [(title: String, url: URL)]
    func addressBarForwardList(_ bar: AddressBarView) -> [(title: String, url: URL)]
    func addressBar(_ bar: AddressBarView, navigateTo url: URL, inNewTab: Bool)
}

class AddressBarView: NSView {
    weak var delegate: AddressBarDelegate?

    let backButton = NSButton()
    let forwardButton = NSButton()
    let textField = NSTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backButton.bezelStyle = .texturedRounded
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setContentHuggingPriority(.required, for: .horizontal)
        backButton.sendAction(on: [.leftMouseUp])
        setupLongPress(for: backButton, action: #selector(showBackMenu(_:)))

        forwardButton.bezelStyle = .texturedRounded
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.setContentHuggingPriority(.required, for: .horizontal)
        forwardButton.sendAction(on: [.leftMouseUp])
        setupLongPress(for: forwardButton, action: #selector(showForwardMenu(_:)))

        textField.placeholderString = "Search YouTube or enter URL"
        textField.target = self
        textField.action = #selector(textFieldSubmitted)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.cell?.isScrollable = true
        textField.cell?.usesSingleLineMode = true
        textField.bezelStyle = .roundedBezel

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(textField)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 30),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 30),

            textField.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setURL(_ url: URL?) {
        textField.stringValue = url?.absoluteString ?? ""
    }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    @objc private func textFieldSubmitted() {
        let input = textField.stringValue
        guard !input.isEmpty else { return }
        delegate?.addressBar(self, didSubmitInput: input)
    }

    @objc private func goBack() {
        delegate?.addressBarGoBack(self)
    }

    @objc private func goForward() {
        delegate?.addressBarGoForward(self)
    }

    private func setupLongPress(for button: NSButton, action: Selector) {
        let press = NSPressGestureRecognizer(target: self, action: action)
        press.minimumPressDuration = 0.3
        press.buttonMask = 0x1
        button.addGestureRecognizer(press)
    }

    override func rightMouseDown(with event: NSEvent) {
        let backLoc = backButton.convert(event.locationInWindow, from: nil)
        if backButton.bounds.contains(backLoc) {
            let items = delegate?.addressBarBackList(self) ?? []
            showHistoryMenu(items: items, from: backButton)
            return
        }
        let fwdLoc = forwardButton.convert(event.locationInWindow, from: nil)
        if forwardButton.bounds.contains(fwdLoc) {
            let items = delegate?.addressBarForwardList(self) ?? []
            showHistoryMenu(items: items, from: forwardButton)
            return
        }
        super.rightMouseDown(with: event)
    }

    @objc private func showBackMenu(_ sender: NSPressGestureRecognizer) {
        guard sender.state == .began else { return }
        let items = delegate?.addressBarBackList(self) ?? []
        showHistoryMenu(items: items, from: backButton)
    }

    @objc private func showForwardMenu(_ sender: NSPressGestureRecognizer) {
        guard sender.state == .began else { return }
        let items = delegate?.addressBarForwardList(self) ?? []
        showHistoryMenu(items: items, from: forwardButton)
    }

    private func showHistoryMenu(items: [(title: String, url: URL)], from button: NSButton) {
        guard !items.isEmpty else { return }
        let menu = NSMenu()
        for (i, entry) in items.enumerated() {
            let title = entry.title.isEmpty ? entry.url.absoluteString : entry.title
            let truncated = title.count > 60 ? String(title.prefix(57)) + "…" : title
            let item = NSMenuItem(title: truncated, action: #selector(historyMenuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.representedObject = entry.url
            item.toolTip = entry.url.absoluteString
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: button.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func historyMenuItemClicked(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let event = NSApp.currentEvent
        let newTab = event?.modifierFlags.contains(.command) == true
        delegate?.addressBar(self, navigateTo: url, inNewTab: newTab)
    }
}
