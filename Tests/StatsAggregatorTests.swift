import XCTest
@testable import YTAppCore

final class StatsAggregatorTests: XCTestCase {
    func rec(_ title: String, channel: String? = nil, duration: String? = nil, daysAgo: Double = 0) -> WatchRecord {
        WatchRecord(title: title, channel: channel, durationText: duration,
                    visitedAt: Date(timeIntervalSinceNow: -daysAgo * 86400))
    }

    func testParseDuration() {
        XCTAssertEqual(StatsAggregator.parseDuration("12:34"), 754)
        XCTAssertEqual(StatsAggregator.parseDuration("1:02:03"), 3723)
        XCTAssertEqual(StatsAggregator.parseDuration("0:59"), 59)
        XCTAssertNil(StatsAggregator.parseDuration(nil))
        XCTAssertNil(StatsAggregator.parseDuration("garbage"))
        XCTAssertNil(StatsAggregator.parseDuration(""))
    }

    func testCountsAndWatchTime() {
        let stats = StatsAggregator.aggregate(records: [
            rec("a", duration: "10:00"),
            rec("b", duration: "20:00"),
            rec("c"),
        ], now: Date())
        XCTAssertEqual(stats.videoCount, 3)
        XCTAssertEqual(stats.totalSeconds, 1800)
    }

    func testLast7DayCount() {
        let stats = StatsAggregator.aggregate(records: [
            rec("old", daysAgo: 30),
            rec("recent", daysAgo: 2),
            rec("today", daysAgo: 0),
        ], now: Date())
        XCTAssertEqual(stats.videoCount, 3)
        XCTAssertEqual(stats.last7DayCount, 2)
    }

    func testTopChannelsSortedByCountThenName() {
        let stats = StatsAggregator.aggregate(records: [
            rec("1", channel: "Alpha"), rec("2", channel: "Beta"),
            rec("3", channel: "Beta"), rec("4", channel: ""), rec("5", channel: nil),
        ], now: Date())
        XCTAssertEqual(stats.topChannels.map(\.name), ["Beta", "Alpha"])
        XCTAssertEqual(stats.topChannels.first?.count, 2)
    }

    func testTimeSavedAtRate() {
        XCTAssertEqual(StatsAggregator.timeSaved(totalSeconds: 3600, rate: 2.0), 1800, accuracy: 0.1)
        XCTAssertEqual(StatsAggregator.timeSaved(totalSeconds: 3600, rate: 1.0), 0, accuracy: 0.1)
        XCTAssertEqual(StatsAggregator.timeSaved(totalSeconds: 100, rate: 0), 0, accuracy: 0.1)
    }

    func testHoursText() {
        XCTAssertEqual(StatsAggregator.hoursText(0), "0m")
        XCTAssertEqual(StatsAggregator.hoursText(59 * 60), "59m")
        XCTAssertEqual(StatsAggregator.hoursText(3600 * 5 + 60 * 30), "5h 30m")
        XCTAssertEqual(StatsAggregator.hoursText(3600 * 41), "41h 0m")
    }
}
