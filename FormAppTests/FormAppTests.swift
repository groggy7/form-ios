import XCTest
import AVFoundation
import UIKit
import SwiftUI
@testable import FormApp

final class FormAppTests: XCTestCase {
    func testWeeklyPlanPreservesExerciseCountWithStatus() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let workout = Workout(id: "test", day: 1, title: "Test", exercises: [Exercise(name: "A"), Exercise(name: "B")])
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let count = LanguageManager.t("weekly.exerciseCount", ["count": 2])
            XCTAssertEqual("\(count) · \(LanguageManager.t("history.unfinished"))", WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: true, isMissed: false))
            XCTAssertEqual("\(count) · \(LanguageManager.t("history.missed"))", WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: false, isMissed: true))
            XCTAssertEqual(count, WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: false, isMissed: false))
            XCTAssertEqual(LanguageManager.t("weekly.restDay"), WeeklyPlanView.workoutSubtitle(workout: nil, isUnfinished: false, isMissed: false))
        }
    }

    func testOnlyPastUnstartedWorkoutDaysAreMissed() {
        for today in 0..<7 {
            for day in 0..<7 {
                XCTAssertEqual(day < today, WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: false, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: false, completed: false, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: true, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: false, unfinished: true))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: true, unfinished: true))
            }
        }
        XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: 0, todayIndex: 7, hasWorkout: true, completed: false, unfinished: false))
        XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: -1, todayIndex: 6, hasWorkout: true, completed: false, unfinished: false))
    }

    @MainActor
    func testEquipmentOptionsRenderInEnglishAndTurkishLargeText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        for (language, width, type) in [("en", 390.0, DynamicTypeSize.large), ("tr", 320.0, DynamicTypeSize.xxxLarge)] {
            LanguageManager.setLanguage(language)
            let content = VStack(alignment: .leading, spacing: 16) {
                Text(LanguageManager.t("library.equipment")).foregroundColor(AppColors.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(EquipmentCatalog.shared.categories) { category in
                        LibraryFilterOption(title: category.title, selected: category.id == "resistance-band", equipment: category, action: {})
                    }
                }
            }.padding(20).frame(width: width).background(AppColors.background).environment(\.dynamicTypeSize, type)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 180)
            XCTAssertLessThan(image.size.height, 950)
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/form-equipment-ios-\(language).png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "Equipment \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEquipmentCatalogCoverageAndFiltering() throws {
        let catalog = EquipmentCatalog.shared
        XCTAssertEqual(catalog.exercises.count, 300)
        XCTAssertEqual(Set(catalog.exercises.keys), Set(ExerciseCatalog.canonicalExercises.keys))
        XCTAssertEqual(catalog.categories.count, 7)
        XCTAssertEqual(Set(catalog.exercises.values), Set(catalog.categories.map(\.id)))
        for (id, group) in ["ez-bar-curl": "bar", "goblet-squat": "dumbbell",
                            "cable-lateral-raise": "machine", "leg-press": "machine",
                            "weighted-front-raise": "weight-plate", "svend-press": "weight-plate",
                            "weighted-pull-ups": "other"] {
            XCTAssertEqual(catalog.categoryId(id), group)
            XCTAssertTrue(catalog.matches(id, selected: group))
            XCTAssertTrue(catalog.matches(id, selected: nil))
        }
        XCTAssertEqual(catalog.categoryId("custom-dumbbell"), "other")
        XCTAssertEqual(catalog.categoryId(nil), "other")
        XCTAssertFalse(catalog.matches("ez-bar-curl", selected: "machine"))
        for category in catalog.categories {
            XCTAssertFalse(SVGPathParser.parse(category.icon).isEmpty)
            XCTAssertFalse(category.en.isEmpty)
            XCTAssertFalse(category.tr.isEmpty)
        }
    }


    func testFlexibleExerciseSearch() throws {
        func score(_ id: String, _ query: String) throws -> Int? {
            let exercise = try XCTUnwrap(ExerciseCatalog.canonicalExercises[id]).toExercise()
            return ExerciseSearch.score(.init(query), exercise: exercise)
        }
        for query in ["chest supported", "CHEST-SUPPORTED", "chest—supported", "  chest   supported  ",
                      "row chest", "supported dumb", "DB chest row"] {
            XCTAssertNotNil(try score("chest-supported-dumbbell-row", query), query)
        }
        for (id, query) in [
            ("dumbbell-romanian-deadlift", "DB RDL"), ("barbell-romanian-deadlift", "bb rdl"),
            ("standing-barbell-overhead-press", "OHP"), ("rope-triceps-pressdown", "rope pushdown"),
            ("pec-deck-fly", "butterfly"), ("push-ups", "pushups"), ("pull-ups", "pull ups"),
            ("push-ups", "SINAV"), ("push-ups", "ŞINAV"), ("pull-ups", "barfiks")
        ] { XCTAssertNotNil(try score(id, query), "\(id) / \(query)") }
        XCTAssertNil(try score("barbell-bench-press", "chest supported"))
        XCTAssertNil(try score("chest-supported-dumbbell-row", "chest bicycle"))
        XCTAssertNil(try score("barbell-back-squat", "bell"))
        XCTAssertNil(try score("pull-ups", "weighted"))
        XCTAssertNotNil(try score("weighted-pull-ups", "weighted pullup"))
        XCTAssertEqual(try score("barbell-bench-press", " --- "), 0)
        XCTAssertEqual(try score("barbell-back-squat", ""), 0)
        XCTAssertEqual(ExerciseSearch.normalize("İŞINAV GÖĞÜS ÇEKİŞ"), "isinav gogus cekis")
        let exact = Exercise(name: "RDL")
        XCTAssertLessThan(try XCTUnwrap(ExerciseSearch.score(.init("rdl"), exercise: exact)),
                          try XCTUnwrap(score("barbell-romanian-deadlift", "rdl")))
    }

    func testSearchKeywordsAndCustomExerciseCompatibility() throws {
        XCTAssertEqual(ExerciseCatalog.canonicalExercises.count, 300)
        XCTAssertTrue(ExerciseCatalog.canonicalExercises.values.allSatisfy { !$0.searchKeywords.isEmpty })
        let custom = Exercise(name: "My Chest—Supported Row", exerciseId: "custom")
        XCTAssertNotNil(ExerciseSearch.score(.init("chest supported"), exercise: custom))
        XCTAssertNotNil(ExerciseSearch.score(.init("CEKIS"), exercise: custom, category: "Çekiş"))
        XCTAssertNil(ExerciseSearch.score(.init("rdl"), exercise: custom))
        let old = Data(#"{"id":"custom","name":"Custom","movementType":"other"}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(ExerciseDefinition.self, from: old).searchKeywords.isEmpty)
    }

    func testExerciseVideoCatalogMatchesCurrentExercises() throws {
        XCTAssertEqual(ExerciseVideoCatalog.entries.count, 300)
        for id in ExerciseCatalog.canonicalExercises.keys {
            let entry = try XCTUnwrap(ExerciseVideoCatalog.entries[id], id)
            XCTAssertFalse(entry.name.isEmpty)
            let url = try XCTUnwrap(ExerciseVideoCatalog.url(for: id), id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertNil(ExerciseVideoCatalog.url(for: "unknown-custom-exercise"))
        XCTAssertEqual(ExerciseVideoCatalog.entries["face-pull"]?.videoId, "565612")
        XCTAssertEqual(ExerciseVideoCatalog.entries["goblet-squat"]?.videoId, "176012")
        XCTAssertNotEqual(ExerciseVideoCatalog.url(for: "pull-ups"),
                          ExerciseVideoCatalog.url(for: "weighted-pull-ups"))
    }

    @MainActor
    func testExerciseVideoFramingIsFullBleed() throws {
        XCTAssertEqual(ExerciseVideoCatalog.framings.count, 300)
        for id in ExerciseVideoCatalog.entries.keys {
            let crop = try XCTUnwrap(ExerciseVideoCatalog.framings[id], id)
            XCTAssertGreaterThan(crop.width, 0)
            XCTAssertGreaterThan(crop.height, 0)
            XCTAssertGreaterThanOrEqual(crop.left, 0)
            XCTAssertGreaterThanOrEqual(crop.top, 0)
            XCTAssertLessThanOrEqual(crop.left + crop.width, 1.00001)
            XCTAssertLessThanOrEqual(crop.top + crop.height, 1.00001)
            for width: CGFloat in [320, 440] {
                let size = CGSize(width: width, height: width / crop.aspectRatio)
                let frame = crop.videoFrame(in: size)
                XCTAssertEqual(frame.width / frame.height, 16 / 9, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.minY, 0)
                XCTAssertGreaterThanOrEqual(frame.maxX + 0.001, size.width)
                XCTAssertGreaterThanOrEqual(frame.maxY + 0.001, size.height)
            }
        }
        let host = UIHostingController(rootView:
            ExerciseDetailVideo(exerciseId: "barbell-bench-press").frame(width: 320)
        )
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
        XCTAssertEqual(size.width, 320, accuracy: 0.1)
        XCTAssertEqual(size.height, 256, accuracy: 0.1)
    }

    @MainActor
    func testLocalExerciseVideoPlaysAndPauses() async throws {
        let url = try XCTUnwrap(ExerciseVideoCatalog.url(for: "barbell-bench-press"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        let framing = ExerciseVideoCatalog.framing(for: "barbell-bench-press")
        let video = ExercisePlayerView(url: url, framing: framing)
        video.frame = CGRect(x: 0, y: 0, width: 320, height: 320 / framing.aspectRatio)
        controller.view.addSubview(video)
        window.isHidden = false
        // This standalone test window is not the app's key window; lay out its
        // hosted view explicitly before checking the child AVPlayerLayer.
        video.setNeedsLayout()
        video.layoutIfNeeded()
        defer { video.release(); window.isHidden = true }
        video.setPlaying(true)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(ExerciseVideoCatalog.playbackSpeed, 1.2, accuracy: 0.01)
        XCTAssertEqual(video.playbackRate, 1.2, accuracy: 0.01)
        XCTAssertGreaterThan(video.playbackTime.seconds, 0.1)
        XCTAssertEqual(video.renderedVideoFrame, framing.videoFrame(in: video.bounds.size))
        let image = UIGraphicsImageRenderer(size: video.bounds.size).image { _ in
            video.drawHierarchy(in: video.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Full-bleed centered detail video"
        attachment.lifetime = .keepAlways
        add(attachment)
        video.setPlaying(false)
        XCTAssertEqual(video.playbackRate, 0.0, accuracy: 0.01)
        let pausedAt = video.playbackTime.seconds
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(video.playbackTime.seconds, pausedAt, accuracy: 0.05)
    }

    @MainActor
    func testUnknownExerciseArtworkFramesAreEmpty() throws {
        for id in ["unknown", "band-face-pull"] {
            let renderer = ImageRenderer(content:
                MovementIllustration(exerciseId: id)
                    .frame(width: 224, height: 224)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cgImage.width, 224)
            XCTAssertEqual(cgImage.height, 224)
            // Compare rendered alpha, not PNG encoding or image color-profile metadata.
            var pixels = [UInt8](repeating: 0, count: 224 * 224 * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: 224, height: 224,
                    bitsPerComponent: 8, bytesPerRow: 224 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 224, height: 224))
            }
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy {
                pixels[$0] == 0
            }, id)
        }
        for name in ["anatomy_compound", "anatomy_dead_bug", "anatomy_pull_up",
                     "anatomy_weighted_pull_up", "anatomy_seated_leg_curl"] {
            XCTAssertNil(UIImage(named: name), "Archived artwork must not ship")
        }
    }

    @MainActor
    func testStaticStepOneThumbnails() throws {
        XCTAssertEqual(Set(ExerciseThumbnails.catalog.keys), Set(ExerciseCatalog.canonicalExercises.keys))
        for id in ExerciseThumbnails.catalog.keys {
            let image = try XCTUnwrap(ExerciseThumbnails.image(for: id), id)
            XCTAssertLessThanOrEqual(image.size.width, 384)
            XCTAssertLessThanOrEqual(image.size.height, 384)
            XCTAssertNotEqual(image.cgImage?.alphaInfo, CGImageAlphaInfo.none)
        }
        XCTAssertNil(ExerciseThumbnails.image(for: "unknown"))
        let renderer = ImageRenderer(content:
            VStack {
                MovementIllustration(exerciseId: "barbell-bench-press")
                    .frame(width: 224, height: 224).background(AppColors.exerciseThumbnailSurface)
                HStack {
                    ForEach(["face-pull", "cable-lateral-raise", "leg-press"], id: \.self) { id in
                        MovementIcon(exerciseId: id, size: 96)
                    }
                }
            }.padding(12).background(AppColors.background)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.pngData(), renderer.uiImage?.pngData())
        if let data = image.pngData() {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/static-thumbnails-ios.png"))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Static STEP1 thumbnails"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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

    func testSetJumpLimitsAndPreviousSetPrefill() throws {
        let rows = (1...3).map { ExerciseSetLog(setNumber: $0) }
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(rows), 1)
        var completed = rows
        completed[0].isCompleted = true
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 2)
        completed[1].isCompleted = true
        completed[2].isCompleted = true
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 3)
        completed[0].isCompleted = false
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 1)
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber([]), 0)
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("7,5", by: 5), "12.5")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("2.5", by: -10), "0")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("", by: 10), "10")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("9999.99", by: 10), "9999.99")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("1", by: -1), "")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("", by: 1), "1")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("999", by: 1), "999")
        let source = ExerciseSetLog(setNumber: 1, weightInput: "62.5", repsInput: "10", isCompleted: true)
        let blank = ExerciseSetLog(id: "next", setNumber: 2)
        let next = WorkoutSessionUtils.prefillSet(blank, from: source)
        XCTAssertEqual(next.id, blank.id)
        XCTAssertEqual(next.weightKg, 62.5)
        XCTAssertEqual(next.completedReps, 10)
        XCTAssertFalse(next.isCompleted)
        var cleared = blank
        cleared.inputTouched = true
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(cleared, from: source), cleared)
        var partial = blank
        partial.weightInput = "20"
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(partial, from: source), partial)
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(blank, from: nil), blank)
        let persisted = try JSONDecoder().decode(ExerciseSetLog.self, from: JSONEncoder().encode(cleared))
        XCTAssertEqual(persisted.inputTouched, true)
        let legacy = #"{"id":"old","setNumber":1,"weightInput":"","repsInput":"","isCompleted":false}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(ExerciseSetLog.self, from: legacy).inputTouched)
    }

    @MainActor
    func testSetJumpControlsNarrowSnapshots() throws {
        defer { LanguageManager.setLanguage("en") }
        func textFields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields($0) }
        }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for index in 0..<2 {
            let content = SetLoggingTable(sets: (1...3).map { ExerciseSetLog(setNumber: $0, weightInput: "12.5", repsInput: "10") }, prescription: "3 × 6–10",
                onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in }, onAddSet: {}, onRemoveSet: { _ in })
                .padding(16).environment(\.dynamicTypeSize, .xLarge)
                .frame(width: 320).background(AppColors.background)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let fields = textFields(host.view)
            XCTAssertEqual(fields.count, 6)
                window.endEditing(true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let field = try XCTUnwrap(textFields(host.view).filter { !$0.isHidden }.dropFirst(index).first)
                XCTAssertTrue(field.becomeFirstResponder())
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "set-jumps-\(language)-\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/set-jumps-ios-\(language)-\(index).png"))
            window.endEditing(true)
            window.isHidden = true
            }
        }
    }

    func testSanitizedWeightInput() {
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("50"), "50")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52.5"), "52.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52,5"), "52.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput(""), "")
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("0"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("00"))
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("015"), "15")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("05"), "5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("0.5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("00.5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput(".5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("0."), "0.")
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
        XCTAssertEqual(bundled.count, 8, "Expected all 8 starter programs")
        XCTAssertEqual(bundled.first?.name, "Aesthetic Engine: 5-Day Hypertrophy")
        XCTAssertEqual(bundled.map { $0.workouts.count }, [5, 4, 6, 3, 4, 3, 4, 3])
        let canonical = AppStore.loadBundledExercises()
        for exercise in bundled.flatMap({ $0.workouts }).flatMap({ $0.exercises }) {
            XCTAssertNotNil(exercise.exerciseId.flatMap { canonical[$0] })
            XCTAssertNotNil(exercise.reps?.min)
            XCTAssertEqual(exercise.reps?.toFailure, false)
        }
    }

    func testStarterRefreshPreservesIndependentProgramsAndIsIdempotent() {
        let bundled = AppStore.loadBundledStarterPrograms()
        let old = Program(id: "aesthetic-hypertrophy", name: "Old template")
        let custom = Program(id: "my-copy", name: "My edited plan")
        let refreshed = AppStore.refreshedStarterPrograms(existing: [old, custom], bundled: bundled)
        XCTAssertEqual(refreshed.count, 9)
        XCTAssertEqual(refreshed.first, bundled.first)
        XCTAssertEqual(refreshed.last, custom)
        XCTAssertEqual(AppStore.refreshedStarterPrograms(existing: refreshed, bundled: bundled), refreshed)
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
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

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
    func testLibraryViewTurkishSnapshot() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let store = AppStore.shared
        let libraryView = LibraryView(store: store, onSelectExercise: { _ in }, onOpenSettings: {})
        let controller = UIHostingController(rootView: libraryView)
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_library_tr_snapshot.png"
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
    func testExerciseDetailTechniqueSectionsExpandedSnapshot() {
        let cuesView = VStack(spacing: 16) {
            TechniqueSectionView(
                title: "Technique cues",
                text: "Plant heels, arch upper back, tuck shoulder blades.\nLower bar to sternum under control.\nExplode upward with leg drive.",
                accent: AppColors.accent,
                isAvoid: false,
                initiallyExpanded: true
            )

            TechniqueSectionView(
                title: "What to avoid",
                text: "Bouncing bar off ribcage.\nButt lifting off the bench.",
                accent: AppColors.danger,
                isAvoid: true,
                initiallyExpanded: true
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: cuesView)
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_expanded_cues.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testExerciseDetailNavigationFromTodayAndLibrary() {
        let store = AppStore.shared
        store.currentView = .today
        XCTAssertEqual(store.currentView, .today)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)

        // Opening exercise from Today
        store.openExercise(id: "barbell-bench-press")
        XCTAssertEqual(store.currentView, .library)
        XCTAssertEqual(store.selectedExerciseId, "barbell-bench-press")
        XCTAssertEqual(store.returnView, .today)

        // Pressing back returns to Today
        store.selectExerciseInLibrary(id: nil)
        XCTAssertEqual(store.currentView, .today)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)

        // Opening exercise directly in Library
        store.currentView = .library
        store.selectExerciseInLibrary(id: "barbell-bench-press")
        XCTAssertEqual(store.currentView, .library)
        XCTAssertEqual(store.selectedExerciseId, "barbell-bench-press")
        XCTAssertNil(store.returnView)

        // Pressing back stays in Library
        store.selectExerciseInLibrary(id: nil)
        XCTAssertEqual(store.currentView, .library)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)
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
        XCTAssertEqual(LanguageManager.t("modal.program.titleEdit"), "Edit program")
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

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
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

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
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

    @MainActor
    func testHistoryDayDetailSheetUnfinishedExpandedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-expanded",
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

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {}, initiallyExpanded: true)
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 1100)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_expanded_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetTurkishSnapshot() {
        let prevLang = LanguageManager.shared.currentLanguage
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage(prevLang) }

        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-tr",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Göğüs & Arka Kol",
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

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_turkish_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetCompletedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-completed",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Chest Growth",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:45:12.000Z",
            durationSeconds: 2712,
            totalVolumeKg: 5250,
            totalCompletedSets: 6,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 24, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .completed,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(
            detail: detail,
            history: [sampleRecord],
            onDismiss: {},
            onActionWorkout: {},
            initiallyExpanded: true
        )
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_completed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayPreviewCardSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "chest-workout",
            day: 1,
            title: "Chest & Triceps",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Cable Fly", sets: 3),
                Exercise(name: "Triceps Pushdown", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let priorRecord = WorkoutSessionRecord(
            id: "prior-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-08-25T10:00:00.000Z",
            completedAt: "2026-08-25T10:45:00.000Z",
            durationSeconds: 2700,
            totalVolumeKg: 4000,
            totalCompletedSets: 6,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80, reps: 8)],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let currentRecord = WorkoutSessionRecord(
            id: "current-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:48:30.000Z",
            durationSeconds: 2910,
            totalVolumeKg: 6200,
            totalCompletedSets: 12,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 2, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 100, reps: 6)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 28, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 28, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 28, reps: 8)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Cable Fly",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 15, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 15, reps: 12)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Triceps Pushdown",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 25, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 25, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 25, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .completed,
            sessionRecord: currentRecord,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [priorRecord, currentRecord],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testHistoryDayPreviewCardUnfinishedSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "unfinished-test-workout",
            day: 1,
            title: "Push Day",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Sled Hack Squat", sets: 3),
                Exercise(name: "Leg Press", sets: 3),
                Exercise(name: "Leg Extension", sets: 3),
                Exercise(name: "Standing Calf Raise", sets: 3),
                Exercise(name: "Seated Cable Row", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-03")!

        let currentRecord = WorkoutSessionRecord(
            id: "unfinished-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-09-03T10:00:00.000Z",
            completedAt: "2026-09-03T10:25:00.000Z",
            durationSeconds: 1500,
            totalVolumeKg: 2400,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 2, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 100, reps: 6)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 28, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-03",
            status: .unfinished,
            sessionRecord: currentRecord,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [currentRecord],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_unfinished_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testHistoryDayPreviewCardMissedSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "missed-test-workout",
            day: 1,
            title: "Chest & Triceps",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Cable Fly", sets: 3),
                Exercise(name: "Triceps Pushdown", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-01")!

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-01",
            status: .missed,
            sessionRecord: nil,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_missed_snapshot.png"
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
        _ = store.startActiveSession(programId: program.id, workout: tuesdayWorkout, allowPast: true)
        guard let draft = store.activeSession else {
            XCTFail("Active session failed to start")
            return
        }

        // Verify that draft is assigned to Tuesday in the current week
        let tuesdayDate = WorkoutCalendar.scheduledDate(forWeekday: 2, relativeTo: Date())
        let sessionEntry = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })
        XCTAssertNotNil(sessionEntry)
        XCTAssertEqual(sessionEntry?.date, tuesdayDate)
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
        let tuesdayDateObj = WorkoutCalendar.parseDate(tuesdayDate) ?? Date()
        let statuses = store.calendarStatuses(today: tuesdayDateObj)
        XCTAssertEqual(statuses[tuesdayDate], .unfinished, "Tuesday must be orange (.unfinished), not red (.missed)!")

        // History list must contain record for Tuesday
        let foundRecord = store.state.history.first { rec in
            WorkoutCalendar.localDate(from: rec.startedAt) == tuesdayDate ||
            store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date == tuesdayDate
        }
        XCTAssertNotNil(foundRecord, "Record must be mapped to \(tuesdayDate)")
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

    func testAppStoreSetExerciseVideos() throws {
        let store = AppStore.shared
        let previous = store.state
        let previousCatalogue = store.exerciseCatalogue
        let previousNotice = store.noticeMessage
        defer {
            store.state = previous; store.saveState(previous)
            store.exerciseCatalogue = previousCatalogue; store.noticeMessage = previousNotice
        }
        let exerciseName = "Barbell Back Squat"

        let testUrls = [
            "https://youtu.be/ZaTM37cfiDs",
            "youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/ZaTM37cfiDs", // duplicate
            "https://youtube.com/shorts/3jzKvd6e2q4",
            "https://youtube.com/watch?v=abcdefghijk" // 4th valid link, capped at 3
        ]

        store.setExerciseVideos(exerciseName: exerciseName, videoUrls: testUrls)

        let catalogEntry = store.exerciseCatalogue.first { $0.key == exerciseName.lowercased() }
        XCTAssertNotNil(catalogEntry)
        XCTAssertEqual(catalogEntry?.exercise.videos.count, 3, "Videos count must be capped at 3")
        XCTAssertEqual(catalogEntry?.exercise.videos[0], "https://youtu.be/ZaTM37cfiDs")
        XCTAssertEqual(catalogEntry?.exercise.videos[1], "https://youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(catalogEntry?.exercise.videos[2], "https://youtube.com/shorts/3jzKvd6e2q4")
        XCTAssertNotNil(store.noticeMessage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = try encoder.encode(store.state)
        store.setExerciseVideos(exerciseName: exerciseName, videoUrls: ["https://vimeo.com/123"])
        XCTAssertEqual(try encoder.encode(store.state), saved)
        XCTAssertEqual(store.noticeMessage, LanguageManager.t("video.youtubeOnly"))
    }

    func testExerciseMuscleCatalog() throws {
        let catalog = try XCTUnwrap(ExerciseMuscleCatalog.shared)
        XCTAssertEqual(catalog.exercises.count, 300)
        XCTAssertNil(catalog.profile(nil))
        XCTAssertNil(catalog.profile("unknown"))
        XCTAssertNotNil(catalog.profile("barbell-back-squat"))
        for (_, profile) in catalog.exercises {
            XCTAssertFalse(profile.primary.isEmpty)
            XCTAssertEqual(Set(profile.all).count, profile.all.count)
            XCTAssertFalse(profile.sources.isEmpty)
            XCTAssertTrue(catalog.availableViews(profile).contains(profile.initialView))
            for muscle in profile.all {
                XCTAssertNotNil(catalog.muscles[muscle]?["en"])
                XCTAssertNotNil(catalog.muscles[muscle]?["tr"])
                XCTAssertTrue(catalog.views.values.contains { $0.regions[muscle] != nil })
            }
        }
        XCTAssertEqual(ExerciseMuscleCatalog.images.count, 2)
        for image in ExerciseMuscleCatalog.images.values {
            XCTAssertEqual(image.size, CGSize(width: 480, height: 1024))
        }
    }

    @MainActor
    func testExerciseMusclePanelRenders() throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        for (id, name, language, width, type) in [
            ("barbell-bench-press", "bench", "en", 350.0, DynamicTypeSize.large),
            ("pull-ups", "pull", "tr", 280.0, DynamicTypeSize.xxxLarge),
            ("seated-leg-curl", "legs", "en", 350.0, DynamicTypeSize.large),
            ("unknown", "unknown", "en", 280.0, DynamicTypeSize.large)
        ] {
            LanguageManager.setLanguage(language)
            let renderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: id, initiallyExpanded: true)
                .environment(\.dynamicTypeSize, type).frame(width: width))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 60)
            XCTAssertLessThan(image.size.height, 750)
            try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/form-muscles-ios-\(name).png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "Muscle panel \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testExerciseMusclesCardCollapsedByDefault() throws {
        LanguageManager.setLanguage("en")
        let renderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: "barbell-bench-press")
            .frame(width: 350))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertLessThan(image.size.height, 90)
    }

    func testVideoDuplicatesPreserveCaseSensitiveIdsAndFirstTimestamp() {
        let first = "https://youtu.be/ZaTM37cfiDs?t=90"
        let same = "https://youtube.com/shorts/ZaTM37cfiDs?t=30"
        let different = "https://youtu.be/zaTM37cfiDs?t=90"
        XCTAssertTrue(YouTubeVideo.isSameVideo(first, same))
        XCTAssertFalse(YouTubeVideo.isSameVideo(first, different))
        XCTAssertFalse(YouTubeVideo.isSameVideo("invalid", "invalid"))
        XCTAssertFalse(YouTubeVideo.isSameVideo(first, "invalid"))
        XCTAssertEqual(YouTubeVideo.validatedLinks([first, same, different]), [first, different])
    }

    func testProgramExportTranslation() {
        XCTAssertEqual(Translations.en["programs.export"], "Export")
        XCTAssertEqual(Translations.tr["programs.export"], "Dışa aktar")
    }

    func testExerciseLinksAcceptOnlyYouTubeVideosAndShorts() {
        let id = "ZaTM37cfiDs"
        for url in [" youtube.com/watch?v=\(id) ", "youtu.be/\(id)?si=share", "https://youtube.com/shorts/\(id)",
                    "https://m.youtube.com/watch?v=\(id)&t=90", "https://www.youtube-nocookie.com/embed/\(id)"] {
            XCTAssertTrue(YouTubeVideo.isSupportedLink(url), url)
        }
        for url in ["https://vimeo.com/123", "https://example.com/video.mp4", "youtube.com", "youtube.com/@trainer",
                    "youtube.com/playlist?list=PL123", "youtube.com/watch?v=short", "youtube.com.evil.com/watch?v=\(id)",
                    "https://user@youtube.com/watch?v=\(id)", "ftp://youtube.com/watch?v=\(id)", "", "not a url",
                    "https://youtube.com/watch?v=\(id)&x=" + String(repeating: "a", count: 2_000)] {
            XCTAssertFalse(YouTubeVideo.isSupportedLink(url), url)
        }
        XCTAssertNil(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://example.com"]))
        XCTAssertEqual(YouTubeVideo.validatedLinks([]), [])
        XCTAssertEqual(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://youtu.be/\(id)", " "]), ["https://youtu.be/\(id)"])
        XCTAssertEqual(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://www.youtube.com/watch?v=\(id)&si=xyz", "https://youtube.com/shorts/\(id)"]), ["https://youtu.be/\(id)"])
        XCTAssertEqual(YouTubeVideo.parse("https://youtu.be/\(id)?t=9223372036854775807h")?.startSeconds, 604800)
    }

    func testAppStoreExerciseCatalogueContainsAll300Exercises() {
        let store = AppStore()
        XCTAssertEqual(store.exerciseCatalogue.count, 300)
    }

    func testLegacyExerciseNameWithCanonicalExerciseIdMergesUnderCanonicalName() {
        let legacyExercise = Exercise(
            name: "Conventional Barbell Deadlift",
            exerciseId: "conventional-barbell-deadlift"
        )
        let legacyWorkout = Workout(id: "w-leg", day: 1, title: "Legs", exercises: [legacyExercise])
        let legacyProgram = Program(id: "p-leg", name: "Legacy", workouts: [legacyWorkout])
        let entries = ExerciseCatalog.build(
            bundledPrograms: [],
            userPrograms: [legacyProgram],
            canonicalExercises: Array(ExerciseCatalog.canonicalExercises.values)
        )
        XCTAssertEqual(entries.count, 300)
        let deadlift = entries.first { $0.exercise.exerciseId == "conventional-barbell-deadlift" }
        XCTAssertEqual(deadlift?.key, "deadlift")
        XCTAssertEqual(deadlift?.exercise.name, "Deadlift")
        XCTAssertTrue(deadlift?.programIds.contains("p-leg") ?? false)
    }

    func testVideoTranslationsParity() {
        let requiredKeys = [
            "video.openExternal", "video.close", "video.back5", "video.forward5",
            "video.play", "video.pause", "video.resume", "video.replay",
            "video.loading", "video.retry", "video.invalid", "video.youtubeOnly", "video.networkError", "video.embedError",
            "video.linkTitle", "video.linkSubtitle", "video.urlInputLabel", "video.urlInputPlaceholder",
            "video.addUrlButton", "video.paste", "video.preview",
            "video.linkedCount", "video.maxReached", "video.maxReachedHint", "video.alreadyAdded",
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

        XCTAssertEqual(catalogue.count, 300)
        XCTAssertEqual(catalogue.count, Set(catalogue.map { $0.key }).count)
        XCTAssertEqual(catalogue.filter { $0.exercise.movementAssetId != nil }.count, 50)
        XCTAssertEqual(catalogue.filter { !$0.exercise.cues.isEmpty }.count, 300)
        XCTAssertEqual(catalogue.filter { !$0.exercise.avoid.isEmpty }.count, 300)
        XCTAssertEqual(catalogue.filter { $0.exercise.exerciseId != nil }.count, 300)
    }

    func testCanonicalExercisesProvideTurkishCuesAndAvoid() {
        let canonical = Array(ExerciseCatalog.canonicalExercises.values)
        XCTAssertEqual(canonical.count, 300)
        let trExercises = ContentLocalizer.shared.loadExercises(lang: "tr")
        XCTAssertEqual(trExercises.count, 300)
        XCTAssertEqual(trExercises.values.filter { ($0.cues ?? []).count > 0 }.count, 300)
        XCTAssertEqual(trExercises.values.filter { ($0.avoid ?? []).count > 0 }.count, 300)

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
        XCTAssertEqual(localizedFirstCue, trExercises["barbell-bench-press"]?.cues?.first)
    }

    func testContentLocalizerResolution() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let pullUps = Exercise(name: "Pull-Ups", exerciseId: "pull-ups")
        XCTAssertEqual(pullUps.displayName, "Barfiks")
        XCTAssertTrue(pullUps.displayCues.contains("Barı omuzlardan biraz geniş"))

        let bench = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press")
        XCTAssertEqual(bench.displayName, "Barbell Bench Press")

        let deadlift = Exercise(name: "Deadlift", exerciseId: "conventional-barbell-deadlift")
        XCTAssertEqual(deadlift.displayName, "Deadlift")

        let smithSquat = Exercise(name: "Smith Machine Squat", exerciseId: "smith-squat")
        XCTAssertEqual(smithSquat.displayName, "Smith Makinesi Squat")

        let workout = Workout(id: "pb-squat-strength", day: 1, title: "Heavy Squat", focus: "Maximal squat power, quad density, and core bracing")
        XCTAssertEqual(workout.displayTitle(programId: "powerbuilding-strength"), "Alt Vücut: Squat")
        XCTAssertEqual(workout.displayFocus(programId: "powerbuilding-strength"), "Squat tekniği, arka bacak ve baldır")

        let program = Program(id: "powerbuilding-strength", name: "Heavy & Built: 4-Day Powerbuilding")
        XCTAssertEqual(program.displayName, "Heavy & Built: 4 Günlük Güç ve Kas")
        XCTAssertEqual(Program(id: "machine-foundation", name: "fallback").displayName, "Machine Foundation: 3 Günlük Tüm Vücut")
        XCTAssertEqual(Program(id: "upper-lower-balanced", name: "fallback").displayName, "Balanced Build: 4 Günlük Üst/Alt Vücut")

        // English check
        LanguageManager.setLanguage("en")
        XCTAssertEqual(pullUps.displayName, "Pull-Ups")
        XCTAssertEqual(workout.displayTitle(programId: "powerbuilding-strength"), "Lower: Squat")
    }

    func testExercisePriorityStaplesBeforeGymRatMoves() {
        XCTAssertEqual(ExercisePriority.orderedIds.count, 300)
        XCTAssertEqual(Set(ExercisePriority.orderedIds).count, 300)

        let benchRank = ExercisePriority.priority(for: "barbell-bench-press")
        let squatRank = ExercisePriority.priority(for: "barbell-back-squat")
        let deadliftRank = ExercisePriority.priority(for: "conventional-barbell-deadlift")
        let pullUpRank = ExercisePriority.priority(for: "pull-ups")
        let latPulldownRank = ExercisePriority.priority(for: "lat-pulldown")

        let svendPressRank = ExercisePriority.priority(for: "svend-press")
        let tatePressRank = ExercisePriority.priority(for: "dumbbell-tate-press")
        let zercherSquatRank = ExercisePriority.priority(for: "barbell-full-zercher-squat")
        let larsenPressRank = ExercisePriority.priority(for: "barbell-larsen-press")
        let gorillaRowRank = ExercisePriority.priority(for: "dumbbell-gorilla-row")
        let tibialisRaiseRank = ExercisePriority.priority(for: "wall-supported-tibialis-raise")
        let kasGluteBridgeRank = ExercisePriority.priority(for: "barbell-kas-glute-bridge")

        // Staples in top 40
        XCTAssertTrue(benchRank < 40)
        XCTAssertTrue(squatRank < 40)
        XCTAssertTrue(deadliftRank < 40)
        XCTAssertTrue(pullUpRank < 40)
        XCTAssertTrue(latPulldownRank < 40)

        // Niche gym-rat moves in bottom 50 (> 250)
        XCTAssertTrue(svendPressRank > 250)
        XCTAssertTrue(tatePressRank > 250)
        XCTAssertTrue(zercherSquatRank > 250)
        XCTAssertTrue(larsenPressRank > 250)
        XCTAssertTrue(gorillaRowRank > 250)
        XCTAssertTrue(tibialisRaiseRank > 250)
        XCTAssertTrue(kasGluteBridgeRank > 250)
    }

    func testTurkishPossessiveNumberAndSetsProgress() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 5), "5 setten 4'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 4), "4 setten 4'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 0, total: 3), "3 setten 0'ı tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 1, total: 3), "3 setten 1'i tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 2, total: 3), "3 setten 2'si tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 3, total: 3), "3 setten 3'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 5, total: 5), "5 setten 5'i tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 6, total: 6), "6 setten 6'sı tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 10, total: 10), "10 setten 10'u tamamlandı")

        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 5), "4 of 5 sets")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 4), "4 of 4 sets")
    }

    func testUncompletedExercisesCountFormatting() {
        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(1), "1 uncompleted exercise")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(6), "6 uncompleted exercises")

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(1), "1 tamamlanmamış egzersiz")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(6), "6 tamamlanmamış egzersiz")
        LanguageManager.setLanguage("en")
    }

    func testCompletedExercisesCountFormatting() {
        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(1), "1 completed exercise")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(6), "6 completed exercises")

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(1), "1 tamamlanan egzersiz")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(6), "6 tamamlanan egzersiz")
        LanguageManager.setLanguage("en")
    }

    func testSessionProgressTargetSetsWhenSetDeleted() {
        let exercise = Exercise(id: "squat", name: "Barbell Back Squat", sets: 5)
        let workout = Workout(id: "w1", day: 1, title: "Heavy Squat", exercises: [exercise])
        // 4 sets remaining out of 5, all completed
        let sets = (1...4).map { setNum in
            ExerciseSetLog(
                id: "set-\(setNum)",
                setNumber: setNum,
                weightKg: 100,
                completedReps: 5,
                isCompleted: true
            )
        }
        let draft = ActiveSessionDraft(
            id: "draft-1",
            programId: "prog-1",
            workout: workout,
            startedAt: "2026-09-05T10:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: ["squat": sets]
        )

        let progress = SessionProgress.from(draft: draft, nowEpochMillis: 2000)
        let log = progress.exerciseLogs.first
        XCTAssertEqual(log?.sets.count, 4)
        XCTAssertEqual(log?.targetSets, 4)
    }

    func testRestoreSetsFromHistoryRespectsTargetSetsWhenSetDeleted() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", sets: 4)
        let workout = Workout(id: "w1", day: 1, title: "Chest", exercises: [exercise])

        // User deleted set 4 (targetSets = 3), completed 1 set
        let record1 = WorkoutSessionRecord(
            id: "rec-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:15:00Z",
            durationSeconds: 900,
            totalVolumeKg: 800,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored1 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record1)["bench"] ?? []
        XCTAssertEqual(restored1.count, 3)
        XCTAssertTrue(restored1[0].isCompleted)
        XCTAssertFalse(restored1[1].isCompleted)
        XCTAssertFalse(restored1[2].isCompleted)

        // User deleted set 4 (targetSets = 3), completed 0 sets
        let record2 = WorkoutSessionRecord(
            id: "rec-2",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:05:00Z",
            durationSeconds: 300,
            totalVolumeKg: 0,
            totalCompletedSets: 0,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored2 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record2)["bench"] ?? []
        XCTAssertEqual(restored2.count, 3)
        XCTAssertTrue(restored2.allSatisfy { !$0.isCompleted })

        // User deleted set 4 (targetSets = 3), completed all 3 sets
        let record3 = WorkoutSessionRecord(
            id: "rec-3",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:25:00Z",
            durationSeconds: 1500,
            totalVolumeKg: 2400,
            totalCompletedSets: 3,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored3 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record3)["bench"] ?? []
        XCTAssertEqual(restored3.count, 3)
        XCTAssertTrue(restored3.allSatisfy { $0.isCompleted })
    }

    func testIsoDateParserFractionalSeconds() {
        let withFractional = "2026-09-05T14:45:12.345Z"
        let withoutFractional = "2026-09-05T14:45:12Z"

        let d1 = WorkoutCalendar.parseIsoTimestamp(withFractional)
        XCTAssertNotNil(d1)
        let d2 = WorkoutCalendar.parseIsoTimestamp(withoutFractional)
        XCTAssertNotNil(d2)

        let local1 = WorkoutCalendar.localDate(from: withFractional)
        let local2 = WorkoutCalendar.localDate(from: withoutFractional)
        XCTAssertEqual(local1, local2)
    }

    func testResumeWorkoutRestoresCompletedSetsAndTimer() {
        let store = AppStore.shared
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 2 }) else {
            XCTFail("Requires a workout with at least 2 exercises")
            return
        }

        // Clean state for this workout
        store.activeSession = nil
        var st = store.state
        st.history.removeAll { $0.workoutId == workout.id }
        st.completed.removeAll { $0.contains(workout.id) }
        store.saveState(st)

        // 1. Start workout
        let started = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(started)
        guard let initialDraft = store.activeSession else {
            XCTFail("Failed to start initial active session")
            return
        }

        // Verify timer starts near 0, NOT 5 days in the past or stuck at 8 hours!
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedInitial = SessionProgress.from(draft: initialDraft, nowEpochMillis: nowMillis).durationSeconds
        XCTAssertLessThan(elapsedInitial, 5, "Initial workout timer must start at 0, not stuck at hours")

        // 2. Complete all sets on first exercise
        let firstEx = workout.exercises[0]
        let targetFirstCount = WorkoutSessionUtils.initialSetCount(exercise: firstEx)
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 85.0
                sets[i].weightInput = "85"
                sets[i].completedReps = 8
                sets[i].repsInput = "8"
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // 3. Exit workout with progress (calls abandonActiveSession)
        store.abandonActiveSession()
        XCTAssertNil(store.activeSession, "Active session should be nil after exiting")

        // 4. Verify unfinished workout key is present and record in history
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let expectedKey = "\(program.id):\(workout.id)"
        XCTAssertTrue(unfinishedKeys.contains(expectedKey), "Unfinished key must be present in unfinishedWorkoutKeys")

        let unfinishedRecord = store.state.history.first { $0.workoutId == workout.id && $0.isComplete == false }
        XCTAssertNotNil(unfinishedRecord, "Unfinished record must be saved in history")

        // 5. Resume workout
        let resumed = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(resumed, "Resuming workout should succeed")
        guard let resumedDraft = store.activeSession else {
            XCTFail("Active session was not restored")
            return
        }

        // 6. Verify first exercise sets are completely restored
        let restoredSets = resumedDraft.setsByExercise[firstEx.id] ?? []
        XCTAssertEqual(restoredSets.count, targetFirstCount)
        XCTAssertTrue(restoredSets.allSatisfy { $0.isCompleted }, "All sets of first exercise must be marked completed")
        XCTAssertEqual(restoredSets.first?.weightKg, 85.0)
        XCTAssertEqual(restoredSets.first?.completedReps, 8)

        // 7. Verify currentExerciseIndex advanced to index 1 (the next incomplete exercise)
        XCTAssertEqual(resumedDraft.currentExerciseIndex, 1, "Workout should resume at first incomplete exercise")

        // 8. Clean up
        store.abandonActiveSession()
    }

    @MainActor
    func testActiveSessionResumedSnapshot() {
        let store = AppStore.shared
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 2 }) else {
            return
        }

        let firstEx = workout.exercises[0]
        let firstSets = (1...3).map {
            ExerciseSetLog(id: "s\($0)", setNumber: $0, weightInput: "80", repsInput: "10", weightKg: 80, completedReps: 10, isCompleted: true)
        }
        let secondEx = workout.exercises[1]
        let secondSets = (1...3).map {
            ExerciseSetLog(id: "s2_\($0)", setNumber: $0, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        }

        let draft = ActiveSessionDraft(
            id: "test-resumed-draft",
            programId: program.id,
            workout: workout,
            startedAt: "2026-09-05T10:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000) - 245_000, // 4m 05s elapsed
            currentExerciseIndex: 1,
            setsByExercise: [
                firstEx.id: firstSets,
                secondEx.id: secondSets
            ]
        )

        store.activeSession = draft
        let sessionView = ActiveSessionView(store: store, draft: draft)
        let controller = UIHostingController(rootView: sessionView)
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_resumed_session_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        store.abandonActiveSession()
    }

    @MainActor
    func testCompletedSetsAndDeletedSetReflectedInHistoryDetail() {
        let store = AppStore.shared
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 3 }) else {
            XCTFail("Requires a workout with at least 3 exercises")
            return
        }

        // Clean any leftover session
        store.abandonActiveSession()

        // 1. Start active session
        let started = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(started)
        guard var draft = store.activeSession else {
            XCTFail("Failed to start active session")
            return
        }

        let ex1 = workout.exercises[0]
        let ex2 = workout.exercises[1]
        let ex3 = workout.exercises[2]

        // 2. Complete all sets for exercise 1
        let ex1Target = WorkoutSessionUtils.initialSetCount(exercise: ex1)
        var ex1Sets = (1...ex1Target).map {
            ExerciseSetLog(id: "ex1_s\($0)", setNumber: $0, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true)
        }
        draft.setsByExercise[ex1.id] = ex1Sets

        // 3. For exercise 2, simulate deleting last set and completing the remaining sets
        let ex2OriginalCount = WorkoutSessionUtils.initialSetCount(exercise: ex2)
        let ex2NewCount = max(1, ex2OriginalCount - 1)
        var ex2Sets = (1...ex2NewCount).map {
            ExerciseSetLog(id: "ex2_s\($0)", setNumber: $0, weightInput: "24", repsInput: "12", weightKg: 24, completedReps: 12, isCompleted: true)
        }
        draft.setsByExercise[ex2.id] = ex2Sets

        // 4. Exercise 3 remains incomplete (0 sets done)
        let ex3Target = WorkoutSessionUtils.initialSetCount(exercise: ex3)
        draft.setsByExercise[ex3.id] = (1...ex3Target).map {
            ExerciseSetLog(id: "ex3_s\($0)", setNumber: $0, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        }

        store.activeSession = draft

        // 5. Complete active session (unfinished / partial session)
        let nowEpoch = Int64(Date().timeIntervalSince1970 * 1000)
        let progress = SessionProgress.from(draft: draft, nowEpochMillis: nowEpoch)
        let record = progress.record(draft: draft, completedAtEpochMillis: nowEpoch)
        store.completeActiveSession(record)

        XCTAssertNil(store.activeSession, "Active session should be cleared after completion")

        // 6. Verify calendar entry exists and find the date
        guard let entry = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(record.id)" }) else {
            XCTFail("Calendar entry for session was not found")
            return
        }
        XCTAssertEqual(entry.status, .unfinished)

        // 7. Verify History lookup finds the session record for that day
        let dateString = entry.date
        let historyRecord = store.state.history.first { rec in
            if let calDate = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == dateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == dateString || completedDate == dateString
        }

        XCTAssertNotNil(historyRecord, "Session record must be resolved for date \(dateString)")
        guard let resolvedRec = historyRecord else { return }

        // Total completed sets: ex1 (ex1Target) + ex2 (ex2NewCount)
        XCTAssertEqual(resolvedRec.totalCompletedSets, ex1Target + ex2NewCount)

        // 8. Verify exercise breakdown
        let ex1Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex1.name.lowercased() })
        XCTAssertNotNil(ex1Log)
        XCTAssertEqual(ex1Log?.sets.count, ex1Target)
        XCTAssertEqual(ex1Log?.targetSets, ex1Target)

        let ex2Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex2.name.lowercased() })
        XCTAssertNotNil(ex2Log)
        XCTAssertEqual(ex2Log?.sets.count, ex2NewCount)
        XCTAssertEqual(ex2Log?.targetSets, ex2NewCount, "Target sets for exercise 2 should reflect deleted set (\(ex2NewCount) not \(ex2OriginalCount))")

        let ex3Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex3.name.lowercased() })
        XCTAssertNotNil(ex3Log)
        XCTAssertEqual(ex3Log?.sets.count, 0)
        XCTAssertEqual(ex3Log?.targetSets, ex3Target)

        // 9. Snapshot rendering of the detail sheet
        let detailData = HistoryDayDetailData(
            date: Date(),
            dateString: dateString,
            status: .unfinished,
            sessionRecord: resolvedRec,
            workout: workout
        )
        let sheetView = HistoryDayDetailSheet(detail: detailData, onDismiss: {})
        let controller = UIHostingController(rootView: sheetView)
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_completed_and_deleted_set.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testSessionRecordDoesNotLeakToAnotherDay() {
        // Monday workout done physically on Saturday (startedAt = 2026-09-05)
        // but scheduled/mapped to Monday (2026-08-31) in calendarHistory.
        let mondayRecord = WorkoutSessionRecord(
            id: "monday-workout-id",
            programId: "prog-1",
            workoutId: "w-mon",
            workoutTitle: "Chest & Triceps",
            startedAt: "2026-09-05T15:39:17.662Z",
            completedAt: "2026-09-05T16:06:17.662Z",
            durationSeconds: 27,
            totalVolumeKg: 2720,
            totalCompletedSets: 18,
            exerciseLogs: [],
            isComplete: true
        )

        let calHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-31",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:monday-workout-id", date: "2026-08-31", status: .completed)
            ]
        )

        let history = [mondayRecord]

        // Looking up for Saturday September 5 (2026-09-05)
        let saturdayDateString = "2026-09-05"
        let saturdayMatch = history.first { rec in
            if let calDate = calHistory.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == saturdayDateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == saturdayDateString || completedDate == saturdayDateString
        }

        XCTAssertNil(saturdayMatch, "Saturday lookup must NOT match Monday's session record even if startedAt was today!")

        // Looking up for Monday August 31 (2026-08-31)
        let mondayDateString = "2026-08-31"
        let mondayMatch = history.first { rec in
            if let calDate = calHistory.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == mondayDateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == mondayDateString || completedDate == mondayDateString
        }

        XCTAssertNotNil(mondayMatch, "Monday lookup must match Monday's session record")
        XCTAssertEqual(mondayMatch?.id, "monday-workout-id")
    }

    func testWorkoutCalendarRestorePrunesOrphanSessionEntries() {
        let realSession = WorkoutSessionRecord(
            id: "real-session-id",
            programId: "prog-1",
            workoutId: "w-1",
            workoutTitle: "Upper",
            startedAt: "2026-08-31T10:00:00Z",
            completedAt: "2026-08-31T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000,
            totalCompletedSets: 10,
            exerciseLogs: [],
            isComplete: true
        )

        let rawHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-31",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:real-session-id", date: "2026-08-31", status: .completed),
                WorkoutDayEntry(id: "session:active-draft-id", date: "2026-09-05", status: .unfinished),
                WorkoutDayEntry(id: "session:stale-orphan-id", date: "2026-09-05", status: .unfinished)
            ]
        )

        // Restore with activeSessionId = "active-draft-id"
        let restored = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [realSession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: "active-draft-id"
        )

        XCTAssertTrue(restored.entries.contains { $0.id == "session:real-session-id" })
        XCTAssertTrue(restored.entries.contains { $0.id == "session:active-draft-id" })
        XCTAssertFalse(restored.entries.contains { $0.id == "session:stale-orphan-id" }, "Orphan entry must be pruned!")

        // Restore without activeSession (e.g. idle today)
        let restoredNoActive = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [realSession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: nil
        )

        XCTAssertTrue(restoredNoActive.entries.contains { $0.id == "session:real-session-id" })
        XCTAssertFalse(restoredNoActive.entries.contains { $0.id == "session:active-draft-id" }, "Inactive draft entry must be pruned")
        XCTAssertFalse(restoredNoActive.entries.contains { $0.id == "session:stale-orphan-id" }, "Orphan entry must be pruned")

        // Status for Saturday 2026-09-05 must be nil (not unfinished!)
        let statuses = WorkoutCalendar.statuses(history: restoredNoActive, today: "2026-09-05")
        XCTAssertNil(statuses["2026-09-05"], "Saturday must have nil status when not started, NOT unfinished")
    }

    func testWorkoutCalendarRestoreReconcilesScheduledWorkoutDate() {
        let mondaySession = WorkoutSessionRecord(
            id: "session-push-a",
            programId: "prog-1",
            workoutId: "w-mon",
            workoutTitle: "Chest & Triceps",
            startedAt: "2026-09-05T15:21:25.181Z",
            completedAt: "2026-09-05T16:03:24.092Z",
            durationSeconds: 2518,
            totalVolumeKg: 2000,
            totalCompletedSets: 7,
            exerciseLogs: [],
            isComplete: false
        )
        let prog = Program(
            id: "prog-1",
            name: "Aesthetic",
            workouts: [
                Workout(id: "w-mon", day: 1, title: "Chest & Triceps", exercises: [])
            ]
        )
        let rawHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-05",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: ["2026-08-31"],
            entries: [
                WorkoutDayEntry(id: "session:session-push-a", date: "2026-09-05", status: .unfinished)
            ]
        )

        let restored = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [mondaySession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: nil,
            programs: [prog]
        )

        let entry = restored.entries.first { $0.id == "session:session-push-a" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.date, "2026-08-31", "Session for Monday workout performed on Saturday must reconcile to Monday 2026-08-31")
        XCTAssertEqual(entry?.status, .unfinished)

        let statuses = WorkoutCalendar.statuses(history: restored, today: "2026-09-05")
        XCTAssertEqual(statuses["2026-08-31"], .unfinished, "August 31 must show unfinished, NOT missed")
    }

    func testProgramExerciseFixedSetsAndRepTargetModificationPersists() {
        let store = AppStore.shared
        guard var program = store.state.programs.first else {
            XCTFail("No programs found in store")
            return
        }
        guard !program.workouts.isEmpty && !program.workouts[0].exercises.isEmpty else {
            XCTFail("First workout has no exercises")
            return
        }

        // Modify exercise 0 to fixed 4 sets of 10-12 reps
        var modifiedEx = program.workouts[0].exercises[0]
        modifiedEx.sets = 4
        modifiedEx.reps = RepTarget(min: 10, max: 12, toFailure: false, perSide: false)
        modifiedEx.restSeconds = 120
        program.workouts[0].exercises[0] = modifiedEx

        // Update program via store
        store.updateProgram(program)

        // Verify in-memory state
        let updatedInStore = store.state.programs.first { $0.id == program.id }
        XCTAssertNotNil(updatedInStore)
        let exInStore = updatedInStore?.workouts.first?.exercises.first
        XCTAssertEqual(exInStore?.sets, 4, "Sets must be fixed integer 4")
        XCTAssertEqual(exInStore?.reps?.min, 10)
        XCTAssertEqual(exInStore?.reps?.max, 12)
        XCTAssertEqual(exInStore?.displayPrescription, "4 × 10–12")

        // Verify persistence in UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "stored_app_state"),
              let persistedState = try? JSONDecoder().decode(StoredAppState.self, from: data),
              let persistedProgram = persistedState.programs.first(where: { $0.id == program.id }),
              let persistedExercise = persistedProgram.workouts.first?.exercises.first else {
            XCTFail("Failed to read persisted program from UserDefaults")
            return
        }
        XCTAssertEqual(persistedExercise.sets, 4)
        XCTAssertEqual(persistedExercise.reps?.min, 10)
        XCTAssertEqual(persistedExercise.reps?.max, 12)
        XCTAssertEqual(persistedExercise.restSeconds, 120)
    }

    @MainActor
    func testProgramExerciseEditorSheetSnapshot() {
        let exercise = Exercise(
            name: "Incline Barbell Bench Press",
            prescription: "4 × 6–8",
            sets: 4,
            reps: RepTarget(min: 6, max: 8),
            restSeconds: 180,
            movementType: "bench"
        )
        let sheet = ProgramExerciseEditorSheet(
            exercise: exercise,
            onSave: { _ in },
            onDelete: {}
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_program_exercise_editor_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testAddedSetStartsEmptyWithoutCopyingPreviousInputs() {
        var sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "80", repsInput: "10", weightKg: 80, completedReps: 10, isCompleted: true)
        ]
        // Adding a set must produce a clean, blank set
        sets.append(ExerciseSetLog(
            setNumber: sets.count + 1,
            isCompleted: false
        ))
        let added = sets.last!
        XCTAssertEqual(added.setNumber, 2)
        XCTAssertEqual(added.weightInput, "")
        XCTAssertEqual(added.repsInput, "")
        XCTAssertNil(added.weightKg)
        XCTAssertNil(added.completedReps)
        XCTAssertFalse(added.isCompleted)
    }

    func testCanCompleteSetValidatesKgAndRepsAboveOrEqualToOne() {
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "", repsInput: "10")))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "0", repsInput: "10", weightKg: 0, completedReps: 10)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "0.9", repsInput: "10", weightKg: 0.9, completedReps: 10)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "", weightKg: 50)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "0", weightKg: 50, completedReps: 0)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "1", repsInput: "1", weightKg: 1, completedReps: 1)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "12", weightKg: 50, completedReps: 12)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "2.5", repsInput: "15")))
    }

    func testEmptySetWarningTranslationsParity() {
        XCTAssertEqual(Translations.en["notice.emptySetWarning"], "Weight and rep info cannot be left empty.")
        XCTAssertEqual(Translations.tr["notice.emptySetWarning"], "Tekrar ve ağırlık bilgisi boş bırakılamaz.")
    }

    func testRestActiveWarningTranslationsParity() {
        XCTAssertEqual(Translations.en["notice.restActiveWarning"], "Cannot log a set while the rest timer is running.")
        XCTAssertEqual(Translations.tr["notice.restActiveWarning"], "Dinlenme sayacı devredeyken set tamamlanamaz.")
    }

    func testIsSetEnabledRequiresPrecedingSetsToBeCompleted() {
        let sets = [
            ExerciseSetLog(setNumber: 1),
            ExerciseSetLog(setNumber: 2),
            ExerciseSetLog(setNumber: 3)
        ]
        // All incomplete: only set 1 enabled
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 0))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 1))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 2))

        // Set 1 completed: set 1 and 2 enabled, set 3 locked
        var set1Done = sets
        set1Done[0].isCompleted = true
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 0))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 1))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 2))

        // Set 1 and 2 completed: all enabled
        var set1And2Done = set1Done
        set1And2Done[1].isCompleted = true
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 0))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 1))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 2))
    }

    func testPrefillNextSetTranslationsParity() {
        XCTAssertEqual(Translations.en["settings.prefillNextSet"], "Pre-fill next set")
        XCTAssertEqual(Translations.tr["settings.prefillNextSet"], "Sonraki seti doldur")
        XCTAssertEqual(Translations.en["settings.prefillNextSetSubtitle"], "Copy weight and reps from previous set")
        XCTAssertEqual(Translations.tr["settings.prefillNextSetSubtitle"], "Önceki setin ağırlık ve tekrarını kopyala")
    }

    func testPrefillNextSetDefault() {
        let store = AppStore.shared
        XCTAssertTrue(store.prefillNextSet)
    }

    func testAboutTranslationsParity() {
        XCTAssertEqual(Translations.en["settings.version"], "v1.0")
        XCTAssertEqual(Translations.tr["settings.version"], "v1.0")
        XCTAssertFalse(Translations.en["settings.aboutDescription"]?.isEmpty ?? true)
        XCTAssertFalse(Translations.tr["settings.aboutDescription"]?.isEmpty ?? true)
    }

    func testMovementIconSupportsAnimatedParameter() {
        let staticIcon = MovementIcon(exerciseId: "barbell-bench-press", size: 72, animated: false)
        XCTAssertNotNil(staticIcon)
        let animatedIcon = MovementIcon(exerciseId: "barbell-bench-press", size: 72, animated: true)
        XCTAssertNotNil(animatedIcon)
    }

    @MainActor
    func testSettingsViewSnapshot() {
        let view = SettingsView(store: AppStore.shared, onDismiss: {})
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_settings_view_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    private func makePrSession(
        id: String,
        startedAt: String,
        completedAt: String = "",
        durationSeconds: Int = 1800,
        volumeKg: Double = 1000.0,
        exercises: [(String, [Double])]
    ) -> WorkoutSessionRecord {
        let comp = completedAt.isEmpty ? startedAt : completedAt
        let exerciseLogs = exercises.map { (name, weights) in
            SessionExerciseLog(
                exerciseName: name,
                sets: weights.enumerated().map { idx, w in
                    SessionSetLog(setNumber: idx + 1, weightKg: w, reps: 10)
                },
                targetSets: weights.count
            )
        }
        return WorkoutSessionRecord(
            id: id,
            programId: "prog-1",
            workoutId: "w-1",
            workoutTitle: "Test Workout",
            startedAt: startedAt,
            completedAt: comp,
            durationSeconds: durationSeconds,
            totalVolumeKg: volumeKg,
            totalCompletedSets: exercises.reduce(0) { $0 + $1.1.count },
            exerciseLogs: exerciseLogs,
            isComplete: true
        )
    }

    func testFirstRecordedWeightIsBaselineNotPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-14T10:00:00Z",
            exercises: [
                ("Bench Press", [60.0, 70.0, 80.0]),
                ("Barbell Squat", [100.0, 100.0])
            ]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 0, "First time weights are recorded must not count as PRs")
    }

    func testPassingPreviousWeightHitsPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [("Bench Press", [80.0, 80.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z", // Week 38
            exercises: [("Bench Press", [80.0, 85.0])]
        )

        let prCountWeek38 = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCountWeek38, 1, "Exceeding 80 kg with 85 kg must hit 1 PR in Week 38")
    }

    func testEqualOrLowerWeightDoesNotHitPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [("Bench Press", [80.0, 80.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z", // Week 38
            exercises: [("Bench Press", [70.0, 80.0])]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 0, "Matching or lower weight must not count as a PR")
    }

    func testMultipleExercisesInWeekTrackIndependentPRs() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [
                ("Bench Press", [80.0]),
                ("Barbell Squat", [100.0])
            ]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-15T10:00:00Z", // Week 38
            exercises: [
                ("Bench Press", [85.0]),    // PR #1 (passed 80)
                ("Barbell Squat", [105.0]),  // PR #2 (passed 100)
                ("Overhead Press", [50.0])   // Baseline (not PR)
            ]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 2)
    }

    func testBodyweightZeroKgDoesNotEstablishOrHitWeightPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z",
            exercises: [("Pull-Up", [0.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z",
            exercises: [("Pull-Up", [10.0])] // First weight recorded, baseline
        )
        let session3 = makePrSession(
            id: "s3",
            startedAt: "2026-09-16T10:00:00Z",
            exercises: [("Pull-Up", [15.0])] // Passed 10 -> PR!
        )

        let prCountWeek38 = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2, session3],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCountWeek38, 1, "10 kg was first recorded weight, 15 kg was the PR")
    }

    func testWeeklyGoalMetricsFormatting() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }

        LanguageManager.setLanguage("en")
        let metrics = WeeklyGoalProgressMetrics(
            completedWorkouts: 1,
            totalWorkouts: 5,
            totalVolumeKg: 14850.0,
            activeDurationSeconds: 5040, // 1h 24m
            prsHitCount: 2,
            hasUnfinishedProgress: false
        )

        XCTAssertEqual(metrics.formattedVolume, "14,850")
        XCTAssertEqual(metrics.formattedActiveTime, "1h 24m")
        XCTAssertEqual(metrics.progressFraction, 0.2, accuracy: 0.001)

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(metrics.formattedVolume, "14.850")
        XCTAssertEqual(metrics.formattedActiveTime, "1 sa 24 dk")
    }

    func testWeeklyGoalPillBlinking() {
        let totalWorkouts = 5
        let completedWorkouts = 2

        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 1, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 2, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 3, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 4, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))

        // Blinks even when no active workout is started/pending
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 2, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts, isCurrentWorkoutPending: false))

        // 1 completed out of 5 -> 2nd pill (index 1) blinks
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 1, totalWorkouts: totalWorkouts, completedWorkouts: 1))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: totalWorkouts, completedWorkouts: 1))

        for i in 0..<totalWorkouts {
            XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: i, totalWorkouts: totalWorkouts, completedWorkouts: 5))
        }

        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: 0, completedWorkouts: 0))
    }

    @MainActor
    func testWeeklyGoalProgressCardSnapshot() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")

        let metrics = WeeklyGoalProgressMetrics(
            completedWorkouts: 3,
            totalWorkouts: 4,
            totalVolumeKg: 14850.0,
            activeDurationSeconds: 5040,
            prsHitCount: 2,
            hasUnfinishedProgress: false
        )

        let view = VStack(spacing: 16) {
            WeeklyGoalProgressCard(metrics: metrics)
        }
        .padding(20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_weekly_goal_progress_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote WeeklyGoalProgressCard snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayViewSnapshot() {
        let store = AppStore.shared
        let view = TodayView(
            store: store,
            onOpenPrograms: {},
            onOpenSettings: {},
            onSelectExercise: { _ in }
        )
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_today_view_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote TodayView snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardLegsSnapshot() {
        let legsWorkout = Workout(
            id: "legs-test",
            day: 4,
            title: "Quads & Calves",
            focus: "Squat pattern and calf isolation",
            exercises: [
                Exercise(name: "Barbell Back Squat"),
                Exercise(name: "Leg Extension"),
                Exercise(name: "Standing Calf Raise")
            ],
            targetMuscles: ["quadriceps", "calves"]
        )

        let view = VStack {
            TodayHeroCard(
                workout: legsWorkout,
                programId: "test-prog",
                todayIndex: 3,
                isCompleted: false,
                isAvailable: true,
                availableDay: nil,
                hasUnfinishedProgress: false,
                onStart: {}
            )
        }
        .padding(.vertical, 20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_legs_hero_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote legs hero snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardTuesdaySnapshot() {
        let store = AppStore.shared
        store.selectedWorkoutId = "aesthetic-pull-a"
        let workout = store.activeProgram?.workouts.first { $0.id == "aesthetic-pull-a" }
            ?? Workout(
                id: "aesthetic-pull-a",
                day: 2,
                title: "Back & Biceps",
                focus: "Vertical pull, supported row and rear delts",
                exercises: [
                    Exercise(name: "Cable Lat Pulldown"),
                    Exercise(name: "Chest Supported Row"),
                    Exercise(name: "Incline Dumbbell Curl")
                ],
                targetMuscles: ["lats", "trapezius", "shoulders", "biceps"]
            )

        let view = VStack {
            TodayHeroCard(
                workout: workout,
                programId: store.activeProgram?.id ?? "01_aesthetic_hypertrophy",
                todayIndex: store.weekCalendar.today,
                isCompleted: false,
                isAvailable: true,
                availableDay: nil,
                hasUnfinishedProgress: false,
                onStart: {}
            )
        }
        .padding(.vertical, 20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_tuesday_hero_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Tuesday hero snapshot to \(path)")
        }
        store.selectedWorkoutId = nil
    }

    func testFindExercisePrReturnsBestSetOrNilWhenNoData() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", sets: 3)

        // Empty history
        XCTAssertNil(WorkoutSessionUtils.findExercisePr(history: [], exercise: exercise))

        // History with unrelated exercise
        let record1 = WorkoutSessionRecord(
            id: "rec-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Legs",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 500,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Squat",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5)]
                )
            ]
        )
        XCTAssertNil(WorkoutSessionUtils.findExercisePr(history: [record1], exercise: exercise))

        // History with matching exercise
        let record2 = WorkoutSessionRecord(
            id: "rec-2",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-12T10:00:00Z",
            completedAt: "2026-09-12T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 1000,
            totalCompletedSets: 3,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 60.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 65.0, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 65.0, reps: 10)
                    ]
                )
            ]
        )
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record1, record2], exercise: exercise), "65x10")

        // Newer record with fractional weight PR
        let record3 = WorkoutSessionRecord(
            id: "rec-3",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 1200,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 67.5, reps: 6)
                    ]
                )
            ]
        )
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record1, record2, record3], exercise: exercise), "67.5x6")
    }

    func testExerciseReportTranslationsParity() {
        let requiredKeys = [
            "report.action", "report.title", "report.category",
            "report.category.animation_form", "report.category.technique_cue",
            "report.category.what_to_avoid", "report.category.muscles_worked",
            "report.category.equipment_category", "report.category.other",
            "report.detailsLabel", "report.detailsPlaceholder",
            "report.submit", "report.submitted"
        ]

        for key in requiredKeys {
            XCTAssertFalse(Translations.en[key]?.isEmpty ?? true, "Missing English key: \(key)")
            XCTAssertFalse(Translations.tr[key]?.isEmpty ?? true, "Missing Turkish key: \(key)")
        }
    }

    func testExerciseReportStore() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("reports.json")
        let store = ExerciseReportStore(fileURL: fileURL)

        XCTAssertTrue(store.loadReports().isEmpty)

        let report1 = ExerciseIssueReport(
            id: "r1",
            exerciseId: "bench_press",
            exerciseName: "Bench Press",
            category: "animation_form",
            comment: "Elbow flares too much"
        )
        let updated1 = store.saveReport(report1)
        XCTAssertEqual(updated1.count, 1)
        XCTAssertEqual(updated1[0].id, "r1")

        let report2 = ExerciseIssueReport(
            id: "r2",
            exerciseId: "squat",
            exerciseName: "Barbell Squat",
            category: "what_to_avoid",
            comment: "Add knee cave note"
        )
        let updated2 = store.saveReport(report2)
        XCTAssertEqual(updated2.count, 2)

        let loaded = store.loadReports()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].exerciseName, "Bench Press")
        XCTAssertEqual(loaded[0].category, "animation_form")
        XCTAssertEqual(loaded[1].exerciseName, "Barbell Squat")
        XCTAssertEqual(loaded[1].category, "what_to_avoid")
    }

    @MainActor
    func testExerciseReportSheetSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            movementType: "press"
        )
        let sheet = ExerciseReportSheet(exercise: exercise, onDismiss: {}, onSubmit: { _ in })
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_report_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailViewSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees\nDo not bounce bar off chest",
            movementType: "press"
        )
        let view = ExerciseDetailView(exercise: exercise, onBack: {})
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_with_report_button_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testSetLoggingTableButtonHierarchySnapshot() {
        let sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "65", repsInput: "10", weightKg: 65.0, completedReps: 10, isCompleted: true),
            ExerciseSetLog(setNumber: 2, weightInput: "65", repsInput: "10", weightKg: 65.0, completedReps: nil, isCompleted: false),
            ExerciseSetLog(setNumber: 3, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        ]
        let table = SetLoggingTable(
            sets: sets,
            prescription: "3 × 8–10",
            prText: "65x10",
            onUpdateSet: { _, _, _ in },
            onToggleCompleteSet: { _ in },
            onAddSet: {},
            onRemoveSet: { _ in }
        )
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .padding(16)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: table)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 380)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 380))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_set_logging_table_buttons_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testZeroLoggedSetsDayStatusResolution() {
        let store = AppStore.shared
        let todayStr = "2026-09-17"
        let yesterdayStr = "2026-09-16"
        let todayDate = WorkoutCalendar.parseDate(todayStr)!

        // 1. Session today with 0 sets logged -> calendar status is nil (neutral tile)
        let todaySessionNoSets = WorkoutSessionRecord(
            id: "test-zero-sets-today",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-17T10:00:00.000Z",
            completedAt: "2026-09-17T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 0,
            exerciseLogs: [],
            isComplete: false
        )

        // Save a clean state
        store.activeSession = nil
        let previousHistory = store.state.history
        var st = store.state
        st.history = [todaySessionNoSets]
        st.history.append(todaySessionNoSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-today", date: todayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesToday = store.calendarStatuses(today: todayDate)
        XCTAssertNil(statusesToday[todayStr], "Today with zero sets logged must have no status (neutral tile)")

        // 1b. Active session today with 0 completed sets -> calendar status is nil (neutral tile)
        let dummyWorkout = Workout(id: "w1", day: 4, title: "Push", exercises: [Exercise(name: "Bench", sets: 3)])
        store.activeSession = ActiveSessionDraft(
            id: "draft-0-sets",
            programId: "prog",
            workout: dummyWorkout,
            startedAt: "2026-09-17T10:00:00.000Z",
            startedAtEpochMillis: 1000,
            currentExerciseIndex: 0,
            setsByExercise: [
                "Bench": [
                    ExerciseSetLog(setNumber: 1, isCompleted: false)
                ]
            ]
        )
        let statusesActive0Sets = store.calendarStatuses(today: todayDate)
        XCTAssertNil(statusesActive0Sets[todayStr], "Active session today with 0 completed sets must have no status (neutral tile)")
        store.activeSession = nil

        // 2. Session on a passed day with 0 sets logged -> calendar status is .missed (red)
        let pastSessionNoSets = WorkoutSessionRecord(
            id: "test-zero-sets-past",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-16T10:00:00.000Z",
            completedAt: "2026-09-16T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 0,
            exerciseLogs: [],
            isComplete: false
        )
        st.history.append(pastSessionNoSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-past", date: yesterdayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesPast = store.calendarStatuses(today: todayDate)
        XCTAssertEqual(statusesPast[yesterdayStr], .missed, "Passed day with zero sets logged must be marked .missed (red)")

        // 3. Session on a passed day WITH sets logged -> calendar status is .unfinished (orange)
        let pastSessionWithSets = WorkoutSessionRecord(
            id: "test-zero-sets-past-completed",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-16T10:00:00.000Z",
            completedAt: "2026-09-16T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 2,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80, reps: 8)],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        st.history.removeAll { $0.id == "test-zero-sets-past" }
        st.history.append(pastSessionWithSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-past-completed", date: yesterdayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesWithSets = store.calendarStatuses(today: todayDate)
        XCTAssertEqual(statusesWithSets[yesterdayStr], .unfinished, "Passed day with sets logged must remain .unfinished (orange)")

        // Clean up
        st.history = previousHistory
        st.calendarHistory = nil
        store.saveState(st)
    }
}

