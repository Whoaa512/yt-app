import Cocoa

/// "Nerd stats" window: watch counts, total time, top channels, time saved by speed.
final class StatsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Watch Stats"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        buildContent()
    }

    func refresh() {
        buildContent()
    }

    private func buildContent() {
        guard let window else { return }

        let records = HistoryManager.shared.allWatchRecords()
        let stats = StatsAggregator.aggregate(records: records, now: Date())
        let rate = Settings.defaultPlaybackRate
        let saved = StatsAggregator.timeSaved(totalSeconds: stats.totalSeconds, rate: rate)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active

        let title = NSTextField(labelWithString: "Watch Stats")
        title.font = .systemFont(ofSize: 20, weight: .bold)

        let grid = NSStackView()
        grid.orientation = .horizontal
        grid.distribution = .fillEqually
        grid.spacing = 12
        grid.addArrangedSubview(statCard(value: "\(stats.videoCount)", label: "videos watched"))
        grid.addArrangedSubview(statCard(value: "\(stats.last7DayCount)", label: "this week"))
        grid.addArrangedSubview(statCard(value: StatsAggregator.hoursText(stats.totalSeconds), label: "watch time"))

        let savedLabel = NSTextField(labelWithString: "⚡ \(StatsAggregator.hoursText(saved)) saved at \(String(format: "%g", rate))× speed")
        savedLabel.font = .systemFont(ofSize: 13, weight: .medium)
        savedLabel.textColor = .secondaryLabelColor

        let channelsHeader = NSTextField(labelWithString: "Top Channels")
        channelsHeader.font = .systemFont(ofSize: 13, weight: .semibold)
        channelsHeader.textColor = .secondaryLabelColor

        let channelStack = NSStackView()
        channelStack.orientation = .vertical
        channelStack.alignment = .leading
        channelStack.spacing = 6
        let maxCount = stats.topChannels.first?.count ?? 1
        for entry in stats.topChannels {
            channelStack.addArrangedSubview(channelRow(name: entry.name, count: entry.count, maxCount: maxCount))
        }
        if stats.topChannels.isEmpty {
            let empty = NSTextField(labelWithString: "Channels appear as you watch")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            channelStack.addArrangedSubview(empty)
        }

        let stack = NSStackView(views: [title, grid, savedLabel, channelsHeader, channelStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.setCustomSpacing(20, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 44),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -24),
            grid.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: effect.bottomAnchor, constant: -24),
        ])

        window.contentView = effect
    }

    private func statCard(value: String, label: String) -> NSView {
        let valueField = NSTextField(labelWithString: value)
        valueField.font = .monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        valueField.textColor = .labelColor

        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 11)
        labelField.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [valueField, labelField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        card.layer?.cornerRadius = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func channelRow(name: String, count: Int, maxCount: Int) -> NSView {
        let nameField = NSTextField(labelWithString: name)
        nameField.font = .systemFont(ofSize: 12, weight: .medium)
        nameField.lineBreakMode = .byTruncatingTail

        let countField = NSTextField(labelWithString: "\(count)")
        countField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countField.textColor = .secondaryLabelColor

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        bar.layer?.cornerRadius = 2
        bar.translatesAutoresizingMaskIntoConstraints = false
        let fraction = CGFloat(count) / CGFloat(max(1, maxCount))

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        countField.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(nameField)
        row.addSubview(bar)
        row.addSubview(countField)
        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 360),
            row.heightAnchor.constraint(equalToConstant: 18),
            nameField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            nameField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 160),
            bar.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 8),
            bar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 4),
            bar.widthAnchor.constraint(equalToConstant: 130 * fraction),
            countField.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            countField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }
}
