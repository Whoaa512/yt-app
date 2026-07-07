import Cocoa

/// Shared empty-state placeholder: large SF Symbol + title + hint.
final class EmptyStateView: NSView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let hintField = NSTextField(labelWithString: "")

    init(symbol: String, title: String, hint: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 36, weight: .light)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 14, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        titleField.alignment = .center

        hintField.stringValue = hint
        hintField.font = .systemFont(ofSize: 12)
        hintField.textColor = .tertiaryLabelColor
        hintField.alignment = .center
        hintField.maximumNumberOfLines = 0

        let stack = NSStackView(views: [iconView, titleField, hintField])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: iconView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(title: String, hint: String) {
        titleField.stringValue = title
        hintField.stringValue = hint
    }
}
