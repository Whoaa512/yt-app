import Cocoa

protocol PluginSettingsDelegate: AnyObject {
    func pluginSettingsDidChange()
    func pluginSettingsOpenPluginDir()
}

/// Plugin management panel — enable/disable, view info, open plugin directory.
class PluginSettingsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var settingsDelegate: PluginSettingsDelegate?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var plugins: [LoadedPlugin] { PluginManager.shared.plugins }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Plugins"
        setupLayout()
    }

    private func setupLayout() {
        let titleLabel = NSTextField(labelWithString: "🔌  Plugins")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "Place plugins in ~/.ytapp/plugins/  •  Auto-reloads on file changes")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitle)

        // Table
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        view.addSubview(scrollView)

        let enabledCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledCol.title = ""
        enabledCol.width = 30
        tableView.addTableColumn(enabledCol)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Plugin"
        nameCol.width = 150
        tableView.addTableColumn(nameCol)

        let descCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("desc"))
        descCol.title = "Description"
        descCol.width = 220
        tableView.addTableColumn(descCol)

        let versionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("version"))
        versionCol.title = "Version"
        versionCol.width = 50
        tableView.addTableColumn(versionCol)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 28
        tableView.headerView?.frame.size.height = 24

        // Buttons
        let openDirBtn = NSButton(title: "Open Plugin Folder", target: self, action: #selector(openDir))
        openDirBtn.bezelStyle = .texturedRounded
        openDirBtn.translatesAutoresizingMaskIntoConstraints = false

        let reloadBtn = NSButton(title: "Reload", target: self, action: #selector(reloadPlugins))
        reloadBtn.bezelStyle = .texturedRounded
        reloadBtn.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let btnStack = NSStackView(views: [openDirBtn, reloadBtn, NSView(), closeBtn])
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btnStack)

        // Empty state
        if plugins.isEmpty {
            let empty = NSTextField(labelWithString: "No plugins installed.\n\nCreate a folder in ~/.ytapp/plugins/ with a manifest.json to get started.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            empty.alignment = .center
            empty.maximumNumberOfLines = 5
            empty.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                empty.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
                empty.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            ])
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            scrollView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            btnStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        plugins.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < plugins.count else { return nil }
        let plugin = plugins[row]
        let colId = tableColumn?.identifier.rawValue ?? ""

        switch colId {
        case "enabled":
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            check.state = plugin.enabled ? .on : .off
            check.tag = row
            return check

        case "name":
            let label = NSTextField(labelWithString: plugin.manifest.name)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            return label

        case "desc":
            let label = NSTextField(labelWithString: plugin.manifest.description ?? "")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            return label

        case "version":
            let label = NSTextField(labelWithString: plugin.manifest.version ?? "")
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .tertiaryLabelColor
            return label

        default:
            return nil
        }
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard row < plugins.count else { return }
        let newState = sender.state == .on
        PluginManager.shared.setEnabled(newState, pluginId: plugins[row].id)
        settingsDelegate?.pluginSettingsDidChange()
    }

    @objc private func openDir() {
        let dir = PluginManager.pluginDirectories.first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func reloadPlugins() {
        PluginManager.shared.reload()
        tableView.reloadData()
        settingsDelegate?.pluginSettingsDidChange()
    }

    @objc private func closeSheet() {
        dismiss(nil)
    }
}
