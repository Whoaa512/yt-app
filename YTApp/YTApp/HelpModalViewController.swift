import Cocoa

protocol HelpModalDelegate: AnyObject {
    func helpModalDidRequestElementPicker()
}

/// Keyboard shortcuts help + custom macro editor, presented as a sheet.
class HelpModalViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var helpDelegate: HelpModalDelegate?
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var sections: [(title: String, rows: [(key: String, label: String)])] = []
    private let macroTable = NSTableView()
    private let macroScroll = NSScrollView()

    // Macro creation fields
    private let keyField = NSTextField()
    private let nameField = NSTextField()
    private let actionTypePopup = NSPopUpButton()
    private let actionValueField = NSTextField()
    private let urlPatternField = NSTextField()
    private let pickButton: NSButton = NSButton()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 520))
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Keyboard Shortcuts"
        buildSections()
        setupLayout()
    }

    private func buildSections() {
        sections = []
        var cats: [String: [(key: String, label: String)]] = [:]
        let order = ["Navigation", "Tabs", "Link Hints", "Playback", "Panels", "Other"]
        for s in KeyboardShortcutHandler.builtInShortcuts {
            cats[s.category, default: []].append((s.key, s.label))
        }
        for cat in order {
            if let rows = cats[cat] { sections.append((cat, rows)) }
        }
        // Add macros section
        let macros = CustomMacroManager.shared.macros
        if !macros.isEmpty {
            sections.append(("Custom Macros", macros.map { ($0.key, "\($0.name) — \($0.action.typeLabel): \($0.action.value)") }))
        }
    }

    private func setupLayout() {
        let container = view

        // Title
        let titleLabel = NSTextField(labelWithString: "⌨️  Keyboard Shortcuts")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let subtitle = NSTextField(labelWithString: "Shortcuts are active when the page (not a text field) has focus")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitle)

        // Shortcuts list
        let shortcutsView = buildShortcutsView()
        shortcutsView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shortcutsView)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        // Macro editor section
        let macroLabel = NSTextField(labelWithString: "Custom Macros")
        macroLabel.font = .systemFont(ofSize: 14, weight: .medium)
        macroLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(macroLabel)

        let macroForm = buildMacroForm()
        macroForm.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(macroForm)

        // Macro list
        macroScroll.translatesAutoresizingMaskIntoConstraints = false
        macroScroll.documentView = macroTable
        macroScroll.hasVerticalScroller = true
        macroScroll.borderType = .bezelBorder
        setupMacroTable()
        container.addSubview(macroScroll)

        // Close button
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        closeBtn.keyEquivalent = "\u{1b}" // Escape
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            shortcutsView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 10),
            shortcutsView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            shortcutsView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            shortcutsView.heightAnchor.constraint(equalToConstant: 200),

            divider.topAnchor.constraint(equalTo: shortcutsView.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            macroLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            macroLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            macroForm.topAnchor.constraint(equalTo: macroLabel.bottomAnchor, constant: 6),
            macroForm.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            macroForm.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            macroScroll.topAnchor.constraint(equalTo: macroForm.bottomAnchor, constant: 8),
            macroScroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            macroScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            macroScroll.heightAnchor.constraint(equalToConstant: 80),

            closeBtn.topAnchor.constraint(equalTo: macroScroll.bottomAnchor, constant: 10),
            closeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            closeBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
    }

    private func buildShortcutsView() -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.borderType = .noBorder

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        for section in sections {
            let header = NSTextField(labelWithString: section.title.uppercased())
            header.font = .systemFont(ofSize: 10, weight: .bold)
            header.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(header)
            // Spacing after header
            stack.setCustomSpacing(4, after: header)

            for row in section.rows {
                let rowView = makeShortcutRow(key: row.key, label: row.label)
                stack.addArrangedSubview(rowView)
            }
            // Section spacing
            if let last = stack.arrangedSubviews.last {
                stack.setCustomSpacing(10, after: last)
            }
        }

        let clip = NSView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: clip.bottomAnchor),
        ])
        sv.documentView = clip
        // Make clip at least as wide as scroll view
        clip.widthAnchor.constraint(greaterThanOrEqualTo: sv.widthAnchor).isActive = true

        return sv
    }

    private func makeShortcutRow(key: String, label: String) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let keyBadge = NSTextField(labelWithString: key)
        keyBadge.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyBadge.textColor = .controlAccentColor
        keyBadge.wantsLayer = true
        keyBadge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        keyBadge.layer?.cornerRadius = 4
        keyBadge.alignment = .center
        keyBadge.translatesAutoresizingMaskIntoConstraints = false

        let desc = NSTextField(labelWithString: label)
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .labelColor
        desc.translatesAutoresizingMaskIntoConstraints = false
        desc.lineBreakMode = .byTruncatingTail

        row.addSubview(keyBadge)
        row.addSubview(desc)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 22),
            keyBadge.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            keyBadge.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            keyBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            desc.leadingAnchor.constraint(equalTo: keyBadge.trailingAnchor, constant: 12),
            desc.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            desc.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            row.widthAnchor.constraint(equalToConstant: 480),
        ])
        return row
    }

    // MARK: - Macro Form

    private func buildMacroForm() -> NSView {
        let grid = NSView()

        func label(_ text: String) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.translatesAutoresizingMaskIntoConstraints = false
            return l
        }

        let keyLabel = label("Key")
        let nameLabel = label("Name")
        let typeLabel = label("Type")
        let valueLabel = label("Value")
        let patternLabel = label("URL filter")

        keyField.placeholderString = "e.g. s"
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        nameField.placeholderString = "Subscribe button"
        nameField.translatesAutoresizingMaskIntoConstraints = false

        actionTypePopup.addItems(withTitles: ["Click Selector", "Evaluate JS", "Navigate URL"])
        actionTypePopup.translatesAutoresizingMaskIntoConstraints = false
        actionTypePopup.controlSize = .small

        actionValueField.placeholderString = "#subscribe-button button"
        actionValueField.translatesAutoresizingMaskIntoConstraints = false

        urlPatternField.placeholderString = "optional, e.g. youtube.com/watch"
        urlPatternField.translatesAutoresizingMaskIntoConstraints = false

        pickButton.title = "🎯 Pick Element"
        pickButton.bezelStyle = .texturedRounded
        pickButton.controlSize = .small
        pickButton.target = self
        pickButton.action = #selector(startPick)
        pickButton.translatesAutoresizingMaskIntoConstraints = false

        let addBtn = NSButton(title: "Add Macro", target: self, action: #selector(addMacro))
        addBtn.bezelStyle = .texturedRounded
        addBtn.controlSize = .small
        addBtn.translatesAutoresizingMaskIntoConstraints = false

        // Row 1: key, name
        let row1 = NSStackView(views: [keyLabel, keyField, nameLabel, nameField])
        row1.orientation = .horizontal; row1.spacing = 6
        row1.translatesAutoresizingMaskIntoConstraints = false

        // Row 2: type, value, pick
        let row2 = NSStackView(views: [typeLabel, actionTypePopup, valueLabel, actionValueField, pickButton])
        row2.orientation = .horizontal; row2.spacing = 6
        row2.translatesAutoresizingMaskIntoConstraints = false

        // Row 3: url pattern, add
        let row3 = NSStackView(views: [patternLabel, urlPatternField, addBtn])
        row3.orientation = .horizontal; row3.spacing = 6
        row3.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [row1, row2, row3])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        grid.addSubview(stack)
        grid.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: grid.topAnchor),
            stack.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: grid.bottomAnchor),
            keyField.widthAnchor.constraint(equalToConstant: 50),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            actionValueField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            urlPatternField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        return grid
    }

    @objc private func addMacro() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespaces)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let value = actionValueField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else {
            NSSound.beep()
            return
        }

        let action: MacroAction
        switch actionTypePopup.indexOfSelectedItem {
        case 0:  action = .clickSelector(value)
        case 1:  action = .evaluateJS(value)
        case 2:  action = .navigate(value)
        default: action = .clickSelector(value)
        }

        let pattern = urlPatternField.stringValue.trimmingCharacters(in: .whitespaces)
        let macro = UserMacro(key: key, name: name.isEmpty ? value : name, action: action, urlPattern: pattern.isEmpty ? nil : pattern)
        CustomMacroManager.shared.add(macro)

        // Clear fields
        keyField.stringValue = ""
        nameField.stringValue = ""
        actionValueField.stringValue = ""
        urlPatternField.stringValue = ""

        macroTable.reloadData()
        buildSections()
    }

    @objc private func startPick() {
        // Dismiss sheet temporarily, start element picker
        helpDelegate?.helpModalDidRequestElementPicker()
    }

    /// Called from MainWindowController when element picker returns a selector.
    func didPickElement(selector: String) {
        if !selector.isEmpty {
            actionValueField.stringValue = selector
            actionTypePopup.selectItem(at: 0) // Click Selector
        }
    }

    // MARK: - Macro Table

    private func setupMacroTable() {
        let keyCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyCol.title = "Key"
        keyCol.width = 50
        macroTable.addTableColumn(keyCol)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Name"
        nameCol.width = 140
        macroTable.addTableColumn(nameCol)

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 240
        macroTable.addTableColumn(actionCol)

        let deleteCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("delete"))
        deleteCol.title = ""
        deleteCol.width = 30
        macroTable.addTableColumn(deleteCol)

        macroTable.dataSource = self
        macroTable.delegate = self
        macroTable.headerView = nil
        macroTable.rowHeight = 22
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        CustomMacroManager.shared.macros.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let macros = CustomMacroManager.shared.macros
        guard row < macros.count else { return nil }
        let macro = macros[row]

        let id = tableColumn?.identifier.rawValue ?? ""
        let cell = NSTextField(labelWithString: "")
        cell.font = .systemFont(ofSize: 11)
        cell.lineBreakMode = .byTruncatingTail

        switch id {
        case "key":
            cell.stringValue = macro.key
            cell.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        case "name":
            cell.stringValue = macro.name
        case "action":
            cell.stringValue = "\(macro.action.typeLabel): \(macro.action.value)"
            cell.textColor = .secondaryLabelColor
        case "delete":
            let btn = NSButton(title: "✕", target: self, action: #selector(deleteMacro(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.tag = row
            btn.font = .systemFont(ofSize: 10, weight: .bold)
            btn.contentTintColor = .systemRed
            return btn
        default: break
        }
        return cell
    }

    @objc private func deleteMacro(_ sender: NSButton) {
        let macros = CustomMacroManager.shared.macros
        guard sender.tag < macros.count else { return }
        CustomMacroManager.shared.remove(key: macros[sender.tag].key)
        macroTable.reloadData()
        buildSections()
    }

    @objc private func closeSheet() {
        dismiss(nil)
    }
}
