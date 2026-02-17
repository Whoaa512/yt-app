import Cocoa

protocol AddressBarDelegate: AnyObject {
    func addressBar(_ bar: AddressBarView, didSubmitInput input: String)
    func addressBarGoBack(_ bar: AddressBarView)
    func addressBarGoForward(_ bar: AddressBarView)
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

        forwardButton.bezelStyle = .texturedRounded
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.setContentHuggingPriority(.required, for: .horizontal)

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
}
