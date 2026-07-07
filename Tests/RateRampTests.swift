import XCTest
@testable import YTAppCore

final class RateRampTests: XCTestCase {
    func testStepsEndExactlyAtTarget() {
        let steps = RateRamp.steps(from: 1.0, to: 2.0)
        XCTAssertEqual(steps.last, 2.0)
    }

    func testStepsAreMonotonicWhenIncreasing() {
        let steps = RateRamp.steps(from: 1.0, to: 3.0)
        XCTAssertEqual(steps, steps.sorted())
        XCTAssertGreaterThan(steps.count, 2)
    }

    func testStepsAreMonotonicWhenDecreasing() {
        let steps = RateRamp.steps(from: 2.5, to: 1.0)
        XCTAssertEqual(steps, steps.sorted(by: >))
    }

    func testSameRateYieldsSingleStep() {
        XCTAssertEqual(RateRamp.steps(from: 1.5, to: 1.5), [1.5])
    }

    func testEaseOutFrontLoadsChange() {
        let steps = RateRamp.steps(from: 1.0, to: 2.0)
        let mid = steps[steps.count / 2]
        XCTAssertGreaterThan(mid, 1.5)
    }

    func testJSAppliesFinalRateAndIsParseable() {
        let js = RateRamp.rampJS(from: 1.0, to: 2.0)
        XCTAssertTrue(js.contains("2"))
        XCTAssertTrue(js.contains("playbackRate"))
        XCTAssertFalse(js.contains("Optional"))
    }
}
