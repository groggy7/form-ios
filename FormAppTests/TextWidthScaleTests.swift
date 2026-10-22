import XCTest
@testable import FormApp

/// Width text scale bounds from gym/docs/design/form-design-system.md#width-scaled-text; Android's TextWidthScaleTest mirrors these.
final class TextWidthScaleTests: XCTestCase {
    private func factor(_ width: CGFloat) -> CGFloat { TextWidthScale.factor(forWidth: width) }

    func testReferenceWidthsKeepAuthoredSizes() {
        XCTAssertEqual(factor(393), 1)
        XCTAssertEqual(factor(392.7), 1)
        XCTAssertEqual(factor(390), 0.99)
    }

    func testNarrowPhonesShrinkProportionallyDownToTheFloor() {
        XCTAssertEqual(factor(384), 0.98)
        XCTAssertEqual(factor(375), 0.95)
        XCTAssertEqual(factor(360), 0.92)
        XCTAssertEqual(factor(320), TextWidthScale.minFactor)
    }

    func testWidePhonesGrowOnlyUpToTheCap() {
        XCTAssertEqual(factor(402), 1.02)
        XCTAssertEqual(factor(412), 1.05)
        XCTAssertEqual(factor(440), TextWidthScale.maxFactor)
        XCTAssertEqual(factor(1024), TextWidthScale.maxFactor)
    }

    func testUndefinedWidthLeavesTextUnchanged() {
        XCTAssertEqual(factor(0), 1)
    }
}
