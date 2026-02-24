import Cocoa

class SuspendedTabOverlay: NSView {
    var onUnsuspend: (() -> Void)?

    init(title: String, url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1.0).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSTextField(labelWithString: "💤")
        icon.font = .systemFont(ofSize: 48)
        icon.alignment = .center

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail

        let urlLabel = NSTextField(labelWithString: url.absoluteString)
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.alignment = .center
        urlLabel.lineBreakMode = .byTruncatingMiddle

        let button = NSButton(title: "Unsuspend Tab", target: self, action: #selector(unsuspendClicked))
        button.bezelStyle = .rounded
        button.controlSize = .large

        let hint = NSTextField(labelWithString: "Click here or press gs to unsuspend")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(urlLabel)
        stack.addArrangedSubview(button)
        stack.addArrangedSubview(hint)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func unsuspendClicked() {
        onUnsuspend?()
    }
}
