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
        XCTAssertEqual(bundled.count, 6, "Expected all 6 starter programs")
        XCTAssertEqual(bundled.first?.name, "Aesthetic Engine: 5-Day Hypertrophy")
    }

    func testMovementSpritesResolution() {
        let pressSprite = MovementIcon.categorySprite(.press)
        XCTAssertNotNil(pressSprite)
        XCTAssertEqual(pressSprite?.imageName, "anatomy_compound")

        let jumpRopeSprite = MovementIcon.movementAssetSprite("jump-rope")
        XCTAssertNotNil(jumpRopeSprite)
        XCTAssertEqual(jumpRopeSprite?.imageName, "anatomy_jump_rope")

        let benchSprite = MovementIcon.movementAssetSprite("barbell-bench-press")
        XCTAssertNotNil(benchSprite)
        XCTAssertEqual(benchSprite?.imageName, "anatomy_batch_03_upper")
    }

    func testMovementAnimationClockIsActive() {
        let clock = MovementAnimationClock.shared
        XCTAssertTrue([0, 1, 2].contains(clock.currentFrame))
    }
    func testMovementFrameCacheProducesDistinctFrames() {
        let sprite = MovementIcon.categorySprite(.press)!
        let f0 = MovementFrameCache.getFrame(for: sprite, frame: 0)
        let f1 = MovementFrameCache.getFrame(for: sprite, frame: 1)
        let f2 = MovementFrameCache.getFrame(for: sprite, frame: 2)
        XCTAssertNotNil(f0)
        XCTAssertNotNil(f1)
        XCTAssertNotNil(f2)
        XCTAssertNotEqual(f0?.pngData(), f2?.pngData(), "Frames 0 and 2 must be visually different")
    }

}
