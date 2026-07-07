import XCTest
@testable import YTAppCore

final class TranscriptParserTests: XCTestCase {
    let sample = """
    {"events":[
      {"tStartMs":0,"dDurMs":2000,"segs":[{"utf8":"Hello "},{"utf8":"world"}]},
      {"tStartMs":1500,"dDurMs":10,"segs":[{"utf8":"\\n"}]},
      {"tStartMs":2000,"dDurMs":3000},
      {"tStartMs":5000,"dDurMs":1000,"segs":[{"utf8":"second cue"}]}
    ]}
    """

    func testParsesCuesJoiningSegments() {
        let cues = TranscriptParser.parse(json3: sample)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(cues[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(cues[1].text, "second cue")
        XCTAssertEqual(cues[1].start, 5.0, accuracy: 0.001)
    }

    func testSkipsNewlineOnlyAndEmptyEvents() {
        let cues = TranscriptParser.parse(json3: sample)
        XCTAssertFalse(cues.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testGarbageReturnsEmpty() {
        XCTAssertTrue(TranscriptParser.parse(json3: "not json").isEmpty)
        XCTAssertTrue(TranscriptParser.parse(json3: "{}").isEmpty)
    }

    func testTimestampFormatting() {
        XCTAssertEqual(TranscriptParser.timestamp(0), "0:00")
        XCTAssertEqual(TranscriptParser.timestamp(65), "1:05")
        XCTAssertEqual(TranscriptParser.timestamp(3671), "1:01:11")
    }

    func testSearchFiltersCaseInsensitive() {
        let cues = TranscriptParser.parse(json3: sample)
        let hits = TranscriptParser.filter(cues: cues, query: "SECOND")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].text, "second cue")
        XCTAssertEqual(TranscriptParser.filter(cues: cues, query: "").count, cues.count)
    }

    func testCueIndexForTime() {
        let cues = TranscriptParser.parse(json3: sample)
        XCTAssertEqual(TranscriptParser.cueIndex(at: 0.5, in: cues), 0)
        XCTAssertEqual(TranscriptParser.cueIndex(at: 4.0, in: cues), 0)
        XCTAssertEqual(TranscriptParser.cueIndex(at: 6.0, in: cues), 1)
        XCTAssertNil(TranscriptParser.cueIndex(at: 3.0, in: []))
    }
}
