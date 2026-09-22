import XCTest
import AVFoundation
import UIKit
import SwiftUI
@testable import FormApp

final class FormAppTests: XCTestCase {
    @MainActor
    func testRepMaxSourceSnapshots() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let store = AppStore()
        let oldState = store.state
        defer { store.state = oldState }
        store.state.history = [WorkoutSessionRecord(id: "estimate-ui", programId: "p", workoutId: "w", workoutTitle: "Workout",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 100,
            totalVolumeKg: 1220, totalCompletedSets: 2, exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: [
                SessionSetLog(setNumber: 1, weightKg: 100, reps: 5), SessionSetLog(setNumber: 2, weightKg: 20, reps: 36)
            ])])]
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for kind in ["matrix", "curve", "library"] {
                let content = Group {
                    if kind == "library" {
                        ExerciseHistoryStatsRow(stats: PersonalRecordTracker.computeExerciseHistoryStats(history: store.state.history, exerciseName: "Bench"), weightUnit: .kg)
                    } else {
                        FormLabView(store: store, initialTab: kind == "matrix" ? .repMax : .curves)
                    }
                }.padding(12).background(AppColors.background).environment(\.sizeCategory, .extraExtraLarge)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1300))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "rep-\(kind)-\(language)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    func testRepMaxEligibilityAndPreservedLogs() throws {
        for formula in RepMaxFormula.allCases {
            for reps in [-1, 0, 11, 20, 36, 37, Int.max] {
                XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: reps, formula: formula), 0)
                XCTAssertEqual(FormLabEngine.calculateTargetNRM(oneRmKg: 100, targetReps: reps, formula: formula), 0)
            }
            for weight in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
                XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: weight, reps: 5, formula: formula), 0)
                XCTAssertTrue(FormLabEngine.computeRepMaxTargets(oneRmKg: weight, formula: formula).isEmpty)
            }
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: 1, formula: formula), 20)
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: 10, formula: formula), 26.6667, accuracy: 0.001)
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: .greatestFiniteMagnitude, reps: 10, formula: formula), 0)
        }
        XCTAssertEqual(PersonalRecordTracker.calculateEstimated1RM(weightKg: 20, reps: 36), 0)
        let eligible = SessionSetLog(setNumber: 1, weightKg: 100, reps: 5)
        let highRep = SessionSetLog(setNumber: 2, weightKg: 20, reps: 36)
        let warmup = SessionSetLog(setNumber: 3, weightKg: 300, reps: 5, isWarmup: true)
        func session(_ id: String, _ date: String, _ sets: [SessionSetLog]) -> WorkoutSessionRecord {
            WorkoutSessionRecord(id: id, programId: "p", workoutId: "w", workoutTitle: "Workout", startedAt: date,
                completedAt: date, durationSeconds: 100, totalVolumeKg: 0, totalCompletedSets: sets.count,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: sets)])
        }
        let mixed = session("mixed", "2026-09-01T10:00:00Z", [eligible, highRep, warmup])
        let highOnly = session("high", "2026-09-02T10:00:00Z", [highRep])
        let history = [mixed, highOnly]
        for formula in RepMaxFormula.allCases {
            let expected = FormLabEngine.calculateEstimated1RM(weightKg: 100, reps: 5, formula: formula)
            let summary = try XCTUnwrap(FormLabEngine.computeExerciseRepMax(exerciseName: "Bench", history: history, formula: formula))
            XCTAssertEqual(summary.estimated1rmKg, expected, accuracy: 0.001)
            XCTAssertEqual(summary.achievedDate, mixed.startedAt)
            XCTAssertEqual(summary.bestWeightKg, 100)
            XCTAssertEqual(summary.bestReps, 5)
            XCTAssertEqual(summary.formula, formula)
            XCTAssertEqual(summary.targets.first?.estimatedWeightKg, expected)
            let curve = FormLabEngine.computeLongitudinalCurve(exerciseName: "Bench", history: history, formula: formula)
            XCTAssertEqual(curve.points.count, 1)
            XCTAssertEqual(curve.peak1rmKg, expected)
            XCTAssertEqual(curve.current1rmKg, expected)
            XCTAssertEqual(curve.start1rmKg, expected)
            XCTAssertEqual(curve.points.first?.topReps, 5)
            XCTAssertNil(FormLabEngine.computeExerciseRepMax(exerciseName: "Bench", history: [highOnly], formula: formula))
            XCTAssertTrue(FormLabEngine.computeAllRepMaxSummaries(history: [highOnly], formula: formula).isEmpty)
            let empty = FormLabEngine.computeLongitudinalCurve(exerciseName: "Bench", history: [highOnly], formula: formula)
            XCTAssertTrue(empty.points.isEmpty)
            XCTAssertNil(empty.peak1rmKg)
        }
        let stats = PersonalRecordTracker.computeExerciseHistoryStats(history: history, exerciseName: "Bench")
        XCTAssertEqual(stats.estimated1rmKg, 112.5)
        XCTAssertEqual(stats.estimateSourceSet, eligible)
        XCTAssertEqual(stats.estimateSourceDate, mixed.startedAt)
        XCTAssertEqual(stats.lifetimeSets, 4)
        XCTAssertEqual(stats.totalVolumeKg, 3440)
        XCTAssertEqual(stats.recentSessions.first?.sets, [highRep])
        let onlyStats = PersonalRecordTracker.computeExerciseHistoryStats(history: [highOnly], exerciseName: "Bench")
        XCTAssertNil(onlyStats.estimated1rmKg)
        XCTAssertNil(onlyStats.estimateSourceSet)
        XCTAssertEqual(onlyStats.prReps, 36)
        XCTAssertEqual(onlyStats.prWeightKg, 20)
        XCTAssertEqual(onlyStats.totalVolumeKg, 720)
        XCTAssertEqual(mixed.exerciseLogs.first?.sets, [eligible, highRep, warmup])
    }

    @MainActor
    func testAnalyticsReferenceCopySnapshots() {
        let previous = LanguageManager.shared.currentLanguage
        let store = AppStore.shared
        let original = store.state
        var fixture = original
        fixture.history = [WorkoutSessionRecord(id: "distribution-ui", programId: "p", workoutId: "w", workoutTitle: "Workout",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 100,
            totalVolumeKg: 1280, totalCompletedSets: 5, exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 40, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "My leg curl", sets: [SessionSetLog(setNumber: 1, weightKg: 10, reps: 8, isWarmup: false)])])]
        store.saveState(fixture)
        defer { LanguageManager.setLanguage(previous); store.saveState(original) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for matrix in [true, false] {
                let content = Group {
                    if matrix {
                        ScrollView { VolumeMatrixView(store: AppStore.shared).padding(16) }
                    } else {
                        FormLabView(store: AppStore.shared, initialTab: .balance)
                    }
                }.environment(\.sizeCategory, .extraExtraLarge)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1300))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(matrix ? "volume-reference" : "training-distribution")-\(language)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    func testAnalyticsCopyUsesReferenceRangesNotDiagnoses() {
        for (language, copy) in [("en", Translations.en), ("tr", Translations.tr)] {
            XCTAssertEqual(copy["form_lab.tab_balance"], language == "en" ? "Training Distribution" : "Antrenman Dağılımı")
            for zone in VolumeZone.allCases {
                XCTAssertTrue((copy[zone.titleKey] ?? "").lowercased().contains("refer"))
            }
            for key in ["matrix.limitations", "matrix.info.overviewText", "form_lab.balance_subtitle", "form_lab.info_antagonist_desc"] {
                XCTAssertTrue((copy[key] ?? "").contains(language == "en" ? "not" : "tanı"), key)
            }
            let analytics = copy.filter { $0.key.hasPrefix("matrix.") || $0.key.hasPrefix("form_lab.balance") || $0.key.hasPrefix("form_lab.info_antagonist") || $0.key.hasPrefix("paywall.volume_matrix") }.values.joined(separator: "\n").lowercased()
            for claim in ["high risk of overtraining", "protect shoulders", "prevent joint impingement", "balanced knee flexion and extension torque", "optimal balance", "maintenance only", "eliminate overtraining", "fatigue optimization", "aşırı antrenman riskini önlemek", "sürantrene olma riski yüksek", "yalnızca koruma sağlar", "maksimum toparlanabilir hacim aşıldı"] {
                XCTAssertFalse(analytics.contains(claim), claim)
            }
        }
    }

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
    func testLibraryModalsSnapshots() {
        let store = AppStore.shared
        let modals: [(LibraryFilterModal, String)] = [
            (.equipment, "ios_library_equipment_modal_snapshot.png"),
            (.muscle, "ios_library_muscle_modal_snapshot.png")
        ]

        for (modal, filename) in modals {
            let libraryView = LibraryView(store: store, onSelectExercise: { _ in }, onOpenSettings: {}, initialModal: modal)
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
                let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/\(filename)"
                try? data.write(to: URL(fileURLWithPath: path))
                print("Successfully wrote modal snapshot to \(path)")
            }
        }
    }

    @MainActor
    func testAllMuscleArtworkThumbnails() {
        let contactSheet = VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.fixed(160), spacing: 10), GridItem(.fixed(160), spacing: 10)], spacing: 10) {
                ForEach(MuscleGroupFilter.allCases) { muscle in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black)
                            if muscle == .cardio {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AppColors.accent.opacity(0.14))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundColor(AppColors.accent)
                                }
                            } else {
                                MuscleArtwork(view: muscle.bodyView, muscles: muscle.muscleGroups, centered: true)
                                    .padding(4)
                            }
                        }
                        .frame(width: 160, height: 84)

                        Text(LanguageManager.t(muscle.translationKey))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.text)
                    }
                }
            }
        }
        .padding(20)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: contactSheet)
        let targetSize = controller.sizeThatFits(in: CGSize(width: 400, height: 1400))
        controller.view.frame = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(origin: .zero, size: targetSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_all_muscle_groups_contact_sheet.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote contact sheet to \(path)")
        }
    }

    func testLibraryMuscleFilteringAndMatching() {
        let bench = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", movementType: "press")
        let squat = Exercise(name: "Barbell Squat", exerciseId: "barbell-back-squat", movementType: "squat")
        let curl = Exercise(name: "Barbell Curl", exerciseId: "barbell-curl", movementType: "curl")

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "chest"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "quads"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "quads"))
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "glutes"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "biceps"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: curl, muscleKey: "biceps"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: curl, muscleKey: "chest"))

        let jumpRope = Exercise(name: "Jump Rope", exerciseId: "jump-rope", movementType: "conditioning")
        let burpee = Exercise(name: "Burpee", exerciseId: "burpee", movementType: "conditioning")
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: jumpRope, muscleKey: "cardio"))
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: burpee, muscleKey: "cardio"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "cardio"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: nil))
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
    func testVolumeMatrixViewSnapshot() {
        let store = AppStore.shared
        let originalLang = LanguageManager.shared.currentLanguage
        LanguageManager.shared.currentLanguage = "tr"
        defer { LanguageManager.shared.currentLanguage = originalLang }

        let view = ScrollView(showsIndicators: false) {
            VolumeMatrixView(store: store)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
        .background(Color(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0))

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 1250)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1250))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_volume_matrix_screen_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testVolumeMatrixInfoSheetSnapshot() {
        let sheet = VolumeMatrixInfoSheet()
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_volume_matrix_info_sheet_snapshot.png"
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
        let tuesdayDate = WorkoutCalendar.scheduledDate(forWeekday: 2, relativeTo: Date())
        var st = store.state
        st.history.removeAll { $0.workoutId == tuesdayWorkout.id }
        st.completed.removeAll { $0.contains(tuesdayWorkout.id) }
        st.calendarHistory?.entries.removeAll { $0.date == tuesdayDate }
        store.saveState(st)

        // Start Tuesday workout
        _ = store.startActiveSession(programId: program.id, workout: tuesdayWorkout, allowPast: true)
        guard let draft = store.activeSession else {
            XCTFail("Active session failed to start")
            return
        }

        // Verify that draft is assigned to Tuesday in the current week
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
    func testExerciseMusclesCardExpandedByDefault() throws {
        LanguageManager.setLanguage("en")
        let renderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: "barbell-bench-press")
            .frame(width: 350))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 100)

        let collapsedRenderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: "barbell-bench-press", initiallyExpanded: false)
            .frame(width: 350))
        collapsedRenderer.scale = 2
        let collapsedImage = try XCTUnwrap(collapsedRenderer.uiImage)
        XCTAssertLessThan(collapsedImage.size.height, 90)
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

    func testResumeWorkoutPreservesProgramAcrossActiveProgramSwitch() {
        let store = AppStore.shared
        guard store.state.programs.count >= 2 else { return }
        let progA = store.state.programs[0]
        let progB = store.state.programs[1]
        guard let workoutA = progA.workouts.first(where: { $0.exercises.count >= 2 }) else { return }

        // Set active program to progA
        var st = store.state
        st.activeProgramId = progA.id
        st.history.removeAll { $0.workoutId == workoutA.id }
        st.completed.removeAll { $0.contains(workoutA.id) }
        store.saveState(st)

        // 1. Start workout in progA
        let started = store.startActiveSession(programId: progA.id, workout: workoutA)
        XCTAssertTrue(started)

        // 2. Complete first exercise
        let firstEx = workoutA.exercises[0]
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 50.0
                sets[i].weightInput = "50"
                sets[i].completedReps = 10
                sets[i].repsInput = "10"
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // 3. Abandon active session so it saves as an unfinished session in history
        store.abandonActiveSession()
        XCTAssertNil(store.activeSession)

        let unfinishedRec = store.state.history.first { $0.workoutId == workoutA.id && $0.isComplete == false }
        XCTAssertNotNil(unfinishedRec)
        XCTAssertEqual(unfinishedRec?.programId, progA.id)

        // 4. User changes active program to progB!
        var switchedState = store.state
        switchedState.activeProgramId = progB.id
        store.saveState(switchedState)
        XCTAssertEqual(store.activeProgram?.id, progB.id)

        // 5. Resume from History: simulate HistoryView handleWorkoutAction logic
        let resolvedProgId = unfinishedRec?.programId
            ?? store.state.programs.first(where: { $0.workouts.contains(where: { $0.id == workoutA.id }) })?.id
            ?? store.activeProgram?.id
        XCTAssertEqual(resolvedProgId, progA.id, "Resolved program ID must be progA, NOT activeProgram (progB)")

        let resumed = store.startActiveSession(
            programId: resolvedProgId ?? "",
            workout: workoutA,
            allowPast: true,
            unfinishedRecordId: unfinishedRec?.id
        )
        XCTAssertTrue(resumed)
        guard let resumedDraft = store.activeSession else {
            XCTFail("Failed to resume active session")
            return
        }
        XCTAssertEqual(resumedDraft.programId, progA.id, "Draft must preserve original program ID")

        // 6. Complete remaining exercises and finish workout
        for ex in workoutA.exercises {
            store.updateActiveSession { d in
                var copy = d
                var sets = copy.setsByExercise[ex.id] ?? []
                for i in 0..<sets.count {
                    sets[i].isCompleted = true
                    sets[i].weightKg = 60.0
                    sets[i].weightInput = "60"
                    sets[i].completedReps = 10
                    sets[i].repsInput = "10"
                }
                copy.setsByExercise[ex.id] = sets
                return copy
            }
        }

        let finalRecord = WorkoutSessionRecord(
            id: resumedDraft.id,
            programId: resumedDraft.programId,
            workoutId: resumedDraft.workout.id,
            workoutTitle: resumedDraft.workout.title,
            startedAt: resumedDraft.startedAt,
            completedAt: ISO8601DateFormatter().string(from: Date()),
            durationSeconds: 1800,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 6,
            exerciseLogs: [],
            isComplete: true
        )
        store.completeActiveSession(finalRecord)

        // 7. Verify completions
        let completedKeys = store.state.completed
        XCTAssertTrue(completedKeys.contains("\(progA.id):\(workoutA.id)"), "Completion key for progA must be added")
        XCTAssertFalse(completedKeys.contains("\(progB.id):\(workoutA.id)"), "Must NOT add completion key under progB")

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
        XCTAssertEqual(Translations.en["settings.terms"], "Terms of Service")
        XCTAssertEqual(Translations.tr["settings.terms"], "Kullanım Koşulları")
        XCTAssertEqual(Translations.en["settings.privacy"], "Privacy Policy")
        XCTAssertEqual(Translations.tr["settings.privacy"], "Gizlilik Politikası")
        XCTAssertEqual(Translations.en["settings.support"], "Customer Support")
        XCTAssertEqual(Translations.tr["settings.support"], "Müşteri Desteği")
        XCTAssertEqual(Translations.en["settings.manage_subscription"], "Manage Subscription")
        XCTAssertEqual(Translations.tr["settings.manage_subscription"], "Aboneliği Yönet")
        XCTAssertTrue(LegalUrls.termsOfService.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.privacyPolicy.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.support.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.manageSubscriptions.hasPrefix("https://apps.apple.com/account/subscriptions"))
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
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 1500))
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
    func testExerciseDetailTechniqueTabSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula and arch slightly\nLower bar with control to sternum\nDrive feet down to press up",
            avoid: "Do not flare elbows to 90 degrees\nDo not bounce bar off chest\nDo not lift hips off the bench",
            movementType: "press"
        )
        let view = ExerciseDetailView(exercise: exercise, initialTab: .technique, onBack: {})
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_technique_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailHistoryTabSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees",
            movementType: "press"
        )

        let mockHistory: [WorkoutSessionRecord] = [
            WorkoutSessionRecord(
                id: "mock_session_1",
                programId: "prog_1",
                workoutId: "w_1",
                workoutTitle: "Upper Body Strength",
                startedAt: "2026-09-15T10:00:00Z",
                completedAt: "2026-09-15T11:00:00Z",
                durationSeconds: 3600,
                totalVolumeKg: 4000,
                totalCompletedSets: 12,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7),
                            SessionSetLog(setNumber: 3, weightKg: 95.0, reps: 8)
                        ],
                        targetSets: 3
                    )
                ]
            ),
            WorkoutSessionRecord(
                id: "mock_session_2",
                programId: "prog_1",
                workoutId: "w_1",
                workoutTitle: "Chest & Arms Focus",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                totalVolumeKg: 3500,
                totalCompletedSets: 10,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 95.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 90.0, reps: 8)
                        ],
                        targetSets: 2
                    )
                ]
            )
        ]

        let originalHistory = AppStore.shared.state.history
        AppStore.shared.state.history = mockHistory
        defer { AppStore.shared.state.history = originalHistory }

        let view = ExerciseDetailView(exercise: exercise, initialTab: .history, onBack: {})
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_history_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailHistoryEmptyTabSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees",
            movementType: "press"
        )

        let originalHistory = AppStore.shared.state.history
        AppStore.shared.state.history = []
        defer { AppStore.shared.state.history = originalHistory }

        let view = ExerciseDetailView(exercise: exercise, initialTab: .history, onBack: {})
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_history_empty_snapshot.png"
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

    // MARK: - History Import Tests

    func testCsvParserRFC4180() {
        let csv = "col1,col2,\"col3, with comma\"\n" +
            "val1,\"val2 with \"\"quote\"\"\",val3\n" +
            "\"multi\nline\",val5,val6"

        let rows = CsvParser.parse(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["col1", "col2", "col3, with comma"])
        XCTAssertEqual(rows[1], ["val1", "val2 with \"quote\"", "val3"])
        XCTAssertEqual(rows[2][0], "multi\nline")
        XCTAssertEqual(rows[2][1], "val5")
        XCTAssertEqual(rows[2][2], "val6")
    }

    func testCsvParserDelimiterDetection() {
        let semicolonCsv = "Date;Workout Name;Exercise Name;Set Order\n2024-05-10;Chest;Bench;1"
        let rows = CsvParser.parse(semicolonCsv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["Date", "Workout Name", "Exercise Name", "Set Order"])
        XCTAssertEqual(rows[1], ["2024-05-10", "Chest", "Bench", "1"])
    }

    func testExerciseAliasDictionary() {
        let sampleCanonical = [
            "Barbell Bench Press",
            "Barbell Back Squat",
            "Deadlift",
            "Incline Barbell Bench Press",
            "Lat Pulldown",
            "Dumbbell Bicep Curl",
            "Dumbbell Lateral Raise",
            "Cable Triceps Pushdown",
            "Leg Press",
            "Pull-up",
            "Parallel Bar Dips"
        ]

        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Bench Press (Barbell)", canonicalNames: sampleCanonical), "Barbell Bench Press")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Squat (Barbell)", canonicalNames: sampleCanonical), "Barbell Back Squat")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Deadlift (Barbell)", canonicalNames: sampleCanonical), "Deadlift")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Lat Pulldown (Cable)", canonicalNames: sampleCanonical), "Lat Pulldown")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Dumbbell Curl", canonicalNames: sampleCanonical), "Dumbbell Bicep Curl")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Dips", canonicalNames: sampleCanonical), "Parallel Bar Dips")
        XCTAssertEqual(ExerciseAliasDictionary.resolve(rawName: "Custom Rare Exercise", canonicalNames: sampleCanonical), "Custom Rare Exercise")
    }

    func testStrongCsvParsing() throws {
        let sampleCanonical = [
            "Barbell Bench Press",
            "Barbell Back Squat",
            "Deadlift",
            "Dumbbell Lateral Raise"
        ]
        let strongCsv = [
            "Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration",
            "2024-06-15 10:00:00;Push Day;Bench Press (Barbell);1;80;kg;8;;;;;;;4500",
            "2024-06-15 10:00:00;Push Day;Bench Press (Barbell);2;80;kg;8;;;;;;;4500",
            "2024-06-15 10:00:00;Push Day;Lateral Raise (Dumbbell);1;26.4;lbs;12;;;;;;;4500"
        ].joined(separator: "\n")

        let preview = try WorkoutHistoryImporter.preview(
            csvText: strongCsv,
            existingHistory: [],
            canonicalNames: sampleCanonical
        )

        XCTAssertEqual(preview.source, .strong)
        XCTAssertEqual(preview.totalWorkouts, 1)
        XCTAssertEqual(preview.newWorkoutsCount, 1)
        XCTAssertEqual(preview.duplicateWorkoutsCount, 0)
        XCTAssertEqual(preview.totalSetsCount, 3)
        XCTAssertEqual(preview.earliestDate, "2024-06-15")

        let workout = try XCTUnwrap(preview.workoutsToImport.first)
        XCTAssertEqual(workout.workoutTitle, "Push Day")
        XCTAssertEqual(workout.durationSeconds, 4500)
        XCTAssertEqual(workout.exerciseLogs.count, 2)

        let bench = workout.exerciseLogs[0]
        XCTAssertEqual(bench.exerciseName, "Barbell Bench Press")
        XCTAssertEqual(bench.sets.count, 2)
        XCTAssertEqual(try XCTUnwrap(bench.sets[0].weightKg), 80.0, accuracy: 0.01)
        XCTAssertEqual(bench.sets[0].reps, 8)

        let latRaise = workout.exerciseLogs[1]
        XCTAssertEqual(latRaise.exerciseName, "Dumbbell Lateral Raise")
        XCTAssertEqual(latRaise.sets.count, 1)
        // 26.4 lbs * 0.45359237 ≈ 11.97 kg
        XCTAssertEqual(try XCTUnwrap(latRaise.sets[0].weightKg), 11.97, accuracy: 0.05)
        XCTAssertEqual(latRaise.sets[0].reps, 12)
    }

    func testHevyCsvParsing() throws {
        let sampleCanonical = [
            "Barbell Back Squat",
            "Leg Press"
        ]
        let hevyCsv = [
            "\"title\",\"start_time\",\"end_time\",\"description\",\"exercise_title\",\"superset_id\",\"exercise_notes\",\"set_index\",\"set_type\",\"weight_lbs\",\"reps\",\"distance_miles\",\"duration_seconds\",\"rpe\"",
            "\"Leg Day\",\"15 Jul 2024, 09:30\",\"15 Jul 2024, 10:30\",\"\",\"Squat (Barbell)\",,\"\",0,\"normal\",220,5,,3600,",
            "\"Leg Day\",\"15 Jul 2024, 09:30\",\"15 Jul 2024, 10:30\",\"\",\"Squat (Barbell)\",,\"\",1,\"normal\",220,5,,3600,",
            "\"Leg Day\",\"15 Jul 2024, 09:30\",\"15 Jul 2024, 10:30\",\"\",\"Leg Press\",,\"\",0,\"normal\",400,10,,3600,"
        ].joined(separator: "\n")

        let preview = try WorkoutHistoryImporter.preview(
            csvText: hevyCsv,
            existingHistory: [],
            canonicalNames: sampleCanonical
        )

        XCTAssertEqual(preview.source, .hevy)
        XCTAssertEqual(preview.totalWorkouts, 1)
        XCTAssertEqual(preview.newWorkoutsCount, 1)
        XCTAssertEqual(preview.totalSetsCount, 3)
        XCTAssertEqual(preview.earliestDate, "2024-07-15")

        let workout = try XCTUnwrap(preview.workoutsToImport.first)
        XCTAssertEqual(workout.workoutTitle, "Leg Day")
        XCTAssertEqual(workout.exerciseLogs.count, 2)

        let squat = workout.exerciseLogs[0]
        XCTAssertEqual(squat.exerciseName, "Barbell Back Squat")
        // 220 lbs * 0.45359237 ≈ 99.79 kg (~100 kg)
        XCTAssertEqual(try XCTUnwrap(squat.sets[0].weightKg), 99.79, accuracy: 0.1)
        XCTAssertEqual(squat.sets[0].reps, 5)
    }

    func testDeduplicationAgainstExistingHistory() throws {
        let sampleCanonical = [
            "Barbell Bench Press",
            "Pull-up"
        ]
        let strongCsv = [
            "Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration",
            "2024-06-15 10:00:00;Push Day;Bench Press (Barbell);1;80;kg;8;;;;;;;2700",
            "2024-06-16 10:00:00;Pull Day;Pull Up;1;0;kg;10;;;;;;;2700"
        ].joined(separator: "\n")

        let existingSession = WorkoutSessionRecord(
            id: "existing-1",
            programId: "imported",
            workoutId: "imported_push_day",
            workoutTitle: "Push Day",
            startedAt: "2024-06-15T10:00:00Z",
            completedAt: "2024-06-15T11:15:00Z",
            durationSeconds: 4500,
            totalVolumeKg: 640.0,
            totalCompletedSets: 1,
            isComplete: true
        )

        let preview = try WorkoutHistoryImporter.preview(
            csvText: strongCsv,
            existingHistory: [existingSession],
            canonicalNames: sampleCanonical
        )

        XCTAssertEqual(preview.totalWorkouts, 2)
        XCTAssertEqual(preview.newWorkoutsCount, 1) // Pull Day is new
        XCTAssertEqual(preview.duplicateWorkoutsCount, 1) // Push Day is skipped
        XCTAssertEqual(preview.workoutsToImport.first?.workoutTitle, "Pull Day")
    }

    func testWeightUnitDefaultForLocale() {
        let usLocale = Locale(identifier: "en_US")
        let gbLocale = Locale(identifier: "en_GB")
        let trLocale = Locale(identifier: "tr_TR")
        let deLocale = Locale(identifier: "de_DE")

        XCTAssertEqual(WeightUnit.defaultForLocale(usLocale), .lbs)
        XCTAssertEqual(WeightUnit.defaultForLocale(gbLocale), .kg)
        XCTAssertEqual(WeightUnit.defaultForLocale(trLocale), .kg)
        XCTAssertEqual(WeightUnit.defaultForLocale(deLocale), .kg)
    }

    func testOnboardingRecommender() {
        let dummyPrograms: [Program] = [
            Program(id: "home-forge-dumbbells", name: "Home Forge"),
            Program(id: "machine-foundation", name: "Machine Foundation"),
            Program(id: "classic-ppl", name: "Classic PPL"),
            Program(id: "aesthetic-hypertrophy", name: "Aesthetic Hypertrophy"),
            Program(id: "powerbuilding-strength", name: "Powerbuilding Strength"),
            Program(id: "upper-lower-balanced", name: "Upper Lower"),
            Program(id: "athletic-performance", name: "Athletic Performance"),
            Program(id: "full-body-classic", name: "Full Body Classic")
        ]

        // 1. Home / Dumbbells
        let homePrefs = OnboardingPreferences(equipment: .dumbbellsHome)
        let homeRec = OnboardingRecommender.recommendProgram(preferences: homePrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(homeRec.targetProgramId, "home-forge-dumbbells")

        // 2. Machines only
        let machinePrefs = OnboardingPreferences(equipment: .machinesOnly)
        let machineRec = OnboardingRecommender.recommendProgram(preferences: machinePrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(machineRec.targetProgramId, "machine-foundation")

        // 3. Commercial gym + 6 days
        let pplPrefs = OnboardingPreferences(equipment: .commercialGym, frequency: .days6)
        let pplRec = OnboardingRecommender.recommendProgram(preferences: pplPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(pplRec.targetProgramId, "classic-ppl")

        // 4. Commercial gym + 5 days
        let fiveDaysPrefs = OnboardingPreferences(equipment: .commercialGym, frequency: .days5)
        let fiveDaysRec = OnboardingRecommender.recommendProgram(preferences: fiveDaysPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(fiveDaysRec.targetProgramId, "aesthetic-hypertrophy")

        // 5. Commercial gym + 4 days + strength
        let pbPrefs = OnboardingPreferences(goal: .strength, equipment: .commercialGym, frequency: .days4)
        let pbRec = OnboardingRecommender.recommendProgram(preferences: pbPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(pbRec.targetProgramId, "powerbuilding-strength")

        // 6. Commercial gym + 4 days + bulk
        let ulPrefs = OnboardingPreferences(goal: .bulk, equipment: .commercialGym, frequency: .days4)
        let ulRec = OnboardingRecommender.recommendProgram(preferences: ulPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(ulRec.targetProgramId, "upper-lower-balanced")

        // 7. Commercial gym + 3 days + cut
        let athleticPrefs = OnboardingPreferences(goal: .cut, equipment: .commercialGym, frequency: .days3)
        let athleticRec = OnboardingRecommender.recommendProgram(preferences: athleticPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(athleticRec.targetProgramId, "athletic-performance")

        // 8. Commercial gym + 3 days + maintain
        let fbPrefs = OnboardingPreferences(goal: .maintain, equipment: .commercialGym, frequency: .days3)
        let fbRec = OnboardingRecommender.recommendProgram(preferences: fbPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(fbRec.targetProgramId, "full-body-classic")
    }

    func testOnboardingScheduledWeekdays() {
        let dummyPrograms = [Program(id: "upper-lower-balanced", name: "Upper Lower")]

        // Default weekdays when none explicitly selected
        let defaultPrefs = OnboardingPreferences(frequency: .days4, selectedDays: [])
        let defaultRec = OnboardingRecommender.recommendProgram(preferences: defaultPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(defaultRec.scheduledWeekdays, [1, 2, 4, 5])

        // Custom selected weekdays
        let customPrefs = OnboardingPreferences(frequency: .days4, selectedDays: [2, 4, 6, 7])
        let customRec = OnboardingRecommender.recommendProgram(preferences: customPrefs, availablePrograms: dummyPrograms)
        XCTAssertEqual(customRec.scheduledWeekdays, [2, 4, 6, 7])
    }

    func testProAccessManagerEntitlements() {
        let manager = ProAccessManager.shared
        defer { manager.resetOverrides() }

        // Default: locked for free tier
        manager.resetOverrides()
        XCTAssertFalse(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertFalse(manager.isFeatureUnlocked(.autoProgression))
        XCTAssertFalse(manager.isFeatureUnlocked(.formLab))

        // Subscription unlocks all
        manager.updateSubscriptionStatus(active: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertTrue(manager.isFeatureUnlocked(.autoProgression))
        XCTAssertTrue(manager.isFeatureUnlocked(.formLab))

        // Force locked via override
        manager.setFeatureOverride(.volumeMatrix, unlocked: false)
        XCTAssertFalse(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertTrue(manager.isFeatureUnlocked(.autoProgression))

        // Force unlocked via override even when unsubscribed
        manager.updateSubscriptionStatus(active: false)
        manager.setFeatureOverride(.volumeMatrix, unlocked: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertFalse(manager.isFeatureUnlocked(.autoProgression))
    }

    func testProPreviewDataDemonstrationHistory() {
        // Zero-history accounts identified correctly
        XCTAssertFalse(ProPreviewData.hasWorkingHistory([]))

        let warmupOnly = [
            WorkoutSessionRecord(
                programId: "p",
                workoutId: "w",
                workoutTitle: "Warmup",
                startedAt: "2026-09-20T10:00:00Z",
                completedAt: "2026-09-20T10:30:00Z",
                durationSeconds: 1800,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [SessionSetLog(setNumber: 1, weightKg: 40.0, reps: 10, isWarmup: true)]
                    )
                ]
            )
        ]
        XCTAssertFalse(ProPreviewData.hasWorkingHistory(warmupOnly))

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let testDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)) ?? Date()
        let preview = ProPreviewData.previewHistory(today: testDate)
        XCTAssertTrue(ProPreviewData.hasWorkingHistory(preview))

        // Volume Matrix computation
        guard let catalog = ExerciseMuscleCatalog.shared else {
            XCTFail("ExerciseMuscleCatalog must load")
            return
        }
        let report = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W38",
            history: preview,
            catalog: catalog,
            language: "en"
        )
        XCTAssertGreaterThan(report.totalEffectiveSets, 20)
        XCTAssertGreaterThanOrEqual(report.muscleSummaries["chest"]?.directSets ?? 0, 6)
        XCTAssertGreaterThanOrEqual(report.muscleSummaries["quads"]?.directSets ?? 0, 6)
        XCTAssertGreaterThanOrEqual(report.muscleSummaries["lats"]?.directSets ?? 0, 6)

        // Form Lab balance and progression computation
        let balance = FormLabEngine.computeAntagonistBalance(
            history: preview,
            today: testDate
        )
        XCTAssertNotNil(balance.pushPull.ratio)
        XCTAssertTrue(balance.pushPull.status != AntagonistStatus.insufficientData)
        XCTAssertNotNil(balance.quadHamstring.ratio)
        XCTAssertTrue(balance.quadHamstring.status != AntagonistStatus.insufficientData)
        XCTAssertNotNil(balance.upperLower.ratio)
        XCTAssertTrue(balance.upperLower.status != AntagonistStatus.insufficientData)

        let benchRepMax = FormLabEngine.computeExerciseRepMax(
            exerciseName: "Barbell Bench Press",
            history: preview
        )
        XCTAssertNotNil(benchRepMax)
        XCTAssertGreaterThan(benchRepMax?.estimated1rmKg ?? 0.0, 100.0)

        let benchCurve = FormLabEngine.computeLongitudinalCurve(
            exerciseName: "Barbell Bench Press",
            history: preview,
            today: testDate
        )
        XCTAssertGreaterThanOrEqual(benchCurve.points.count, 4)
        XCTAssertGreaterThan(benchCurve.deltaKg, 0.0)
        XCTAssertGreaterThan(benchCurve.percentageGain, 0.0)
    }

    func testVolumeMatrixEngineComputation() {
        guard let catalog = ExerciseMuscleCatalog.shared else {
            XCTFail("ExerciseMuscleCatalog must load")
            return
        }

        XCTAssertEqual(VolumeMatrixEngine.canonicalMuscles.count, 14)
        for muscle in VolumeMatrixEngine.canonicalMuscles {
            XCTAssertNotNil(catalog.muscles[muscle], "Muscle \(muscle) must exist in catalog")
        }

        let benchId = VolumeMatrixEngine.resolveExerciseId(exerciseName: "Barbell Bench Press")
        XCTAssertEqual(benchId, "barbell-bench-press")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Deadlift"), "conventional-barbell-deadlift")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Smith Machine Squat"), "smith-squat")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Dumbbell 45° Back Extension"), "dumbbell-45-deg-back-extension")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Dual Cable Lat Pulldown"), "cable-neutral-grip-lat-pulldown")

        let session = WorkoutSessionRecord(
            id: "test-sess-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Push Day",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 320,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 4, weightKg: 80, reps: 8)
                    ]
                )
            ]
        )

        let report = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W38",
            history: [session],
            catalog: catalog
        )

        // Chest: 4 direct, 0 indirect -> 4.0 effective
        let chest = report.muscleSummaries["chest"]
        XCTAssertNotNil(chest)
        XCTAssertEqual(chest?.directSets, 4)
        XCTAssertEqual(chest?.indirectSets, 0)
        XCTAssertEqual(chest?.totalEffectiveSets, 4.0)
        XCTAssertEqual(chest?.zone, VolumeZone.underMev)

        // Front delts: 0 direct, 4 indirect -> 2.0 effective
        let frontDelts = report.muscleSummaries["front-delts"]
        XCTAssertNotNil(frontDelts)
        XCTAssertEqual(frontDelts?.directSets, 0)
        XCTAssertEqual(frontDelts?.indirectSets, 4)
        XCTAssertEqual(frontDelts?.totalEffectiveSets, 2.0)
        XCTAssertEqual(report.totalWorkingSets, 4)
        XCTAssertEqual(report.totalEffectiveSets, 8.0)
        XCTAssertTrue(report.unmappedExercises.isEmpty)

        let coverageSession = WorkoutSessionRecord(
            id: "coverage", programId: "p", workoutId: "w", workoutTitle: "Shoulders",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600, exerciseLogs: [
                SessionExerciseLog(exerciseName: "Dumbbell Lateral Raise", sets: (1...2).map { SessionSetLog(setNumber: $0, weightKg: 10, reps: 12) }),
                SessionExerciseLog(exerciseName: "My Custom Movement", sets: (1...2).map { SessionSetLog(setNumber: $0, weightKg: 10, reps: 10) })
            ])
        let coverage = VolumeMatrixEngine.computeLoggedVolume(targetWeekKey: "2026-W38", history: [coverageSession], catalog: catalog)
        XCTAssertEqual(coverage.totalWorkingSets, 4)
        XCTAssertEqual(coverage.unmappedExercises["My Custom Movement"], 2)
        XCTAssertEqual(coverage.muscleSummaries["side-delts"]?.totalEffectiveSets, 2)
        XCTAssertEqual(catalog.profile("dumbbell-lateral-raise")?.primary, ["side-delts"])
        XCTAssertEqual(catalog.profile("head-supported-dumbbell-rear-lateral-raise")?.primary, ["rear-delts"])
        XCTAssertNil(VolumeMatrixEngine.resolveExerciseId(exerciseName: "My Custom Movement"))

        let program = Program(
            id: "cycle",
            name: "Test cycle",
            workouts: [
                Workout(
                    id: "upper",
                    day: 1,
                    title: "Upper",
                    exercises: [
                        Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 4),
                        Exercise(name: "Lat Pulldown", exerciseId: "lat-pulldown", sets: 4)
                    ]
                ),
                Workout(
                    id: "lower",
                    day: 2,
                    title: "Lower",
                    exercises: [
                        Exercise(name: "Barbell Back Squat", exerciseId: "barbell-back-squat", sets: 4)
                    ]
                )
            ]
        )
        let cycle = VolumeMatrixEngine.computePlannedRoutineVolume(program: program, catalog: catalog)
        XCTAssertTrue(cycle.isPlannedRoutine)
        XCTAssertEqual(cycle.weekKey, "program-cycle")
        XCTAssertEqual(cycle.totalWorkingSets, 12)
        XCTAssertTrue(cycle.muscleSummaries.values.allSatisfy { $0.zone == .noWeeklyReference })
        XCTAssertEqual(cycle.optimalMuscleCount, 0)
        XCTAssertEqual(cycle.underTrainedCount, 0)
        XCTAssertEqual(cycle.highFatigueCount, 0)

        let resumedId = "resumed-session"
        let staleRecord = WorkoutSessionRecord(
            id: resumedId,
            programId: "program",
            workoutId: "workout",
            workoutTitle: "Old saved state",
            startedAt: "2026-09-15T09:00:00Z",
            completedAt: "2026-09-15T10:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 8) },
                    exerciseId: "barbell-bench-press"
                )
            ],
            isComplete: false
        )
        let activeExercise = Exercise(
            id: "deadlift-instance",
            name: "Localized deadlift label",
            exerciseId: "conventional-barbell-deadlift",
            sets: 2
        )
        let start = Int64((ISO8601DateFormatter().date(from: "2026-09-15T09:00:00Z")?.timeIntervalSince1970 ?? 0) * 1000)
        let now = Int64((ISO8601DateFormatter().date(from: "2026-09-15T11:00:00Z")?.timeIntervalSince1970 ?? 0) * 1000)
        let active = ActiveSessionDraft(
            id: resumedId,
            programId: "program",
            workout: Workout(id: "workout", day: 2, title: "Resumed", exercises: [activeExercise]),
            startedAt: "2026-09-15T09:00:00Z",
            startedAtEpochMillis: start,
            setsByExercise: [
                activeExercise.id: (1...2).map {
                    ExerciseSetLog(setNumber: $0, weightKg: 100, completedReps: 5, isCompleted: true)
                }
            ]
        )
        let activeReport = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W38",
            history: [staleRecord],
            activeSession: active,
            catalog: catalog,
            nowEpochMillis: now
        )
        XCTAssertEqual(activeReport.totalWorkingSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["glutes"]?.totalEffectiveSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["hamstrings"]?.totalEffectiveSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["chest"]?.totalEffectiveSets, 0)
        XCTAssertTrue(activeReport.unmappedExercises.isEmpty)
        XCTAssertEqual(
            SessionProgress.from(draft: active, nowEpochMillis: now).exerciseLogs.first?.exerciseId,
            "conventional-barbell-deadlift"
        )
    }

    func testProgressionEngineReturnsFirstSessionWhenHistoryIsEmpty() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: [])
        XCTAssertEqual(rec.action, .firstSession)
        XCTAssertNil(rec.suggestedWeightKg)
        XCTAssertEqual(rec.suggestedRepsMin, 8)
        XCTAssertEqual(rec.suggestedRepsMax, 12)
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionEngineRecommendsIncreaseLoadWhenAllSetsHitRepCeiling() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)
        XCTAssertEqual(rec.action, .increaseLoad)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 82.5, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 8)
        XCTAssertFalse(rec.isPlateau)
        XCTAssertTrue(rec.weightDeltaDisplay?.contains("+2.5") == true)
    }

    func testProgressionEngineRecommendsAddRepsWhenWithinBracket() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 11),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 10),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 9)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)
        XCTAssertEqual(rec.action, .addReps)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 80.0, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 12)
        XCTAssertEqual(rec.suggestedRepsMax, 12)
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionEngineRecommendsHoldLoadWhenSetsMissFloor() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 7),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 6)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)
        XCTAssertEqual(rec.action, .holdLoad)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 80.0, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 8)
        XCTAssertEqual(rec.suggestedRepsMax, 12)
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionEngineDetectsPlateauAfterThreeStagnantSessions() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = (1...3).map { i in
            WorkoutSessionRecord(
                id: "s\(i)",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-0\(i)T10:00:00Z",
                completedAt: "2026-09-0\(i)T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 10),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 9),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 8)
                        ]
                    )
                ]
            )
        }

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)
        XCTAssertTrue(rec.isPlateau)
        XCTAssertEqual(rec.action, .deload)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 72.0, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedVariationId, "incline-dumbbell-press")
        XCTAssertEqual(rec.suggestedVariationName, "Incline Dumbbell Press")
    }

    func testProgressionEngineParsesRepRangesFromPrescription() {
        let exRange = Exercise(name: "Squat", prescription: "3 × 6–10")
        let (min1, max1) = ProgressionEngine.parseRepRange(exercise: exRange)
        XCTAssertEqual(min1, 6)
        XCTAssertEqual(max1, 10)

        let exFixed = Exercise(name: "Deadlift", prescription: "5 reps")
        let (min2, max2) = ProgressionEngine.parseRepRange(exercise: exFixed)
        XCTAssertEqual(min2, 5)
        XCTAssertEqual(max2, 5)
    }

    @MainActor
    func testProgressionCoachCardSnapshot() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)
        let card = ProgressionCoachCard(
            recommendation: rec,
            onApplyTarget: {},
            onOpenInfo: {}
        )
        .padding(20)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 180)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 180))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_progression_coach_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testProgressionInfoSheetSnapshot() {
        let sheet = ProgressionInfoSheet()
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_progression_info_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testActiveSessionWithProgressionCoachSnapshot() {
        let store = AppStore.shared
        let originalHistory = store.state.history
        let originalSession = store.activeSession

        // Inject history for Barbell Bench Press where lifter hit rep ceiling (80kg x 12, 12, 12)
        let sampleHistory = WorkoutSessionRecord(
            id: "hist-bench",
            programId: "hypertrophy-split",
            workoutId: "push-1",
            workoutTitle: "Monday: Chest & Triceps",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                    ]
                )
            ]
        )
        store.state.history = [sampleHistory] + originalHistory

        let benchExercise = Exercise(
            id: "bench-active",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            prescription: "3 × 8–12",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let inclineExercise = Exercise(
            id: "incline-active",
            name: "Incline Dumbbell Press",
            exerciseId: "incline-dumbbell-press",
            prescription: "3 × 10–12",
            sets: 3,
            reps: RepTarget(min: 10, max: 12)
        )
        let activeWorkout = Workout(
            id: "workout-chest",
            day: 1,
            title: "Chest & Triceps",
            exercises: [benchExercise, inclineExercise]
        )

        let initialSets = (1...3).map { ExerciseSetLog(setNumber: $0) }
        let draft = ActiveSessionDraft(
            id: "active-prog-session",
            programId: "hypertrophy-split",
            workout: activeWorkout,
            startedAt: "2026-09-19T13:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000),
            currentExerciseIndex: 0,
            setsByExercise: [
                benchExercise.id: initialSets,
                inclineExercise.id: (1...3).map { ExerciseSetLog(setNumber: $0) }
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_active_session_with_progression.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        // Restore state
        store.state.history = originalHistory
        store.activeSession = originalSession
    }

    @MainActor
    func testRootViewBottomDockSnapshot() {
        let store = AppStore.shared
        store.isOnboardingCompleted = true
        store.navigate(to: .today)

        let rootView = RootView()
        let controller = UIHostingController(rootView: rootView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_root_view_dock_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote RootView bottom dock snapshot to \(path)")
        }
    }

    func testWarmupRampFor100kgWorkingWeight() {
        let ramp = WarmupPlateEngine.generateWarmupRamp(
            workingWeightKg: 100.0,
            barWeightKg: 20.0,
            unit: .kg
        )

        XCTAssertEqual(ramp.workingWeightKg, 100.0, accuracy: 0.001)
        XCTAssertEqual(ramp.barWeightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(ramp.steps.count, 4)

        // Set 1: Empty Bar (20 kg) x 10 (warm joints)
        let s1 = ramp.steps[0]
        XCTAssertEqual(s1.setNumber, 1)
        XCTAssertEqual(s1.weightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(s1.reps, 10)
        XCTAssertEqual(s1.labelKey, "warmup.warm_joints")
        XCTAssertFalse(s1.isPotentiation)

        // Set 2: 50 kg x 5 (50% working weight)
        let s2 = ramp.steps[1]
        XCTAssertEqual(s2.setNumber, 2)
        XCTAssertEqual(s2.weightKg, 50.0, accuracy: 0.001)
        XCTAssertEqual(s2.reps, 5)
        XCTAssertEqual(s2.labelKey, "warmup.50_percent")
        XCTAssertFalse(s2.isPotentiation)

        // Set 3: 70 kg x 3 (70% working weight)
        let s3 = ramp.steps[2]
        XCTAssertEqual(s3.setNumber, 3)
        XCTAssertEqual(s3.weightKg, 70.0, accuracy: 0.001)
        XCTAssertEqual(s3.reps, 3)
        XCTAssertEqual(s3.labelKey, "warmup.70_percent")
        XCTAssertFalse(s3.isPotentiation)

        // Set 4: 85 kg x 1 (85% potentiation single)
        let s4 = ramp.steps[3]
        XCTAssertEqual(s4.setNumber, 4)
        XCTAssertEqual(s4.weightKg, 85.0, accuracy: 0.001)
        XCTAssertEqual(s4.reps, 1)
        XCTAssertEqual(s4.labelKey, "warmup.85_percent")
        XCTAssertTrue(s4.isPotentiation)
    }

    func testWarmupRampForLightWeights() {
        // Working weight equal to bar: only empty bar
        let ramp20 = WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 20.0, barWeightKg: 20.0)
        XCTAssertEqual(ramp20.steps.count, 1)
        XCTAssertEqual(ramp20.steps[0].weightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(ramp20.steps[0].reps, 10)

        // Working weight 40 kg: strictly increasing, strictly < 40 kg
        let ramp40 = WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 40.0, barWeightKg: 20.0)
        XCTAssertFalse(ramp40.steps.isEmpty)
        XCTAssertTrue(ramp40.steps.allSatisfy { $0.weightKg < 40.0 })
        for i in 1..<ramp40.steps.count {
            XCTAssertTrue(ramp40.steps[i].weightKg > ramp40.steps[i - 1].weightKg)
        }
    }

    func testCalculatePlates95kgPromptExample() {
        // (95 - 20) / 2 = 37.5 kg per side = 1x20kg + 1x15kg + 1x2.5kg
        let platesWithout25: [Double] = [20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
        let result = WarmupPlateEngine.calculatePlates(
            targetWeight: 95.0,
            barWeight: 20.0,
            availablePlates: platesWithout25,
            unit: .kg
        )

        XCTAssertTrue(result.isExactMatch)
        XCTAssertEqual(result.weightPerSide, 37.5, accuracy: 0.001)
        XCTAssertEqual(result.totalPlatesWeight, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.totalAchievedWeight, 95.0, accuracy: 0.001)
        XCTAssertEqual(result.remainderPerSide, 0.0, accuracy: 0.001)

        XCTAssertEqual(result.platesPerSide.count, 3)
        XCTAssertEqual(result.platesPerSide[0].weight, 20.0, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[0].count, 1)
        XCTAssertEqual(result.platesPerSide[1].weight, 15.0, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[1].count, 1)
        XCTAssertEqual(result.platesPerSide[2].weight, 2.5, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[2].count, 1)

        XCTAssertEqual(result.displayText, "1×20 kg + 1×15 kg + 1×2.5 kg")
    }

    func testCalculatePlatesUnderOrEqualBarWeight() {
        let resultEmpty = WarmupPlateEngine.calculatePlates(targetWeight: 20.0, barWeight: 20.0, availablePlates: WarmupPlateEngine.defaultPlatesKg)
        XCTAssertTrue(resultEmpty.isExactMatch)
        XCTAssertTrue(resultEmpty.platesPerSide.isEmpty)
        XCTAssertEqual(resultEmpty.totalAchievedWeight, 20.0, accuracy: 0.001)

        let resultUnder = WarmupPlateEngine.calculatePlates(targetWeight: 15.0, barWeight: 20.0, availablePlates: WarmupPlateEngine.defaultPlatesKg)
        XCTAssertFalse(resultUnder.isExactMatch)
        XCTAssertTrue(resultUnder.platesPerSide.isEmpty)
    }

    func testWarmupSetsExcludedFromVolumeAndCompletedCount() {
        let exercise = Exercise(
            id: "ex-bench",
            name: "Barbell Bench Press",
            sets: 3
        )
        let workout = Workout(
            id: "w1",
            day: 1,
            title: "Chest Day",
            exercises: [exercise]
        )

        let sets: [ExerciseSetLog] = [
            // 2 Warmup sets (both completed)
            ExerciseSetLog(id: "w1", setNumber: 1, weightKg: 20.0, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightKg: 50.0, completedReps: 5, isCompleted: true, isWarmup: true),
            // 3 Working sets (1 completed at 100kg x 8, 2 uncompleted)
            ExerciseSetLog(id: "s1", setNumber: 1, weightKg: 100.0, completedReps: 8, isCompleted: true, isWarmup: false),
            ExerciseSetLog(id: "s2", setNumber: 2, weightKg: 100.0, completedReps: 8, isCompleted: false, isWarmup: false),
            ExerciseSetLog(id: "s3", setNumber: 3, weightKg: 100.0, completedReps: 8, isCompleted: false, isWarmup: false)
        ]

        let draft = ActiveSessionDraft(
            id: UUID().uuidString,
            programId: "prog1",
            workout: workout,
            startedAt: "2026-09-19T20:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: [exercise.id: sets]
        )

        let progress = SessionProgress.from(draft: draft, nowEpochMillis: 5000)

        // Only the 1 completed working set should count!
        XCTAssertEqual(progress.completedSets, 1)
        // Only working set volume: 100 kg * 8 reps = 800 kg (warmup 20*10=200kg and 50*5=250kg MUST be excluded!)
        XCTAssertEqual(progress.volumeKg, 800.0, accuracy: 0.001)

        let exerciseLog = progress.exerciseLogs.first!
        // Target sets should only count working sets (3)
        XCTAssertEqual(exerciseLog.targetSets, 3)
        // All sets are recorded in logs with isWarmup preserved
        XCTAssertEqual(exerciseLog.sets.count, 3)
        XCTAssertTrue(exerciseLog.sets[0].isWarmup)
        XCTAssertTrue(exerciseLog.sets[1].isWarmup)
        XCTAssertFalse(exerciseLog.sets[2].isWarmup)
    }

    @MainActor
    func testWarmupPlateSheetSnapshot() {
        let sheetRamp = WarmupPlateSheet(
            exerciseName: "Barbell Bench Press",
            initialWorkingWeightKg: 100.0,
            initialBarType: .olympic20,
            initialPlatesKg: WarmupPlateEngine.defaultPlatesKg,
            unit: .kg,
            initialTab: .warmupRamp,
            onInsertWarmupSets: { _ in },
            onSaveBarType: { _ in },
            onSavePlates: { _ in }
        )
        let controllerRamp = UIHostingController(rootView: sheetRamp)
        controllerRamp.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controllerRamp.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let windowRamp = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        windowRamp.rootViewController = controllerRamp
        windowRamp.makeKeyAndVisible()
        controllerRamp.view.layoutIfNeeded()

        let rendererRamp = UIGraphicsImageRenderer(size: controllerRamp.view.bounds.size)
        let imageRamp = rendererRamp.image { ctx in
            controllerRamp.view.drawHierarchy(in: controllerRamp.view.bounds, afterScreenUpdates: true)
        }
        if let data = imageRamp.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_ramp_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote warmup ramp sheet snapshot to \(path)")
        }

        let sheetPlates = WarmupPlateSheet(
            exerciseName: "Barbell Bench Press",
            initialWorkingWeightKg: 100.0,
            initialBarType: .olympic20,
            initialPlatesKg: WarmupPlateEngine.defaultPlatesKg,
            unit: .kg,
            initialTab: .plateLoader,
            onInsertWarmupSets: { _ in },
            onSaveBarType: { _ in },
            onSavePlates: { _ in }
        )
        let controllerPlates = UIHostingController(rootView: sheetPlates)
        controllerPlates.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controllerPlates.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let windowPlates = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        windowPlates.rootViewController = controllerPlates
        windowPlates.makeKeyAndVisible()
        controllerPlates.view.layoutIfNeeded()

        let rendererPlates = UIGraphicsImageRenderer(size: controllerPlates.view.bounds.size)
        let imagePlates = rendererPlates.image { ctx in
            controllerPlates.view.drawHierarchy(in: controllerPlates.view.bounds, afterScreenUpdates: true)
        }
        if let data = imagePlates.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_plate_loader_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote plate loader sheet snapshot to \(path)")
        }
    }

    @MainActor
    func testActiveSessionWithWarmupSetsSnapshot() {
        let store = AppStore.shared
        let originalSession = store.activeSession

        let benchExercise = Exercise(
            id: "ex-bench-warmup",
            name: "Barbell Bench Press",
            exerciseId: "bench-press",
            prescription: "3×8-12",
            sets: 3
        )
        let workout = Workout(
            id: "w-chest-warmup",
            day: 1,
            title: "Push Day",
            exercises: [benchExercise]
        )

        let sets: [ExerciseSetLog] = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20.0, completedReps: 10, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "50", repsInput: "5", weightKg: 50.0, completedReps: 5, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w3", setNumber: 3, weightInput: "70", repsInput: "3", weightKg: 70.0, completedReps: 3, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w4", setNumber: 4, weightInput: "85", repsInput: "1", weightKg: 85.0, completedReps: 1, isCompleted: false, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "s1", setNumber: 1, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false),
            ExerciseSetLog(id: "s2", setNumber: 2, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false),
            ExerciseSetLog(id: "s3", setNumber: 3, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false)
        ]

        let draft = ActiveSessionDraft(
            id: "session-warmup-demo",
            programId: "prog1",
            workout: workout,
            startedAt: "2026-09-19T20:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000) - 900_000,
            currentExerciseIndex: 0,
            setsByExercise: [benchExercise.id: sets]
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
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_active_session_with_warmup_sets_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active session with warmups snapshot to \(path)")
        }

        store.activeSession = originalSession
    }

    @MainActor
    func testWarmupPlateCardInactiveSnapshot() {
        let card = WarmupPlateCard(
            warmupSets: [],
            onGenerateWarmup: {},
            onOpenPlates: {},
            onClearWarmups: {},
            onDismissLocked: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_plate_card_inactive_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote inactive warmup plate card snapshot to \(path)")
        }
    }

    @MainActor
    func testClearWarmupSetsPreservesCompletedSets() {
        let store = AppStore()
        let exercise = Exercise(id: "bench", name: "Bench", sets: 2, reps: RepTarget(min: 8, max: 12), restSeconds: 90)
        let workout = Workout(id: "w1", day: 1, title: "Push", exercises: [exercise])
        let session = ActiveSessionDraft(
            id: "s1",
            programId: "p1",
            workout: workout,
            startedAt: "2026-08-28T09:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: [
                exercise.id: [
                    ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
                    ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: false, isWarmup: true),
                    ExerciseSetLog(id: "s1", setNumber: 1, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: false, isWarmup: false)
                ]
            ]
        )
        store.activeSession = session
        store.clearWarmupSets(exerciseId: exercise.id)

        let sets = store.activeSession?.setsByExercise[exercise.id] ?? []
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].id, "w1")
        XCTAssertTrue(sets[0].isWarmup)
        XCTAssertTrue(sets[0].isCompleted)
        XCTAssertEqual(sets[0].setNumber, 1)

        XCTAssertEqual(sets[1].id, "s1")
        XCTAssertFalse(sets[1].isWarmup)
        XCTAssertEqual(sets[1].setNumber, 1)
    }

    @MainActor
    func testWarmupPlateCardActiveWithIncompleteWarmupsSnapshot() {
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        defer { ProAccessManager.shared.updateSubscriptionStatus(active: false) }

        let warmups = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: false, isWarmup: true)
        ]
        let card = WarmupPlateCard(
            warmupSets: warmups,
            onGenerateWarmup: {},
            onOpenPlates: {},
            onClearWarmups: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_plate_card_active_with_delete_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active warmup plate card with delete snapshot to \(path)")
        }
    }

    @MainActor
    func testWarmupPlateCardActiveAllCompletedSnapshot() {
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        defer { ProAccessManager.shared.updateSubscriptionStatus(active: false) }

        let warmups = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: true, isWarmup: true)
        ]
        let card = WarmupPlateCard(
            warmupSets: warmups,
            onGenerateWarmup: {},
            onOpenPlates: {},
            onClearWarmups: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_plate_card_active_all_completed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active warmup plate card with all completed snapshot to \(path)")
        }
    }

    @MainActor
    func testProgressionCoachCardInactiveSnapshot() {
        let dummyRecommendation = ExerciseProgressionRecommendation(
            exerciseId: "bench_press",
            exerciseName: "Bench Press",
            action: .increaseLoad,
            suggestedWeightKg: 82.5,
            suggestedWeightDisplay: "82.5 kg",
            suggestedRepsMin: 5,
            suggestedRepsMax: 5,
            weightDeltaDisplay: "+2.5 kg",
            rationaleKey: "progression.rationale.all_sets_hit_max_reps",
            rationaleArgs: ["reps": "5"]
        )
        let card = ProgressionCoachCard(
            recommendation: dummyRecommendation,
            onApplyTarget: {},
            onOpenInfo: {},
            onDismissLocked: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_progression_coach_card_inactive_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote inactive progression coach card snapshot to \(path)")
        }
    }

    @MainActor
    func testDismissProCardsInSessionAndRestoreFromSettings() {
        let store = AppStore.shared
        store.resetDismissedProCards()
        XCTAssertFalse(store.isProgressionCardDismissed)
        XCTAssertFalse(store.isWarmupCardDismissed)

        store.isProgressionCardDismissed = true
        XCTAssertTrue(store.isProgressionCardDismissed)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "pro_progression_card_dismissed"))

        store.isWarmupCardDismissed = true
        XCTAssertTrue(store.isWarmupCardDismissed)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "pro_warmup_card_dismissed"))

        store.resetDismissedProCards()
        XCTAssertFalse(store.isProgressionCardDismissed)
        XCTAssertFalse(store.isWarmupCardDismissed)
    }

    // MARK: - Form Lab Unit & Snapshot Tests

    func testFormLabRepMaxCalculations() {
        // Brzycki
        let brzycki1Rep = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 1, formula: .brzycki)
        XCTAssertEqual(brzycki1Rep, 100.0, accuracy: 0.001)

        let brzycki5Reps = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 5, formula: .brzycki)
        // 100 * 36 / (37 - 5) = 3600 / 32 = 112.5
        XCTAssertEqual(brzycki5Reps, 112.5, accuracy: 0.001)

        // Epley
        let epley10Reps = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 10, formula: .epley)
        // 100 * (1 + 10/30) = 133.333
        XCTAssertEqual(epley10Reps, 133.333, accuracy: 0.01)

        // Target N-RM
        let target5RM = FormLabEngine.calculateTargetNRM(oneRmKg: 112.5, targetReps: 5, formula: .brzycki)
        XCTAssertEqual(target5RM, 100.0, accuracy: 0.01)

        // Multi-rep targets
        let targets = FormLabEngine.computeRepMaxTargets(oneRmKg: 100.0, formula: .brzycki)
        XCTAssertEqual(targets.count, 5)
        XCTAssertEqual(targets[0].reps, 1)
        XCTAssertEqual(targets[0].estimatedWeightKg, 100.0, accuracy: 0.01)
        XCTAssertEqual(targets[1].reps, 3)
        XCTAssertEqual(targets[2].reps, 5)
        XCTAssertEqual(targets[3].reps, 8)
        XCTAssertEqual(targets[4].reps, 10)
    }

    func testFormLabLongitudinalCurve() {
        let session1 = WorkoutSessionRecord(
            id: "s1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest Day 1",
            startedAt: "2026-06-01T10:00:00Z",
            completedAt: "2026-06-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 800.0,
            totalCompletedSets: 10,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 10, isWarmup: false)
                    ]
                )
            ]
        )

        let session2 = WorkoutSessionRecord(
            id: "s2",
            programId: "p1",
            workoutId: "w2",
            workoutTitle: "Chest Day 2",
            startedAt: "2026-08-01T10:00:00Z",
            completedAt: "2026-08-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 10,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5, isWarmup: false)
                    ]
                )
            ]
        )

        let report = FormLabEngine.computeLongitudinalCurve(
            exerciseName: "Barbell Bench Press",
            history: [session1, session2],
            timeframe: .allTime,
            formula: .brzycki
        )

        XCTAssertEqual(report.points.count, 2)
        XCTAssertNotNil(report.start1rmKg)
        XCTAssertNotNil(report.current1rmKg)
        XCTAssertGreaterThan(report.current1rmKg!, report.start1rmKg!)
        XCTAssertGreaterThan(report.deltaKg, 0)
        XCTAssertGreaterThan(report.percentageGain, 0)
    }

    func testDistributionUsesExactCatalogClassifications() {
        XCTAssertGreaterThanOrEqual(ExerciseCatalog.canonicalExercises.count, 300)
        XCTAssertNotNil(ExerciseMuscleCatalog.shared)
        for exercise in ExerciseCatalog.canonicalExercises.values {
            let expected = ExerciseMuscleCatalog.shared?.profile(exercise.id)?.primary ?? []
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: exercise.id), expected, exercise.id)
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: exercise.name), expected, exercise.name)
        }
        for name in ["Seated Leg Curl", "Lying Leg Curl", "  SEATED LEG CURL  "] {
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: name), ["hamstrings"])
        }
        XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: "Barbell Curl"), ["biceps"])
        for name in ["My leg curl", "Custom curl", "My chest-supported row", "Unknown"] {
            XCTAssertTrue(FormLabEngine.resolveExerciseMuscles(exerciseName: name).isEmpty)
        }
    }

    func testDistributionKeepsGlutesSeparateAndReportsMissingWork() {
        func report(_ name: String, count: Int = 4) -> AntagonistBalanceReport {
            let sets = (1...count).map { SessionSetLog(setNumber: $0, weightKg: 40, reps: 8, isWarmup: false) }
                + [SessionSetLog(setNumber: 99, weightKg: 10, reps: 8, isWarmup: true)]
            let session = WorkoutSessionRecord(id: "classification", programId: "p", workoutId: "w", workoutTitle: "Test",
                startedAt: "2026-09-10T10:00:00Z", completedAt: "2026-09-10T11:00:00Z", durationSeconds: 3600,
                totalVolumeKg: 1280, totalCompletedSets: count, exerciseLogs: [SessionExerciseLog(exerciseName: name, sets: sets)])
            return FormLabEngine.computeAntagonistBalance(history: [session])
        }
        let squat = report("Barbell Back Squat")
        XCTAssertEqual(squat.quadHamstring.primarySets, 4)
        XCTAssertEqual(squat.quadHamstring.antagonistSets, 0)
        XCTAssertNil(squat.quadHamstring.ratio)
        XCTAssertEqual(squat.quadHamstring.alertMessageKey, "form_lab.balance.no_hamstrings")
        XCTAssertNotEqual(squat.quadHamstring.status, .optimal)
        let glutes = report("Barbell Hip Thrust")
        XCTAssertEqual(glutes.quadHamstring.antagonistSets, 0)
        XCTAssertEqual(glutes.upperLower.antagonistSets, 4)
        XCTAssertEqual(glutes.upperLower.alertMessageKey, "form_lab.balance.no_upper")
        let curl = report("Seated Leg Curl")
        XCTAssertEqual(curl.quadHamstring.antagonistSets, 4)
        XCTAssertEqual(curl.pushPull.antagonistSets, 0)
        XCTAssertEqual(curl.quadHamstring.alertMessageKey, "form_lab.balance.no_quads")
        XCTAssertEqual(report("Barbell Row").pushPull.alertMessageKey, "form_lab.balance.no_push")
        let push = report("Barbell Bench Press")
        XCTAssertNil(push.pushPull.ratio)
        XCTAssertEqual(push.pushPull.alertMessageKey, "form_lab.balance.no_pull")
        XCTAssertEqual(push.upperLower.alertMessageKey, "form_lab.balance.no_lower")
        XCTAssertEqual(report("Barbell Bench Press", count: 1).pushPull.alertMessageKey, "form_lab.balance.no_pull")
        let unknown = report("My leg curl")
        XCTAssertEqual(unknown.totalWorkingSets, 4)
        XCTAssertEqual(unknown.unclassifiedWorkingSets, 4)
        XCTAssertEqual(unknown.pushPull.antagonistSets, 0)
        XCTAssertEqual(unknown.upperLower.antagonistSets, 0)
    }

    func testFormLabAntagonistBalance() {
        let session = WorkoutSessionRecord(
            id: "s-balance",
            programId: "p1",
            workoutId: "w-bal",
            workoutTitle: "Push Day Heavy",
            startedAt: "2026-09-01T10:00:00Z",
            completedAt: "2026-09-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1500.0,
            totalCompletedSets: 11,
            exerciseLogs: [
                // 10 push sets
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 30.0, reps: 10, isWarmup: false) }
                ),
                // 1 pull set
                SessionExerciseLog(
                    exerciseName: "Lat Pulldown",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 50.0, reps: 10, isWarmup: false)]
                )
            ]
        )

        let balance = FormLabEngine.computeAntagonistBalance(
            history: [session],
            timeframe: .allTime
        )

        XCTAssertEqual(balance.pushPull.primarySets, 10)
        XCTAssertEqual(balance.pushPull.antagonistSets, 1)
        XCTAssertEqual(balance.pushPull.ratio, 10.0)
        XCTAssertEqual(balance.pushPull.status, AntagonistStatus.primaryDominant)
    }

    func testAntagonistBalanceZeroAndMissingData() {
        // Empty history: all ratios nil, insufficient data
        let emptyBalance = FormLabEngine.computeAntagonistBalance(history: [], timeframe: .allTime)
        XCTAssertEqual(emptyBalance.pushPull.primarySets, 0)
        XCTAssertEqual(emptyBalance.pushPull.antagonistSets, 0)
        XCTAssertNil(emptyBalance.pushPull.ratio)
        XCTAssertEqual(emptyBalance.pushPull.status, .insufficientData)
        XCTAssertNil(emptyBalance.quadHamstring.ratio)
        XCTAssertEqual(emptyBalance.quadHamstring.status, .insufficientData)
        XCTAssertNil(emptyBalance.upperLower.ratio)
        XCTAssertEqual(emptyBalance.upperLower.status, .insufficientData)

        // Session with push sets only (denominator = 0): ratio must be nil, not fabricated 2.0
        let pushOnlySession = WorkoutSessionRecord(
            id: "s-push-only",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest Only",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }
                )
            ]
        )
        let pushOnlyBalance = FormLabEngine.computeAntagonistBalance(history: [pushOnlySession], timeframe: .allTime)
        XCTAssertEqual(pushOnlyBalance.pushPull.primarySets, 4)
        XCTAssertEqual(pushOnlyBalance.pushPull.antagonistSets, 0)
        XCTAssertNil(pushOnlyBalance.pushPull.ratio)
        XCTAssertEqual(pushOnlyBalance.pushPull.status, .primaryDominant)

        // Low volume (1 push, 1 pull < 3 sets threshold): status insufficientData, ratio nil
        let lowVolumeSession = WorkoutSessionRecord(
            id: "s-low",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Quick Session",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T10:30:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 500.0,
            totalCompletedSets: 2,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8, isWarmup: false)]
                ),
                SessionExerciseLog(
                    exerciseName: "Lat Pulldown",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 50.0, reps: 10, isWarmup: false)]
                )
            ]
        )
        let lowVolumeBalance = FormLabEngine.computeAntagonistBalance(history: [lowVolumeSession], timeframe: .allTime)
        XCTAssertEqual(lowVolumeBalance.pushPull.primarySets, 1)
        XCTAssertEqual(lowVolumeBalance.pushPull.antagonistSets, 1)
        XCTAssertNil(lowVolumeBalance.pushPull.ratio)
        XCTAssertEqual(lowVolumeBalance.pushPull.status, .insufficientData)
    }

    func testNegativeWeightFormatting() {
        XCTAssertEqual(WeightUnit.kg.formatWeight(-5.0), "-5")
        XCTAssertEqual(WeightUnit.kg.formatWeight(-5.5), "-5.5")
        XCTAssertEqual(WeightUnit.lbs.formatWeight(-5.0), "-11")
        XCTAssertEqual(WeightUnit.kg.formatWeightWithUnit(-5.0), "-5 kg")
        XCTAssertEqual(WeightUnit.kg.formatWeight(0.0), "0")
    }

    func testFormLabCloudMirrorSyncAndReadRoundtrip() throws {
        let payload = "{\"schemaVersion\":4,\"programs\":[],\"activeProgramId\":\"\",\"history\":[]}"
        CloudMirrorManager.shared.isEnabled = true

        // 1. When not Pro, syncNow must throw
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        XCTAssertThrowsError(try CloudMirrorManager.shared.syncNow(backupJson: payload)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "CloudMirror")
            XCTAssertEqual(nsError.code, 403)
        }

        // 2. When Pro is active, syncNow succeeds
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        let size = try CloudMirrorManager.shared.syncNow(backupJson: payload)
        XCTAssertGreaterThan(size, 0)

        // 3. Even after Pro expires or for free users, reading existing snapshot remains free
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        let readJson = try CloudMirrorManager.shared.readLatestSnapshot()
        XCTAssertEqual(readJson, payload)

        let status = CloudMirrorManager.shared.getStatus()
        XCTAssertTrue(status.isEnabled)
        XCTAssertFalse(status.isEncrypted)
        XCTAssertNotNil(status.lastSyncTimestamp)
        XCTAssertEqual(status.snapshotSizeBytes, size)
    }

    func testCloudMirrorPendingSyncStagingAndRetry() throws {
        let payload = "{\"schemaVersion\":4,\"pendingTest\":true}"
        CloudMirrorManager.shared.isEnabled = true
        ProAccessManager.shared.updateSubscriptionStatus(active: true)

        CloudMirrorManager.shared.clearPendingSync()
        XCTAssertFalse(CloudMirrorManager.shared.hasPendingSync)

        CloudMirrorManager.shared.savePendingSync(backupJson: payload)
        XCTAssertTrue(CloudMirrorManager.shared.hasPendingSync)

        // Retry pending sync
        CloudMirrorManager.shared.retryPendingSyncIfAny()

        let exp = expectation(description: "Wait for autoSync")
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            if !CloudMirrorManager.shared.hasPendingSync || Date().timeIntervalSince(start) > 4.0 {
                t.invalidate()
                exp.fulfill()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        wait(for: [exp], timeout: 5.0)

        let readJson = try CloudMirrorManager.shared.readLatestSnapshot()
        XCTAssertEqual(readJson, payload)
        XCTAssertFalse(CloudMirrorManager.shared.hasPendingSync)
    }

    @MainActor
    func testFormLabViewSnapshot() {
        let store = AppStore()
        // Provide mock history
        let session = WorkoutSessionRecord(
            id: "s-lab-snap",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Strength & Power",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 2400.0,
            totalCompletedSets: 15,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 100.0, reps: 5, isWarmup: false) }
                ),
                SessionExerciseLog(
                    exerciseName: "Barbell Squat",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 140.0, reps: 5, isWarmup: false) }
                )
            ]
        )
        var state = store.state
        state.history = [session]
        store.saveState(state)

        let labView = FormLabView(store: store)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_matrix_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabInfoSheetSnapshot() {
        let sheet = FormLabInfoSheet()

        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_info_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Info Sheet snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabCurvesSnapshot() {
        let store = AppStore()
        let session1 = WorkoutSessionRecord(
            id: "s1", programId: "p1", workoutId: "w1", workoutTitle: "Chest Day 1",
            startedAt: "2026-06-01T10:00:00Z", completedAt: "2026-06-01T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 800.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8, isWarmup: false)])]
        )
        let session2 = WorkoutSessionRecord(
            id: "s2", programId: "p1", workoutId: "w2", workoutTitle: "Chest Day 2",
            startedAt: "2026-07-15T10:00:00Z", completedAt: "2026-07-15T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 1000.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 95.0, reps: 6, isWarmup: false)])]
        )
        let session3 = WorkoutSessionRecord(
            id: "s3", programId: "p1", workoutId: "w3", workoutTitle: "Chest Day 3",
            startedAt: "2026-09-10T10:00:00Z", completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 1200.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 110.0, reps: 5, isWarmup: false)])]
        )
        var state = store.state
        state.history = [session1, session2, session3]
        store.saveState(state)

        let labView = FormLabView(store: store, initialTab: .curves)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_curves_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Curves snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabBalanceSnapshot() {
        let store = AppStore()
        let session = WorkoutSessionRecord(
            id: "s-bal-snap", programId: "p1", workoutId: "w1", workoutTitle: "Full Body Structural",
            startedAt: "2026-09-12T10:00:00Z", completedAt: "2026-09-12T11:30:00Z",
            durationSeconds: 5400, totalVolumeKg: 3500.0, totalCompletedSets: 22,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 90.0, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Bent Over Barbell Row", sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Barbell Squat", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 130.0, reps: 6, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Romanian Deadlift", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 110.0, reps: 8, isWarmup: false) })
            ]
        )
        var state = store.state
        state.history = [session]
        store.saveState(state)

        let labView = FormLabView(store: store, initialTab: .balance)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_balance_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Balance snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabMirrorSnapshot() {
        let store = AppStore()
        let labView = FormLabView(store: store, initialTab: .mirror)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 600)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_mirror_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Mirror snapshot to \(path)")
        }
    }

    func testVolumeMatrixPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .volumeMatrix)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_volume_matrix_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Volume Matrix Paywall snapshot to \(path)")
        }
    }

    func testFormLabPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .formLab)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_rep_lab_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Rep Lab Paywall snapshot to \(path)")
        }
    }

    func testWarmupCalculatorPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .warmupCalculator)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_warmup_calculator_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Warmup Calculator Paywall snapshot to \(path)")
        }
    }

    @MainActor
    func testVolumeMatrixLockedBlurredPreviewSnapshot() {
        let store = AppStore.shared
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        ProAccessManager.shared.resetOverrides()

        // Populate a completed workout so heatmaps and metrics glow through
        let session = WorkoutSessionRecord(
            id: UUID().uuidString,
            programId: "prog_test",
            workoutId: "w1",
            workoutTitle: "Push Strength",
            startedAt: "2026-09-20T10:00:00.000Z",
            completedAt: "2026-09-20T10:45:00.000Z",
            durationSeconds: 2700,
            totalVolumeKg: 4250.0,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 90, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 100, reps: 6)
                    ]
                ),
                SessionExerciseLog(
                    exerciseName: "Barbell Squat",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 120, reps: 8),
                        SessionSetLog(setNumber: 2, weightKg: 130, reps: 8)
                    ]
                )
            ]
        )
        store.state.history.append(session)

        let view = HistoryView(
            store: store,
            initialTab: .volumeMatrix,
            onOpenSettings: {},
            onSelectRecord: { _ in }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_volume_matrix_locked_blurred_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Volume Matrix Locked Blurred snapshot to \(path)")
        }
    }

    func testActiveWeekWithFiveDayScheduleReconcilesAllUncompletedDaysAsMissed() {
        let testToday = "2026-09-21"
        let mon = WorkoutSessionRecord(
            id: "s-mon", programId: "p5", workoutId: "w-push", workoutTitle: "Push",
            startedAt: "2026-09-14T10:00:00Z", completedAt: "2026-09-14T11:00:00Z", durationSeconds: 3600,
            isComplete: false
        )
        let tue = WorkoutSessionRecord(
            id: "s-tue", programId: "p5", workoutId: "w-pull", workoutTitle: "Pull",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 3600,
            isComplete: true
        )
        let program = Program(
            id: "p5", name: "5-Day Split",
            workouts: [
                Workout(id: "w-push", day: 1, title: "Push", exercises: [Exercise(id: "e1", name: "Bench", sets: 3)]),
                Workout(id: "w-pull", day: 2, title: "Pull", exercises: [Exercise(id: "e2", name: "Row", sets: 3)]),
                Workout(id: "w-legs", day: 4, title: "Legs", exercises: [Exercise(id: "e3", name: "Squat", sets: 3)]),
                Workout(id: "w-upper", day: 5, title: "Upper", exercises: [Exercise(id: "e4", name: "OHP", sets: 3)]),
                Workout(id: "w-arms", day: 6, title: "Arms", exercises: [Exercise(id: "e5", name: "Curls", sets: 3)])
            ]
        )
        let existingHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-21",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: ["2026-09-19"],
            entries: [
                WorkoutDayEntry(id: "session:s-mon", date: "2026-09-14", status: .unfinished),
                WorkoutDayEntry(id: "session:s-tue", date: "2026-09-15", status: .completed)
            ]
        )
        let restored = WorkoutCalendar.restore(
            raw: existingHistory,
            sessions: [mon, tue],
            today: testToday,
            weekdays: [1, 2, 4, 5, 6],
            programs: [program]
        )
        XCTAssertEqual(restored.missedDates, ["2026-09-17", "2026-09-18", "2026-09-19"])

        let statuses = WorkoutCalendar.statuses(history: restored, today: testToday)
        XCTAssertEqual(statuses["2026-09-14"], .unfinished)
        XCTAssertEqual(statuses["2026-09-15"], .completed)
        XCTAssertNil(statuses["2026-09-16"], "Wednesday is a rest day")
        XCTAssertEqual(statuses["2026-09-17"], .missed)
        XCTAssertEqual(statuses["2026-09-18"], .missed)
        XCTAssertEqual(statuses["2026-09-19"], .missed)
        XCTAssertNil(statuses["2026-09-20"], "Sunday is a rest day")

        let weekDays = ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"]
        let count = weekDays.compactMap { statuses[$0] }.count
        XCTAssertEqual(count, 5, "Exactly 5 scheduled workout days in that week must have a status")
    }

    func testGhostTargetCalculationAndProgressionTargets() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [
            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7)
        ]

        // Set 1 target: based on 100kg x 8
        let target1 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)
        XCTAssertFalse(target1.isFirstSession)
        XCTAssertEqual(target1.lastWeekWeightKg ?? 0.0, 100.0, accuracy: 0.01)
        XCTAssertEqual(target1.lastWeekReps, 8)
        XCTAssertEqual(target1.targetWeightKg, 100.0, accuracy: 0.01)
        XCTAssertEqual(target1.targetReps, 9)
        XCTAssertEqual(target1.altWeightKg ?? 0.0, 102.5, accuracy: 0.01)
        XCTAssertEqual(target1.altReps, 7)

        // Set 2 target: based on 100kg x 7
        let target2 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 1, exercise: exercise, unit: .kg)
        XCTAssertEqual(target2.lastWeekReps, 7)
        XCTAssertEqual(target2.targetReps, 8)
        XCTAssertEqual(target2.altWeightKg ?? 0.0, 102.5, accuracy: 0.01)
        XCTAssertEqual(target2.altReps, 6)

        // First session (no history)
        let firstTarget = WorkoutSessionUtils.computeGhostTarget(previousSets: [], workingSetIndex: 0, exercise: exercise, unit: .kg)
        XCTAssertTrue(firstTarget.isFirstSession)
        XCTAssertNil(firstTarget.lastWeekWeightKg)
        XCTAssertNil(firstTarget.lastWeekReps)
        XCTAssertEqual(firstTarget.targetReps, 8)
    }

    func testLogbookBeatDetectionAndFormatting() {
        let exercise = Exercise(id: "bench", name: "Bench Press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8)]
        let target = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)

        // Rep progression beat (+1 rep)
        let beatRep = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 9, target: target)
        XCTAssertNotNil(beatRep)
        XCTAssertEqual(beatRep?.repDelta, 1)
        XCTAssertEqual(beatRep?.weightDeltaKg ?? 0.0, 0.0, accuracy: 0.01)
        let badgeRep = WorkoutSessionUtils.formatLogbookBeatBadge(result: beatRep!, unit: .kg)
        XCTAssertTrue(badgeRep.contains("+1 REP") || badgeRep.contains("+1 TEKRAR"))

        // Load progression beat (102.5kg x 7)
        let beatLoad = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 102.5, loggedReps: 7, target: target)
        XCTAssertNotNil(beatLoad)
        XCTAssertEqual(beatLoad?.weightDeltaKg ?? 0.0, 2.5, accuracy: 0.01)
        let badgeLoad = WorkoutSessionUtils.formatLogbookBeatBadge(result: beatLoad!, unit: .kg)
        XCTAssertTrue(badgeLoad.contains("+2.5 KG"))

        // Rejection of matched or subpar performances
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 8, target: target))
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 7, target: target))
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 90.0, loggedReps: 8, target: target))

        // Notice text formatting
        let notice = WorkoutSessionUtils.formatLogbookBeatNotice(result: beatRep!, unit: .kg)
        XCTAssertTrue(notice.contains("100 kg × 9") && notice.contains("100 kg × 8"))
    }

    @MainActor
    func testSetLoggingTableActiveGhostTargetSnapshot() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [
            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7),
            SessionSetLog(setNumber: 3, weightKg: 95.0, reps: 8)
        ]
        let target1 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)
        let target2 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 1, exercise: exercise, unit: .kg)
        let target3 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 2, exercise: exercise, unit: .kg)

        // Set 1 completed with logbook beat: 100kg x 9 (+1 rep)
        let beatSet1 = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 9, target: target1)!

        let testSets = [
            ExerciseSetLog(setNumber: 1, weightInput: "100", repsInput: "9", weightKg: 100.0, completedReps: 9, isCompleted: true, inputTouched: true),
            ExerciseSetLog(setNumber: 2, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false, inputTouched: false),
            ExerciseSetLog(setNumber: 3, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false, inputTouched: false)
        ]

        let table = SetLoggingTable(
            sets: testSets,
            prescription: "3 × 8–12",
            isRestActive: false,
            prText: "100x8",
            onUpdateSet: { _, _, _ in },
            onToggleCompleteSet: { _ in },
            onAddSet: {},
            onRemoveSet: { _ in },
            weightUnit: .kg,
            ghostTargets: [0: target1, 1: target2, 2: target3],
            logbookBeatenSets: [0: beatSet1]
        )

        let container = VStack {
            table
        }
        .padding(16)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: container)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 340)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 340))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_ghost_target_set_table_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Ghost Target Set Table snapshot to \(path)")
        }
    }
}
