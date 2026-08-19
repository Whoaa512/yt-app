import Cocoa

protocol SettingsDelegate: AnyObject {
    func settingsDidChange()
}

class SettingsViewController: NSViewController {
    weak var settingsDelegate: SettingsDelegate?

    private let queueToggle = NSSwitch()
    private let treeTabsToggle = NSSwitch()
    private let forceTheaterToggle = NSSwitch()
    private let treeTabsSidePopup = NSPopUpButton()
    private let suspensionPopup = NSPopUpButton()
    private let defaultRatePopup = NSPopUpButton()
    private let downloadQualityPopup = NSPopUpButton()
    private let downloadPathField = NSTextField()
    private let summarizeModelCombo = NSComboBox()
    private let summarizeLengthPopup = NSPopUpButton()
    private let restartNote = NSTextField(labelWithString: "")

    private static let suspensionOptions = [1, 3, 5, 10, 30]
    private static let rateOptions: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    private static let qualityOptions = ["480p", "720p", "1080p", "4k"]
    private static let lengthOptions = ["short", "medium", "long", "xl", "xxl"]

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 360))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        setupLayout()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(nil)
    }

    private func setupLayout() {
        let xBtn = NSButton(title: "\u{2715}", target: self, action: #selector(closeSheet))
        xBtn.bezelStyle = .inline
        xBtn.isBordered = false
        xBtn.font = .systemFont(ofSize: 14, weight: .medium)
        xBtn.contentTintColor = .secondaryLabelColor
        xBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(xBtn)

        let titleLabel = NSTextField(labelWithString: "⚙  Settings")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)

        tabView.addTabViewItem(makeTab(label: "General", views: [
            makeToggleRow(
                label: "Enable Queue",
                subtitle: "Intercept YouTube queue, sidebar, auto-play next",
                toggle: queueToggle,
                isOn: Settings.queueEnabled,
                action: #selector(queueToggled)
            ),
            makeToggleRow(
                label: "Tree Style Tabs",
                subtitle: "Nested tab sidebar, middle-click opens as child",
                toggle: treeTabsToggle,
                isOn: Settings.treeTabsEnabled,
                action: #selector(treeTabsToggled)
            ),
            makePopupRow(
                label: "Tree Tabs Side",
                popup: treeTabsSidePopup,
                titles: ["Right", "Left"],
                selected: Settings.treeTabsSide == .left ? "Left" : "Right",
                action: #selector(treeTabsSideChanged)
            ),
            makePopupRow(
                label: "Suspend Inactive Tabs After",
                popup: suspensionPopup,
                titles: Self.suspensionOptions.map { "\($0) min" },
                selected: "\(Settings.suspensionTimeoutMinutes) min",
                action: #selector(suspensionChanged)
            ),
        ]))

        tabView.addTabViewItem(makeTab(label: "Playback", views: [
            makePopupRow(
                label: "Default Playback Speed",
                popup: defaultRatePopup,
                titles: Self.rateOptions.map { Self.rateTitle($0) },
                selected: Self.rateTitle(Settings.defaultPlaybackRate),
                action: #selector(defaultRateChanged)
            ),
            makeToggleRow(
                label: "Force Theater Mode",
                subtitle: "Always use theater layout on watch pages",
                toggle: forceTheaterToggle,
                isOn: Settings.forceTheaterMode,
                action: #selector(forceTheaterToggled)
            ),
        ]))

        let pathRow = NSView()
        pathRow.translatesAutoresizingMaskIntoConstraints = false
        let pathLabel = NSTextField(labelWithString: "Download Folder")
        pathLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        downloadPathField.stringValue = Settings.downloadPath
        downloadPathField.font = .systemFont(ofSize: 12)
        downloadPathField.target = self
        downloadPathField.action = #selector(downloadPathChanged)
        downloadPathField.delegate = self
        downloadPathField.translatesAutoresizingMaskIntoConstraints = false
        pathRow.addSubview(pathLabel)
        pathRow.addSubview(downloadPathField)
        NSLayoutConstraint.activate([
            pathLabel.topAnchor.constraint(equalTo: pathRow.topAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: pathRow.leadingAnchor),
            downloadPathField.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 6),
            downloadPathField.leadingAnchor.constraint(equalTo: pathRow.leadingAnchor),
            downloadPathField.trailingAnchor.constraint(equalTo: pathRow.trailingAnchor),
            downloadPathField.bottomAnchor.constraint(equalTo: pathRow.bottomAnchor),
        ])

        tabView.addTabViewItem(makeTab(label: "Downloads", views: [
            makePopupRow(
                label: "Download Quality",
                popup: downloadQualityPopup,
                titles: Self.qualityOptions,
                selected: Settings.downloadQuality,
                action: #selector(downloadQualityChanged)
            ),
            pathRow,
        ]))

        let modelRow = NSView()
        modelRow.translatesAutoresizingMaskIntoConstraints = false
        let modelLabel = NSTextField(labelWithString: "Summarize Model")
        modelLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        let modelSubtitle = NSTextField(labelWithString: "Passed to summarize CLI as --model")
        modelSubtitle.font = .systemFont(ofSize: 11)
        modelSubtitle.textColor = .secondaryLabelColor
        modelSubtitle.translatesAutoresizingMaskIntoConstraints = false
        summarizeModelCombo.addItems(withObjectValues: [
            "auto",
            "cli/claude",
            "cli/codex",
            "cli/gemini",
            "anthropic/claude-sonnet-4-5",
            "openai/gpt-5-mini",
            "openai/gpt-5.6-luna",
            "google/gemini-3-flash-preview",
            "xai/grok-4-fast-non-reasoning",
        ])
        summarizeModelCombo.stringValue = Settings.summarizeModel
        summarizeModelCombo.completes = true
        summarizeModelCombo.target = self
        summarizeModelCombo.action = #selector(summarizeModelChanged)
        summarizeModelCombo.delegate = self
        summarizeModelCombo.translatesAutoresizingMaskIntoConstraints = false
        modelRow.addSubview(modelLabel)
        modelRow.addSubview(modelSubtitle)
        modelRow.addSubview(summarizeModelCombo)
        NSLayoutConstraint.activate([
            modelLabel.topAnchor.constraint(equalTo: modelRow.topAnchor),
            modelLabel.leadingAnchor.constraint(equalTo: modelRow.leadingAnchor),
            modelSubtitle.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 2),
            modelSubtitle.leadingAnchor.constraint(equalTo: modelRow.leadingAnchor),
            modelSubtitle.bottomAnchor.constraint(equalTo: modelRow.bottomAnchor),
            summarizeModelCombo.centerYAnchor.constraint(equalTo: modelRow.centerYAnchor),
            summarizeModelCombo.trailingAnchor.constraint(equalTo: modelRow.trailingAnchor),
            summarizeModelCombo.widthAnchor.constraint(equalToConstant: 220),
        ])

        tabView.addTabViewItem(makeTab(label: "AI", views: [
            modelRow,
            makePopupRow(
                label: "Summary Length",
                popup: summarizeLengthPopup,
                titles: Self.lengthOptions,
                selected: Settings.summarizeLength,
                action: #selector(summarizeLengthChanged)
            ),
        ]))

        restartNote.font = .systemFont(ofSize: 11)
        restartNote.textColor = .systemOrange
        restartNote.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(restartNote)

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnStack = NSStackView(views: [NSView(), closeBtn])
        btnStack.orientation = .horizontal
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnStack)

        NSLayoutConstraint.activate([
            xBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            xBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            xBtn.widthAnchor.constraint(equalToConstant: 20),
            xBtn.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tabView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            restartNote.topAnchor.constraint(equalTo: tabView.bottomAnchor, constant: 8),
            restartNote.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            btnStack.topAnchor.constraint(equalTo: restartNote.bottomAnchor, constant: 4),
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    private static func rateTitle(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : "\(rate)x"
    }

    private func makeTab(label: String, views: [NSView]) -> NSTabViewItem {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        for row in views {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }

        let item = NSTabViewItem()
        item.label = label
        item.view = container
        return item
    }

    private func makeToggleRow(label: String, subtitle: String, toggle: NSSwitch, isOn: Bool, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

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

    private func makePopupRow(label: String, popup: NSPopUpButton, titles: [String], selected: String, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        popup.addItems(withTitles: titles)
        popup.selectItem(withTitle: selected)
        if popup.selectedItem == nil { popup.selectItem(at: 0) }
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(titleLabel)
        row.addSubview(popup)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            popup.topAnchor.constraint(equalTo: row.topAnchor),
            popup.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            popup.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])

        return row
    }

    private func showRestartNote(_ text: String) {
        restartNote.stringValue = text
    }

    @objc private func queueToggled() {
        Settings.queueEnabled = queueToggle.state == .on
        showRestartNote("Restart app for queue changes to take effect")
        settingsDelegate?.settingsDidChange()
    }

    @objc private func treeTabsToggled() {
        Settings.treeTabsEnabled = treeTabsToggle.state == .on
        showRestartNote("Restart app for tree tabs changes to take effect")
        settingsDelegate?.settingsDidChange()
    }

    @objc private func treeTabsSideChanged() {
        Settings.treeTabsSide = treeTabsSidePopup.titleOfSelectedItem == "Left" ? .left : .right
        settingsDelegate?.settingsDidChange()
    }

    @objc private func suspensionChanged() {
        let idx = suspensionPopup.indexOfSelectedItem
        guard idx >= 0, idx < Self.suspensionOptions.count else { return }
        Settings.suspensionTimeoutMinutes = Self.suspensionOptions[idx]
        settingsDelegate?.settingsDidChange()
    }

    @objc private func defaultRateChanged() {
        let idx = defaultRatePopup.indexOfSelectedItem
        guard idx >= 0, idx < Self.rateOptions.count else { return }
        Settings.defaultPlaybackRate = Self.rateOptions[idx]
        settingsDelegate?.settingsDidChange()
    }

    @objc private func forceTheaterToggled() {
        Settings.forceTheaterMode = forceTheaterToggle.state == .on
        settingsDelegate?.settingsDidChange()
    }

    @objc private func downloadQualityChanged() {
        guard let title = downloadQualityPopup.titleOfSelectedItem else { return }
        Settings.downloadQuality = title
        settingsDelegate?.settingsDidChange()
    }

    @objc private func downloadPathChanged() {
        let value = downloadPathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        Settings.downloadPath = NSString(string: value).expandingTildeInPath
        settingsDelegate?.settingsDidChange()
    }

    @objc private func summarizeModelChanged() {
        let value = summarizeModelCombo.stringValue.trimmingCharacters(in: .whitespaces)
        Settings.summarizeModel = value.isEmpty ? "auto" : value
    }

    @objc private func summarizeLengthChanged() {
        guard let title = summarizeLengthPopup.titleOfSelectedItem else { return }
        Settings.summarizeLength = title
    }

    @objc private func closeSheet() {
        dismiss(nil)
    }
}

extension SettingsViewController: NSComboBoxDelegate, NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let control = obj.object as? NSControl else { return }
        if control === summarizeModelCombo { summarizeModelChanged() }
        if control === downloadPathField { downloadPathChanged() }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { self.summarizeModelChanged() }
    }
}
