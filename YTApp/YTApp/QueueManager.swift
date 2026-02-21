import Foundation

struct QueueItem: Codable, Identifiable, Equatable {
    let id: String  // UUID
    let videoId: String
    var title: String
    var channel: String
    var thumbnailURL: URL?

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

protocol QueueManagerDelegate: AnyObject {
    func queueDidUpdate()
}

class QueueManager {
    static let shared = QueueManager()

    weak var delegate: QueueManagerDelegate?

    private(set) var items: [QueueItem] = []
    private(set) var currentIndex: Int = -1

    private let saveKey = "appQueue"

    private init() {
        load()
    }

    var currentItem: QueueItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var hasNext: Bool {
        currentIndex + 1 < items.count
    }

    var nextItem: QueueItem? {
        guard hasNext else { return nil }
        return items[currentIndex + 1]
    }

    // MARK: - Mutating

    func addItem(videoId: String, title: String, channel: String = "") {
        // Don't add duplicates
        if items.contains(where: { $0.videoId == videoId }) { return }

        let item = QueueItem(
            id: UUID().uuidString,
            videoId: videoId,
            title: title.isEmpty ? videoId : title,
            channel: channel,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
        )
        items.append(item)
        save()
        delegate?.queueDidUpdate()
    }

    func removeItem(at index: Int) {
        guard index >= 0 && index < items.count else { return }
        items.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(currentIndex, items.count - 1)
        }
        save()
        delegate?.queueDidUpdate()
    }

    func moveItem(from: Int, to: Int) {
        guard from != to,
              from >= 0 && from < items.count,
              to >= 0 && to < items.count else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        // Adjust currentIndex
        if currentIndex == from {
            currentIndex = to
        } else if from < currentIndex && to >= currentIndex {
            currentIndex -= 1
        } else if from > currentIndex && to <= currentIndex {
            currentIndex += 1
        }
        save()
        delegate?.queueDidUpdate()
    }

    func playItem(at index: Int) -> QueueItem? {
        guard index >= 0 && index < items.count else { return nil }
        currentIndex = index
        save()
        delegate?.queueDidUpdate()
        return items[index]
    }

    func playNext() -> QueueItem? {
        guard hasNext else { return nil }
        currentIndex += 1
        save()
        delegate?.queueDidUpdate()
        return currentItem
    }

    func clear() {
        items.removeAll()
        currentIndex = -1
        save()
        delegate?.queueDidUpdate()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        UserDefaults.standard.set(currentIndex, forKey: saveKey + "Index")
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode([QueueItem].self, from: data) {
            items = saved
        }
        currentIndex = UserDefaults.standard.integer(forKey: saveKey + "Index")
        if currentIndex >= items.count { currentIndex = -1 }
    }
}
