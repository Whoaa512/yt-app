import Cocoa

protocol SettingsDelegate: AnyObject {
    func settingsDidChange()
}

class SettingsViewController: NSViewController {
    weak var settingsDelegate: SettingsDelegate?

    private let queueToggle = NSSwitch()
    private var needsRestart = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        setupLayout()
    }

    private func setupLayout() {
        let titleLabel = NSTextField(labelWithString: "⚙  Settings")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Queue toggle
        let queueRow = makeToggleRow(
            label: "Enable Queue",
            subtitle: "Intercept YouTube queue, sidebar, auto-play next",
            toggle: queueToggle,
            isOn: Settings.queueEnabled,
            action: #selector(queueToggled)
        )

        let restartNote = NSTextField(labelWithString: "")
        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .systemOrange
        restartNote.translatesAutoresizingMaskIntoConstraints = false
        restartNote.tag = 999
        view.addSubview(restartNote)

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnStack = NSStackView(views: [NSView(), closeBtn])
        btnStack.orientation = .horizontal
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            queueRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            queueRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            queueRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            restartNote.topAnchor.constraint(equalTo: queueRow.bottomAnchor, constant: 12),
            restartNote.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private func makeToggleRow(label: String, subtitle: String, toggle: NSSwitch, isOn: Bool, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        toggle.state = isOn ? .on : .off
        toggle.target = self
        toggle.action = action
        toggle.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(subtitleLabel)
        row.addSubview(toggle)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])

        return row
    }

    @objc private func queueToggled() {
        Settings.queueEnabled = queueToggle.state == .on
        needsRestart = true
        if let note = view.viewWithTag(999) as? NSTextField {
            note.stringValue = "Restart app for queue changes to take effect"
        }
        settingsDelegate?.settingsDidChange()
    }

    @objc private func closeSheet() {
        dismiss(nil)
    }
}
