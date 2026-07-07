import XCTest
@testable import YTAppCore

final class FuzzyMatcherTests: XCTestCase {
    func testEmptyQueryMatchesEverythingWithZeroScore() {
        let m = FuzzyMatcher.match(query: "", in: "Hello World")
        XCTAssertNotNil(m)
        XCTAssertEqual(m?.ranges.count, 0)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "xyz", in: "Hello World"))
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "hlo", in: "Hello World"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "HELLO", in: "hello world"))
    }

    func testConsecutiveBeatsScattered() {
        let consecutive = FuzzyMatcher.match(query: "hist", in: "Show History")!
        let scattered = FuzzyMatcher.match(query: "hist", in: "Height list")!
        XCTAssertGreaterThan(consecutive.score, scattered.score)
    }

    func testWordBoundaryBonus() {
        let boundary = FuzzyMatcher.match(query: "qu", in: "Toggle Queue")!
        let midWord = FuzzyMatcher.match(query: "qu", in: "aqueduct x")!
        XCTAssertGreaterThan(boundary.score, midWord.score)
    }

    func testPrefixBeatsLaterMatch() {
        let prefix = FuzzyMatcher.match(query: "new", in: "New Tab")!
        let later = FuzzyMatcher.match(query: "new", in: "Open New Window")!
        XCTAssertGreaterThan(prefix.score, later.score)
    }

    func testRangesCoverQueryCharacters() {
        let m = FuzzyMatcher.match(query: "nt", in: "New Tab")!
        let text = "New Tab"
        let matched = m.ranges.map { String(text[$0]) }.joined().lowercased()
        XCTAssertEqual(matched, "nt")
    }

    func testRankSortsByScoreDescending() {
        let items = ["Open New Window", "New Tab", "Newton's laws"]
        let ranked = FuzzyMatcher.rank(query: "new tab", items: items, text: { $0 })
        XCTAssertEqual(ranked.first?.item, "New Tab")
    }

    func testRankDropsNonMatches() {
        let ranked = FuzzyMatcher.rank(query: "zzz", items: ["a", "b"], text: { $0 })
        XCTAssertTrue(ranked.isEmpty)
    }
}
