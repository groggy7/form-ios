import XCTest
import UIKit
import SwiftUI
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

    func testMuscleMasksSVGPathsParseNonEmpty() {
        for view in BodyView.allCases {
            let paths = MuscleMasks.paths(for: view)
            XCTAssertFalse(paths.isEmpty, "Paths for \(view) should not be empty")
            for (muscle, path) in paths {
                let bounds = path.boundingBox
                XCTAssertFalse(bounds.isEmpty, "Path for \(view):\(muscle) bounding box should not be empty")
                XCTAssertGreaterThan(bounds.width, 0)
                XCTAssertGreaterThan(bounds.height, 0)
                XCTAssertLessThanOrEqual(bounds.maxX, MuscleMasks.viewport + 10)
                XCTAssertLessThanOrEqual(bounds.maxY, MuscleMasks.viewport + 10)
            }
        }
    }

    func testWorkoutBodyViewsResolution() {
        // Quads and Calves -> legs-front and legs-back
        let legWorkout = Workout(
            id: "w1", day: 4, title: "Legs", focus: "Quads & Calves",
            tone: "violet", exercises: [], targetMuscles: ["quadriceps", "calves"]
        )
        let legViews: [BodyView] = legWorkout.bodyViews()
        XCTAssertEqual(legViews, [BodyView.legsFront, BodyView.legsBack])

        // Chest and Triceps -> front and back
        let upperWorkout = Workout(
            id: "w2", day: 1, title: "Push", focus: "Chest & Triceps",
            tone: "violet", exercises: [], targetMuscles: ["chest", "triceps"]
        )
        let upperViews: [BodyView] = upperWorkout.bodyViews()
        XCTAssertEqual(upperViews, [BodyView.front, BodyView.back])
    }

    func testDetailTranslationsExist() {
        XCTAssertEqual(LanguageManager.t("library.details"), "Exercise details")
        XCTAssertEqual(LanguageManager.t("modal.exercise.cues"), "Technique cues")
        XCTAssertEqual(LanguageManager.t("modal.exercise.avoid"), "What to avoid")
    }

    @MainActor
    func testExerciseDetailSheetSnapshot() {
        let store = AppStore.shared
        guard let exercise = store.state.programs.flatMap({ $0.workouts }).flatMap({ $0.exercises }).first(where: { $0.name == "Barbell Bench Press" }) else {
            XCTFail("Barbell Bench Press not found")
            return
        }

        let sheetView = ExerciseDetailSheet(exercise: exercise, onDismiss: {})
        let controller = UIHostingController(rootView: sheetView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_test.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testProgramsViewSnapshot() {
        let store = AppStore.shared
        let programsView = ProgramsView(store: store, onDismiss: {})
        let controller = UIHostingController(rootView: programsView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_programs_fixed.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        XCTAssertEqual(LanguageManager.t("programs.import"), "Import JSON")
        XCTAssertEqual(LanguageManager.t("programs.apply"), "Apply")
        XCTAssertEqual(LanguageManager.t("editor.title"), "Program editor")
    }
}
