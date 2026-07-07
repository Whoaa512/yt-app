import Foundation

struct WatchRecord {
    let title: String
    let channel: String?
    let durationText: String?
    let visitedAt: Date
}

struct WatchStats {
    let videoCount: Int
    let last7DayCount: Int
    let totalSeconds: Double
    let topChannels: [(name: String, count: Int)]
}

/// Aggregates history rows into the watch-stats panel numbers.
/// Pure logic — covered by Tests/StatsAggregatorTests.
enum StatsAggregator {
    static func parseDuration(_ text: String?) -> Double? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.reduce(0.0) { $0 * 60 + Double($1)! }
    }

    static func aggregate(records: [WatchRecord], now: Date) -> WatchStats {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var channelCounts: [String: Int] = [:]
        var total: Double = 0
        var recent = 0

        for record in records {
            if let secs = parseDuration(record.durationText) { total += secs }
            if record.visitedAt >= weekAgo { recent += 1 }
            if let channel = record.channel, !channel.isEmpty {
                channelCounts[channel, default: 0] += 1
            }
        }

        let top = channelCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(8)
            .map { (name: $0.key, count: $0.value) }

        return WatchStats(videoCount: records.count, last7DayCount: recent, totalSeconds: total, topChannels: top)
    }

    /// Real-time saved by watching `totalSeconds` of content at `rate`.
    static func timeSaved(totalSeconds: Double, rate: Float) -> Double {
        guard rate > 1 else { return 0 }
        return totalSeconds * Double(rate - 1) / Double(rate)
    }

    static func hoursText(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
