import XCTest
@testable import YTAppCore

final class VideoURLTests: XCTestCase {
    func testExtractsFromWatchURL() {
        XCTAssertEqual(VideoURL.videoId(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testExtractsWhenOtherParamsPresent() {
        XCTAssertEqual(VideoURL.videoId(from: "https://www.youtube.com/watch?list=PL123&v=abc123XYZ_-&t=42s"), "abc123XYZ_-")
    }

    func testExtractsFromShortLink() {
        XCTAssertEqual(VideoURL.videoId(from: "https://youtu.be/dQw4w9WgXcQ?t=10"), "dQw4w9WgXcQ")
    }

    func testExtractsFromShorts() {
        XCTAssertEqual(VideoURL.videoId(from: "https://www.youtube.com/shorts/abc123XYZ_-"), "abc123XYZ_-")
    }

    func testNonVideoURLReturnsNil() {
        XCTAssertNil(VideoURL.videoId(from: "https://www.youtube.com/feed/subscriptions"))
        XCTAssertNil(VideoURL.videoId(from: "not a url"))
        XCTAssertNil(VideoURL.videoId(from: "https://www.youtube.com/watch"))
    }

    func testRejectsMalformedIds() {
        XCTAssertNil(VideoURL.videoId(from: "https://www.youtube.com/watch?v="))
    }
}
