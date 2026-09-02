import XCTest
@testable import FormApp

final class FormAppTests: XCTestCase {

    func testSanitizedRepsInputRejectsZero() {
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("0"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("00"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("05"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("-1"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("abc"))
        
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput(""), "")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("1"), "1")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("12"), "12")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("999"), "999")
    }

    func testSanitizedWeightInput() {
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("50"), "50")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52.5"), "52.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52,5"), "52.5")
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("abc"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("12345.67"))
    }

    func testFormatSecondsToTime() {
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(0), "00:00")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(90), "01:30")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(3600), "01:00:00")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(5581), "01:33:01")
    }

    func testInitialSetCount() {
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "4 × 8–10"), 4)
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "3 x 12"), 3)
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "Heavy sets"), 3)
    }

    func testStarterProgramsAreAvailable() {
        let bundled = AppStore.loadBundledStarterPrograms()
        XCTAssertFalse(bundled.isEmpty, "Starter programs should be bundled and loaded successfully")
        XCTAssertTrue(bundled.count >= 6, "Expected at least 6 starter programs")
    }
}
