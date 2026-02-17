import Cocoa

protocol HistoryViewControllerDelegate: AnyObject {
    func historyViewController(_ vc: HistoryViewController, didSelectURL url: URL)
}

class HistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    weak var historyDelegate: HistoryViewControllerDelegate?

    private var entries: [HistoryEntry] = []
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let clearButton = NSButton()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "History"
        setupUI()
        loadHistory()
    }

    private func setupUI() {
        searchField.placeholderString = "Search history..."
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchField)

        clearButton.title = "Clear All"
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        let titleCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleCol.title = "Title"
        titleCol.width = 250
        tableView.addTableColumn(titleCol)

        let durationCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        durationCol.title = "Duration"
        durationCol.width = 60
        tableView.addTableColumn(durationCol)

        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateCol.title = "Visited"
        dateCol.width = 150
        tableView.addTableColumn(dateCol)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),

            clearButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            clearButton.widthAnchor.constraint(equalToConstant: 80),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func loadHistory(query: String = "") {
        entries = HistoryManager.shared.search(query: query)
        tableView.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) {
        loadHistory(query: searchField.stringValue)
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear All History?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            HistoryManager.shared.clearAll()
            loadHistory()
        }
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 && row < entries.count else { return }
        if let url = URL(string: entries[row].url) {
            historyDelegate?.historyViewController(self, didSelectURL: url)
            dismiss(nil)
        }
    }

    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let id = tableColumn!.identifier
        let cellID = NSUserInterfaceItemIdentifier("Cell_\(id.rawValue)")
        let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField ?? {
            let tf = NSTextField(labelWithString: "")
            tf.identifier = cellID
            tf.lineBreakMode = .byTruncatingTail
            return tf
        }()

        switch id.rawValue {
        case "title": cell.stringValue = entry.title ?? entry.url
        case "duration": cell.stringValue = entry.duration ?? ""
        case "date": cell.stringValue = dateFormatter.string(from: entry.visitedAt)
        default: break
        }
        return cell
    }
}
