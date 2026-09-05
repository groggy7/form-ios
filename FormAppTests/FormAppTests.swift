import XCTest
import AVFoundation
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
        XCTAssertEqual(benchSprite?.imageName, "anatomy_barbell_bench_press")
        XCTAssertEqual(benchSprite?.atlasHeight, 418)

        let abWheelSprite = MovementIcon.movementAssetSprite("ab-wheel-rollout")
        XCTAssertEqual(abWheelSprite?.imageName, "anatomy_ab_wheel_rollout")
        XCTAssertEqual(abWheelSprite?.atlasHeight, 371)

        let frontSquatSprite = MovementIcon.movementAssetSprite("barbell-front-squat")
        XCTAssertEqual(frontSquatSprite?.imageName, "anatomy_barbell_front_squat")
        XCTAssertEqual(frontSquatSprite?.atlasHeight, 419)

        let backSquatSprite = MovementIcon.movementAssetSprite("barbell-back-squat")
        XCTAssertEqual(backSquatSprite?.imageName, "anatomy_barbell_back_squat")
        XCTAssertEqual(backSquatSprite?.atlasHeight, 418)
        for sprite in [benchSprite, abWheelSprite, frontSquatSprite, backSquatSprite].compactMap({ $0 }) {
            for frame in 0..<3 {
                XCTAssertNotNil(MovementFrameCache.getFrame(for: sprite, frame: frame))
            }
        }

        let inclineBenchSprite = MovementIcon.movementAssetSprite("incline-barbell-bench-press")
        XCTAssertNotNil(inclineBenchSprite)
        XCTAssertEqual(inclineBenchSprite?.imageName, "anatomy_incline_barbell_bench_press")
        XCTAssertEqual(inclineBenchSprite?.atlasHeight, 418)
        for frame in 0..<3 {
            XCTAssertNotNil(MovementFrameCache.getFrame(for: inclineBenchSprite!, frame: frame))
        }
    }

    func testMovementAnimationClockIsActive() {
        let clock = MovementAnimationClock.shared
        XCTAssertTrue([0, 1, 2].contains(clock.currentFrame))
    }

    func testFeedbackSoundsAreBundledAndDistinct() throws {
        let soundNames = [
            "form_rest_complete",
            "form_set_complete",
            "form_set_undo",
            "form_workout_start",
            "form_workout_complete"
        ]
        let soundData = try soundNames.map { name -> Data in
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: name, withExtension: "wav"),
                "Missing bundled sound: \(name).wav"
            )
            return try Data(contentsOf: url)
        }

        XCTAssertEqual(Set(soundData).count, soundNames.count, "Each feedback event needs its own sound identity")
    }

    func testSetUndoSoundMatchesAndroidMonoFormat() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "form_set_undo", withExtension: "wav")
        )
        let audioFile = try AVAudioFile(forReading: url)

        XCTAssertEqual(audioFile.fileFormat.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(audioFile.fileFormat.channelCount, 1)
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
    func testExerciseDetailSheetWithVideosSnapshot() {
        var exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "5 × 4–6",
            cues: "Plant heels, arch upper back, tuck shoulder blades.\nLower bar to sternum under control.\nExplode upward with leg drive.",
            avoid: "Bouncing bar off ribcage.\nButt lifting off the bench.",
            videos: [
                "https://www.youtube.com/watch?v=ZaTM37cfiDs",
                "https://youtube.com/shorts/3jzKvd6e2q4"
            ],
            movementType: "press",
            movementAssetId: "barbell-bench-press"
        )

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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_with_videos_snapshot.png"
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

    @MainActor
    func testTodayHeroCardDisabledButtonSnapshot() {
        let store = AppStore.shared
        guard let workout = store.activeProgram?.workouts.first(where: { $0.day == 5 }) ?? store.activeWorkout else {
            return
        }

        let card = TodayHeroCard(
            workout: workout,
            todayIndex: 0,
            isCompleted: false,
            isAvailable: false,
            availableDay: "Friday",
            hasUnfinishedProgress: false,
            onStart: {}
        )

        let controller = UIHostingController(rootView: card.padding(20))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 420)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_available_friday_fixed.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardQuadsAndCalvesSnapshot() {
        let store = AppStore.shared
        // Workout with Quads & Calves (e.g. Day 2 / Leg day)
        guard let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Quads") || $0.targetMuscles.contains("quadriceps") }) ?? store.activeProgram?.workouts.first(where: { $0.day == 2 }) else {
            return
        }

        // Test legs_back (index 1) which shows calves
        let card = TodayHeroCard(
            workout: workout,
            todayIndex: workout.day - 1,
            isCompleted: false,
            isAvailable: true,
            availableDay: nil,
            hasUnfinishedProgress: false,
            initialViewIndex: 1,
            onStart: {}
        )

        let controller = UIHostingController(rootView: card.padding(20))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 420)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_quads_calves_back.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testRestTimerModalSnapshot() {
        let modal = RestTimerFullScreenModal(
            secondsRemaining: 113,
            totalSeconds: 120,
            exerciseName: "Incline Dumbbell Press",
            isRunning: true,
            progress: 113.0 / 120.0,
            complete: false,
            timeText: "01:53",
            isMuted: false,
            onDismiss: {},
            onTogglePause: {},
            onAddSeconds: { _ in },
            onSetDuration: { _ in },
            onSkip: {},
            onToggleMute: {}
        )

        let controller = UIHostingController(rootView: modal)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_rest_timer_modal_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testRestTimerBarSnapshot() {
        let bar = RestTimerBar(
            secondsRemaining: 74,
            totalSeconds: 120,
            exerciseName: "Incline Dumbbell Press",
            isRunning: true,
            onTogglePause: {},
            onAddSeconds: { _ in },
            onSetDuration: { _ in },
            onSkip: {},
            isMuted: false,
            onToggleMute: {}
        )

        let controller = UIHostingController(rootView: bar.frame(maxWidth: .infinity))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 210)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 210))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_rest_timer_bar_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testWorkoutCalendarOnlyPastScheduledDaysAreMissed() {
        let initial = WorkoutCalendarHistory(nextScheduledDate: "2026-08-24", scheduledWeekdays: [1, 2, 4, 5])
        let today = "2026-08-27"
        let result = WorkoutCalendar.refresh(history: initial, today: today, weekdays: initial.scheduledWeekdays)
        XCTAssertEqual(result.missedDates, ["2026-08-24", "2026-08-25"])
        XCTAssertEqual(result.missedDates, WorkoutCalendar.refresh(history: result, today: today, weekdays: initial.scheduledWeekdays).missedDates)

        let statuses = WorkoutCalendar.statuses(history: result, today: today)
        XCTAssertEqual(statuses["2026-08-24"], .missed)
        XCTAssertEqual(statuses["2026-08-25"], .missed)
        XCTAssertNil(statuses["2026-08-26"], "Wednesday recovery day must stay neutral")
        XCTAssertNil(statuses[today], "Today must stay neutral if no session logged")
    }

    func testWorkoutCalendarCompletionWinsOverUnfinishedAndMissed() {
        let today = "2026-08-27"
        let history = WorkoutCalendarHistory(
            nextScheduledDate: today,
            missedDates: ["2026-08-24", "2026-08-25", "2026-08-27"],
            entries: [
                WorkoutDayEntry(id: "first", date: "2026-08-24", status: .unfinished),
                WorkoutDayEntry(id: "second", date: "2026-08-24", status: .completed),
                WorkoutDayEntry(id: "partial", date: "2026-08-25", status: .unfinished),
                WorkoutDayEntry(id: "future", date: "2026-08-28", status: .completed)
            ]
        )
        let statuses = WorkoutCalendar.statuses(history: history, today: today)
        XCTAssertEqual(statuses["2026-08-24"], .completed)
        XCTAssertEqual(statuses["2026-08-25"], .unfinished)
        XCTAssertNil(statuses[today])
        XCTAssertNil(statuses["2026-08-28"], "Future dates must stay neutral")
    }

    func testWorkoutCalendarMonthWeeksMondayFirst() {
        let sep2026 = WorkoutCalendar.parseDate("2026-09-01")!
        let weeks = WorkoutCalendar.monthWeeks(for: sep2026)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertNil(weeks[0][0], "Monday before Sept 1 is nil")
        XCTAssertNotNil(weeks[0][1], "Tuesday is Sept 1")
        XCTAssertEqual(WorkoutCalendar.formatDate(weeks[0][1]!), "2026-09-01")
    }

    @MainActor
    func testHistoryViewSnapshot() {
        let store = AppStore.shared
        let view = HistoryView(
            store: store,
            onOpenSettings: {},
            onSelectRecord: { _ in }
        )

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_screen_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetMissedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-01")!
        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-01",
            status: .missed,
            sessionRecord: nil,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 650)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 650))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_missed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetUnfinishedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Chest Growth",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:35:12.000Z",
            durationSeconds: 2112,
            totalVolumeKg: 4250,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ]
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10)
                    ]
                )
            ]
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .unfinished,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_unfinished_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testWorkoutCalendarRefreshPreservesEntries() {
        let initial = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-24",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:tue", date: "2026-08-25", status: .unfinished)
            ]
        )
        let refreshed = WorkoutCalendar.refresh(history: initial, today: "2026-08-27", weekdays: [1, 2, 4, 5])
        XCTAssertEqual(refreshed.entries.count, 1, "Entries must not be erased during refresh")
        XCTAssertEqual(refreshed.entries.first?.id, "session:tue")
        XCTAssertEqual(refreshed.entries.first?.status, .unfinished)

        let statuses = WorkoutCalendar.statuses(history: refreshed, today: "2026-08-27")
        XCTAssertEqual(statuses["2026-08-24"], .missed)
        XCTAssertEqual(statuses["2026-08-25"], .unfinished, "Unfinished entry must override missed date")
    }

    func testScheduledDateForWeekday() {
        // Assume date is Friday, Sep 4, 2026
        let friday = WorkoutCalendar.parseDate("2026-09-04")!
        let tueDate = WorkoutCalendar.scheduledDate(forWeekday: 2, relativeTo: friday)
        XCTAssertEqual(tueDate, "2026-09-01", "Tuesday of this week is 2026-09-01")
        let monDate = WorkoutCalendar.scheduledDate(forWeekday: 1, relativeTo: friday)
        XCTAssertEqual(monDate, "2026-08-31", "Monday of this week is 2026-08-31")
        let friDate = WorkoutCalendar.scheduledDate(forWeekday: 5, relativeTo: friday)
        XCTAssertEqual(friDate, "2026-09-04", "Friday of this week is 2026-09-04")
    }

    @MainActor
    func testTuesdayWorkoutPartialCompletionMarksTuesdayUnfinishedNotMissed() {
        let store = AppStore.shared
        guard let program = store.activeProgram,
              let tuesdayWorkout = program.workouts.first(where: { $0.day == 2 }) else {
            return
        }

        // Clean state
        store.activeSession = nil
        var st = store.state
        st.history.removeAll { $0.workoutId == tuesdayWorkout.id }
        st.completed.removeAll { $0.contains(tuesdayWorkout.id) }
        store.saveState(st)

        // Start Tuesday workout
        _ = store.startActiveSession(programId: program.id, workout: tuesdayWorkout)
        guard let draft = store.activeSession else {
            XCTFail("Active session failed to start")
            return
        }

        // Verify that draft is assigned to Tuesday (2026-09-01 in the current week)
        let sessionEntry = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })
        XCTAssertNotNil(sessionEntry)
        XCTAssertEqual(sessionEntry?.date, "2026-09-01")
        XCTAssertEqual(sessionEntry?.status, .unfinished)

        // Complete all sets for first exercise (e.g. Lat Pulldown)
        let firstEx = tuesdayWorkout.exercises.first!
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 60
                sets[i].completedReps = 10
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // Finish workout (clicks finish / Save & close)
        let progress = SessionProgress.from(draft: store.activeSession!, nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let record = progress.record(draft: store.activeSession!, completedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        store.completeActiveSession(record)

        // Active session should be nil
        XCTAssertNil(store.activeSession)

        // Tuesday in calendarStatuses must be UNFINISHED (orange), NOT MISSED (red)!
        let today = Date()
        let statuses = store.calendarStatuses(today: today)
        XCTAssertEqual(statuses["2026-09-01"], .unfinished, "Tuesday must be orange (.unfinished), not red (.missed)!")

        // History list must contain record for Tuesday
        let foundRecord = store.state.history.first { rec in
            WorkoutCalendar.localDate(from: rec.startedAt) == "2026-09-01" ||
            store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date == "2026-09-01"
        }
        XCTAssertNotNil(foundRecord, "Record must be mapped to 2026-09-01")
        let firstExLog = foundRecord?.exerciseLogs.first(where: { $0.exerciseName.lowercased() == firstEx.name.lowercased() })
        XCTAssertNotNil(firstExLog)
        XCTAssertGreaterThan(firstExLog?.sets.count ?? 0, 0, "Lat Pulldown sets must be recorded as completed")
    }

    // MARK: - Video Support Tests

    func testYouTubeVideoParsing() {
        // Standard watch URLs
        let watch = YouTubeVideo.parse("https://www.youtube.com/watch?v=ZaTM37cfiDs")
        XCTAssertNotNil(watch)
        XCTAssertEqual(watch?.id, "ZaTM37cfiDs")
        XCTAssertFalse(watch?.isShort ?? true)
        XCTAssertEqual(watch?.startSeconds, 0)

        // Shorts URL
        let short = YouTubeVideo.parse("https://youtube.com/shorts/ZaTM37cfiDs")
        XCTAssertNotNil(short)
        XCTAssertEqual(short?.id, "ZaTM37cfiDs")
        XCTAssertTrue(short?.isShort ?? false)

        // youtu.be shortlink with start time in seconds
        let youtbe = YouTubeVideo.parse("https://youtu.be/ZaTM37cfiDs?t=90")
        XCTAssertNotNil(youtbe)
        XCTAssertEqual(youtbe?.id, "ZaTM37cfiDs")
        XCTAssertEqual(youtbe?.startSeconds, 90)
        XCTAssertEqual(youtbe?.watchUrl, "https://www.youtube.com/watch?v=ZaTM37cfiDs&t=90s")

        // Formatted timestamp (1h2m3s)
        let formattedTime = YouTubeVideo.parse("https://www.youtube.com/watch?v=ZaTM37cfiDs&t=1h2m3s")
        XCTAssertNotNil(formattedTime)
        XCTAssertEqual(formattedTime?.startSeconds, 3723)

        // Invalid URLs
        XCTAssertNil(YouTubeVideo.parse("https://vimeo.com/12345678"))
        XCTAssertNil(YouTubeVideo.parse("https://youtube.com/watch?v=short"))
        XCTAssertNil(YouTubeVideo.parse("ftp://youtube.com/watch?v=ZaTM37cfiDs"))
        XCTAssertNil(YouTubeVideo.parse("not a url"))
    }

    func testVideoPlaybackStateProperties() {
        let unready = VideoPlaybackState(ready: false, playerState: -1)
        XCTAssertFalse(unready.playing)
        XCTAssertFalse(unready.ended)
        XCTAssertFalse(unready.canControl)

        let playing = VideoPlaybackState(ready: true, playerState: 1, currentSeconds: 10, durationSeconds: 60)
        XCTAssertTrue(playing.playing)
        XCTAssertFalse(playing.ended)
        XCTAssertTrue(playing.canControl)

        let buffering = VideoPlaybackState(ready: true, playerState: 3)
        XCTAssertTrue(buffering.playing)

        let ended = VideoPlaybackState(ready: true, playerState: 0)
        XCTAssertFalse(ended.playing)
        XCTAssertTrue(ended.ended)
        XCTAssertTrue(ended.canControl)

        let errored = VideoPlaybackState(ready: true, playerState: 1, error: "network")
        XCTAssertFalse(errored.canControl)
    }

    func testFormatVideoTime() {
        XCTAssertEqual(formatVideoTime(0), "0:00")
        XCTAssertEqual(formatVideoTime(9), "0:09")
        XCTAssertEqual(formatVideoTime(75), "1:15")
        XCTAssertEqual(formatVideoTime(3599), "59:59")
        XCTAssertEqual(formatVideoTime(3600), "1:00:00")
        XCTAssertEqual(formatVideoTime(3665), "1:01:05")
    }

    func testAppStoreSetExerciseVideos() {
        let store = AppStore.shared
        let exerciseName = "Barbell Back Squat"

        let testUrls = [
            "https://youtu.be/ZaTM37cfiDs",
            "youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/ZaTM37cfiDs", // duplicate
            "not a valid url with spaces", // invalid URL
            "ftp://invalid-scheme.com/video", // invalid scheme
            "https://youtube.com/shorts/3jzKvd6e2q4",
            "https://youtube.com/watch?v=extraLinkShouldBeCapped" // 4th link, should be capped at 3
        ]

        store.setExerciseVideos(exerciseName: exerciseName, videoUrls: testUrls)

        let catalogEntry = store.exerciseCatalogue.first { $0.key == exerciseName.lowercased() }
        XCTAssertNotNil(catalogEntry)
        XCTAssertEqual(catalogEntry?.exercise.videos.count, 3, "Videos count must be capped at 3")
        XCTAssertEqual(catalogEntry?.exercise.videos[0], "https://youtu.be/ZaTM37cfiDs")
        XCTAssertEqual(catalogEntry?.exercise.videos[1], "https://youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(catalogEntry?.exercise.videos[2], "https://youtube.com/shorts/3jzKvd6e2q4")
        XCTAssertNotNil(store.noticeMessage)
    }

    func testVideoTranslationsParity() {
        let requiredKeys = [
            "video.openExternal", "video.close", "video.back5", "video.forward5",
            "video.play", "video.pause", "video.resume", "video.replay",
            "video.loading", "video.retry", "video.invalid", "video.networkError", "video.embedError",
            "video.linkTitle", "video.linkSubtitle", "video.urlInputLabel", "video.urlInputPlaceholder",
            "video.addUrlButton", "video.pasteButton", "video.previewVideo", "video.deleteVideo",
            "video.linkedCount", "video.maxLimitReached", "video.duplicateUrl", "video.invalidUrl",
            "video.noVideos", "video.saveLinks", "video.tapToPlay", "notice.videosUpdated",
            "library.videos", "library.attachVideoCta"
        ]

        for key in requiredKeys {
            XCTAssertFalse(Translations.en[key]?.isEmpty ?? true, "Missing English key: \(key)")
            XCTAssertFalse(Translations.tr[key]?.isEmpty ?? true, "Missing Turkish key: \(key)")
        }
    }

    @MainActor
    func testExerciseVideoLinksSheetSnapshot() {
        let exercise = Exercise(
            name: "Incline Dumbbell Press",
            prescription: "4 × 8–10",
            videos: [
                "https://www.youtube.com/watch?v=8iPEnn-ltC8"
            ],
            movementType: "press"
        )
        let sheet = ExerciseVideoLinksSheet(exercise: exercise, onDismiss: {})
        let controller = UIHostingController(rootView: sheet)
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_video_links_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testVideoPlayerSheetSnapshot() {
        let sheet = VideoPlayerSheet(
            exerciseName: "Barbell Bench Press",
            videoUrl: "https://www.youtube.com/watch?v=ZaTM37cfiDs",
            onClose: {}
        )
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_video_player_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testCanonicalExercisesSeedCatalogueIndependentlyOfPrograms() {
        let catalogue = ExerciseCatalog.build(
            bundledPrograms: [],
            userPrograms: [],
            canonicalExercises: Array(ExerciseCatalog.canonicalExercises.values)
        )

        XCTAssertEqual(catalogue.count, 49)
        XCTAssertEqual(catalogue.count, Set(catalogue.map { $0.key }).count)
        XCTAssertEqual(catalogue.filter { $0.exercise.movementAssetId != nil }.count, 49)
        XCTAssertEqual(catalogue.filter { !$0.exercise.cues.isEmpty }.count, 49)
        XCTAssertEqual(catalogue.filter { !$0.exercise.avoid.isEmpty }.count, 49)
        XCTAssertEqual(catalogue.filter { $0.exercise.exerciseId != nil }.count, 49)
    }

    func testCanonicalExercisesProvideTurkishCuesAndAvoid() {
        let canonical = Array(ExerciseCatalog.canonicalExercises.values)
        XCTAssertEqual(canonical.count, 49)
        XCTAssertEqual(canonical.filter { !$0.cuesTr.isEmpty }.count, 49)
        XCTAssertEqual(canonical.filter { !$0.avoidTr.isEmpty }.count, 49)

        guard let bench = canonical.first(where: { $0.id == "barbell-bench-press" }) else {
            XCTFail("Missing bench press definition")
            return
        }

        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let localizedCues = LanguageManager.content(bench.cuesText)
        XCTAssertTrue(localizedCues.contains("Gözler barın hizasında"))
        XCTAssertTrue(localizedCues.contains("kürek kemiklerini"))

        let localizedAvoid = LanguageManager.content(bench.avoidText)
        XCTAssertTrue(localizedAvoid.contains("omuz sıkışmasına yol açar"))
        XCTAssertTrue(localizedAvoid.contains("Barı göğüsten sektirmek"))

        let firstCue = bench.cues.first!
        let localizedFirstCue = LanguageManager.content(firstCue)
        XCTAssertEqual(localizedFirstCue, bench.cuesTr.first!)
    }
}
