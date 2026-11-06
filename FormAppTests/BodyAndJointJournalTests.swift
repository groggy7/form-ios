import XCTest
import SwiftUI
@testable import FormApp

/// Shared fixtures from docs/design/body-and-joint-journal.md, plus storage and session rules.
/// Android BodyAndJointJournalTest covers the same cases.
final class BodyAndJointJournalTests: XCTestCase {
    private let day0 = BodyDay.number("2026-09-01")!
    private func date(_ offset: Int) -> String { BodyDay.string(day0 + offset) }
    private func weighIn(_ offset: Int, _ kg: Double) -> BodyEntry { BodyEntry(date: date(offset), bodyweightKg: kg) }

    func testTrendFixtures() {
        let single = BodyTrends.trend([weighIn(0, 80)])
        XCTAssertEqual(single.first?.trendKg ?? 0, 80, accuracy: 1e-9)
        XCTAssertNil(BodyTrends.weeklyChange(single))
        XCTAssertEqual(BodyTrends.trend([weighIn(0, 80), weighIn(1, 81)]).last?.trendKg ?? 0, 80.1, accuracy: 1e-9)
        XCTAssertEqual(BodyTrends.trend([weighIn(3, 82), weighIn(0, 80)]).last?.trendKg ?? 0, 80.542, accuracy: 1e-9)
    }

    func testWeeklyChangeFixtures() throws {
        XCTAssertEqual(try XCTUnwrap(BodyTrends.weeklyChange(BodyTrends.trend([weighIn(0, 80), weighIn(7, 79.5), weighIn(14, 79)]))), -0.5, accuracy: 1e-9)
        XCTAssertNil(BodyTrends.weeklyChange(BodyTrends.trend([weighIn(0, 80), weighIn(5, 79), weighIn(10, 78)])))
        // Only the 28 days ending at the latest weigh-in count.
        let old = BodyTrends.trend([weighIn(0, 90), weighIn(40, 80), weighIn(47, 79.5), weighIn(54, 79)])
        XCTAssertEqual(try XCTUnwrap(BodyTrends.weeklyChange(old)), -0.5, accuracy: 1e-9)
    }

    func testMeasurementChangesUseTheLast90DaysAndNeedTwoEntries() {
        let entries = [BodyEntry(date: date(0), waistCm: 90), BodyEntry(date: date(20), waistCm: 88, armCm: 38), BodyEntry(date: date(100), waistCm: 86.5)]
        let changes = BodyTrends.measurementChanges(entries, today: date(100))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.metric, .waist)
        XCTAssertEqual(changes.first?.latestCm ?? 0, 86.5, accuracy: 1e-9)
        XCTAssertEqual(changes.first?.changeCm ?? 0, -1.5, accuracy: 1e-9)
        XCTAssertEqual(changes.first?.since, date(20))
    }

    private func record(_ id: String, _ day: String, _ logs: [SessionExerciseLog]) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: id, programId: "plan", workoutId: "day", workoutTitle: "Day", startedAt: "\(day)T09:00:00Z",
                             completedAt: "\(day)T10:00:00Z", durationSeconds: 3600, exerciseLogs: logs, performedDate: day)
    }

    private func log(_ name: String, _ id: String? = nil, _ rating: JointStress?, _ sets: [SessionSetLog]) -> SessionExerciseLog {
        SessionExerciseLog(exerciseName: name, sets: sets, exerciseId: id, jointStress: rating?.rawValue)
    }

    func testJointOrderFixtureAndWindow() {
        let today = date(60)
        let set = [SessionSetLog(setNumber: 1, weightKg: 50, reps: 8)]
        let history = [
            record("1", date(50), [log("A", nil, .high, set), log("B", nil, .mild, set), log("C", nil, .high, set)]),
            record("2", date(57), [log("A", nil, .noStress, set), log("B", nil, .mild, set), log("C", nil, .high, set)]),
            // Outside the 8-week window, and an unrated log.
            record("3", date(4), [log("B", nil, .high, set), log("D", nil, nil, set)])
        ]
        let summaries = JointJournal.summaries(history: history, today: today)
        XCTAssertEqual(summaries.map(\.exerciseName), ["C", "A", "B"])
        XCTAssertEqual(summaries[1].recent.map(\.rating), [.high, .noStress])
        XCTAssertEqual([summaries[1].high, summaries[1].mild, summaries[1].none], [1, 0, 1])
        XCTAssertEqual(summaries.last?.total, 2)
    }

    func testJointLoadIsTheHeaviestWorkingSetOrNoneForBodyweight() {
        let today = date(10)
        let history = [record("1", today, [
            log("Barbell Bench Press", "barbell-bench-press", .mild, [SessionSetLog(setNumber: 1, weightKg: 120, reps: 5, isWarmup: true),
                SessionSetLog(setNumber: 2, weightKg: 90, reps: 8), SessionSetLog(setNumber: 3, weightKg: 95, reps: 6)]),
            log("Push-Up", "push-up", .noStress, [SessionSetLog(setNumber: 1, weightKg: 0, reps: 20)])
        ])]
        let byName = Dictionary(uniqueKeysWithValues: JointJournal.summaries(history: history, today: today).map { ($0.exerciseName, $0) })
        XCTAssertEqual(byName["Barbell Bench Press"]?.recent.first?.topLoadKg, 95)
        XCTAssertNotNil(byName["Push-Up"])
        XCTAssertNil(byName["Push-Up"]?.recent.first?.topLoadKg)
    }

    @MainActor func testHistoryRatesOneSavedExerciseWithWorkingSets() throws {
        let saved = record("1", date(10), [
            log("Barbell Bench Press", "barbell-bench-press", nil, [SessionSetLog(setNumber: 1, weightKg: 60, reps: 8)]),
            log("Barbell Bench Press", "barbell-bench-press", .mild, [SessionSetLog(setNumber: 1, weightKg: 80, reps: 5)]),
            log("Warmup Only", nil, nil, [SessionSetLog(setNumber: 1, weightKg: 20, reps: 10, isWarmup: true)])
        ])
        // The second occurrence keeps its own rating; nothing else in the record changes.
        let rated = try XCTUnwrap(JointJournal.rated(saved, logIndex: 0, rating: .high))
        XCTAssertEqual(rated.exerciseLogs.map(\.jointStress), ["high", "mild", nil])
        var expected = saved
        expected.exerciseLogs[0].jointStress = "high"
        XCTAssertEqual(rated, expected)
        // An exercise with no working set, or a missing one, has nothing to rate.
        XCTAssertNil(JointJournal.rated(saved, logIndex: 2, rating: .noStress))
        XCTAssertNil(JointJournal.rated(saved, logIndex: 3, rating: .noStress))
        XCTAssertNil(JointJournal.rated(saved, logIndex: -1, rating: .noStress))

        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        var state = store.state
        state.history = [saved]
        store.state = state
        XCTAssertTrue(store.setHistoryJointStress(recordId: "1", logIndex: 0, rating: .high))
        XCTAssertTrue(store.setHistoryJointStress(recordId: "1", logIndex: 1, rating: nil))
        XCTAssertEqual(store.state.history.first?.exerciseLogs.map(\.jointStress), ["high", nil, nil])
        XCTAssertFalse(store.setHistoryJointStress(recordId: "missing", logIndex: 0, rating: .mild))
        XCTAssertFalse(store.setHistoryJointStress(recordId: "1", logIndex: 2, rating: .mild))
    }

    func testJointStressRatingIsOfferedFromTheFirstCompletedWorkingSet() {
        let warmup = ExerciseSetLog(setNumber: 1, isCompleted: true, isWarmup: true)
        let first = ExerciseSetLog(setNumber: 2)
        var done = first
        done.isCompleted = true
        let second = ExerciseSetLog(setNumber: 3)
        // A completed warmup alone is not an exercise to rate.
        XCTAssertFalse(WorkoutSessionUtils.offersJointStressRating([warmup, first, second]))
        // One working set is enough: a lifter who stops early because a joint hurts can still rate it.
        XCTAssertTrue(WorkoutSessionUtils.offersJointStressRating([warmup, done, second]))
        XCTAssertFalse(WorkoutSessionUtils.offersJointStressRating([]))
    }

    func testRelativeStrengthUsesReferenceBarbellLiftsAndNeedsARecentWeighIn() {
        let today = date(40)
        // Bodyweight, machine, hip-thrust and custom lifts would distort a bodyweight ratio; only reference lifts count.
        let history = [record("1", date(35), [
            log("Barbell Back Squat", "barbell-back-squat", nil, [SessionSetLog(setNumber: 1, weightKg: 140, reps: 1)]),
            log("Weighted Pull-Ups", "weighted-pull-ups", nil, [SessionSetLog(setNumber: 1, weightKg: 40, reps: 1)]),
            log("Leg Press", "leg-press-45-degree", nil, [SessionSetLog(setNumber: 1, weightKg: 300, reps: 1)]),
            log("Barbell Hip Thrust", "barbell-hip-thrust", nil, [SessionSetLog(setNumber: 1, weightKg: 200, reps: 1)]),
            log("My Sled Push", nil, nil, [SessionSetLog(setNumber: 1, weightKg: 250, reps: 1)]),
            log("Barbell Bench Press", "barbell-bench-press", nil, [SessionSetLog(setNumber: 1, weightKg: 100, reps: 1)])
        ])]
        let recent = BodyTrends.trend([BodyEntry(date: date(38), bodyweightKg: 80)])
        guard case .rows(_, let rows) = BodyTrends.relativeStrength(points: recent, history: history, today: today) else {
            return XCTFail("Expected rows")
        }
        XCTAssertEqual(rows.map(\.exerciseName), ["Barbell Back Squat", "Barbell Bench Press"])
        XCTAssertEqual(rows.first?.ratio ?? 0, 1.75, accuracy: 1e-9)
        let stale = BodyTrends.trend([BodyEntry(date: date(9), bodyweightKg: 80)])
        XCTAssertEqual(BodyTrends.relativeStrength(points: stale, history: history, today: today), .needsWeighIn)
        XCTAssertEqual(BodyTrends.relativeStrength(points: recent, history: [], today: today), .noLifts)
    }

    func testSanitizeDropsBadValuesKeepsOnePerDateAndSorts() {
        let clean = BodyLog.sanitize([
            BodyEntry(date: "2026-10-10", bodyweightKg: 80),
            BodyEntry(date: "not-a-date", bodyweightKg: 80),
            BodyEntry(date: "2026-10-25", bodyweightKg: 80),
            BodyEntry(date: "2026-10-05", bodyweightKg: 1_000, waistCm: 85),
            BodyEntry(date: "2026-10-06", bodyweightKg: .nan),
            BodyEntry(date: "2026-10-10", bodyweightKg: 81)
        ], today: "2026-10-20")
        XCTAssertEqual(clean, [BodyEntry(date: "2026-10-05", waistCm: 85), BodyEntry(date: "2026-10-10", bodyweightKg: 81)])
        XCTAssertEqual(BodyLog.sanitize([BodyEntry(date: "2026-10-21", armCm: 38)], today: "2026-10-20").map(\.date), ["2026-10-21"])
    }

    func testUnitsConvertDisplayAndParseOneDecimal() {
        let previous = LanguageManager.shared.languagePreference
        LanguageManager.setLanguage("en")
        defer { LanguageManager.setLanguage(previous) }
        XCTAssertEqual(BodyUnits.format(80.5, locale: Locale(identifier: "de")), "80,5")
        XCTAssertEqual(BodyUnits.formatCanonical(.bodyweight, BodyUnits.toCanonical(.bodyweight, 180.5, unit: .lbs), unit: .lbs), "180.5")
        XCTAssertEqual(BodyUnits.toCanonical(.arm, 32, unit: .lbs), 2.54 * 32, accuracy: 1e-9)
        XCTAssertEqual(BodyUnits.formatCanonical(.arm, 81.28, unit: .lbs), "32")
        XCTAssertEqual(BodyUnits.formatCanonical(.bodyweight, 80, unit: .kg), "80")
        XCTAssertEqual(BodyUnits.parse("80,5"), 80.5)
        XCTAssertNil(BodyUnits.parse("80.55"))
        XCTAssertNil(BodyUnits.parse(""))
        let range = BodyUnits.displayRange(.bodyweight, unit: .lbs)
        XCTAssertEqual(range.0, "44.1")
        XCTAssertEqual(range.1, "881.8")
    }

    func testBackupRoundTripsTheBodyLogAtSchema6() throws {
        let entries = [BodyEntry(date: "2026-10-01", bodyweightKg: 80), BodyEntry(date: "2026-10-08", bodyweightKg: 79.4, waistCm: 86)]
        let state = StoredAppState(programs: [], activeProgramId: "", currentWeekKey: "2026-W43", bodyEntries: entries)
        let data = try JSONEncoder().encode(FullBackupDocument(state: state, weightUnit: .kg))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, StoredAppState.currentSchemaVersion)
        XCTAssertEqual((json["bodyEntries"] as? [Any])?.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(FullBackupDocument.self, from: data).state.bodyEntries, entries)
        // Older backups carry no body log; newer schemas are refused rather than silently dropped.
        let old = #"{"schemaVersion":5,"programs":[],"activeProgramId":"","completed":[],"currentWeekKey":"2026-W43","weeklyArchives":[],"history":[]}"#
        XCTAssertNil(try JSONDecoder().decode(FullBackupDocument.self, from: Data(old.utf8)).state.bodyEntries)
        let newer = old.replacingOccurrences(of: "\"schemaVersion\":5", with: "\"schemaVersion\":\(StoredAppState.currentSchemaVersion + 1)")
        XCTAssertThrowsError(try JSONDecoder().decode(FullBackupDocument.self, from: Data(newer.utf8)))
        let empty = try JSONEncoder().encode(FullBackupDocument(state: StoredAppState(currentWeekKey: "2026-W43"), weightUnit: .kg))
        XCTAssertNil((try JSONSerialization.jsonObject(with: empty) as? [String: Any])?["bodyEntries"])
    }

    func testJointStressIsSavedRestoredAndDroppedOnReplace() {
        let bench = Exercise(id: "bench", name: "Bench", exerciseId: "barbell-bench-press", sets: 1, reps: RepTarget(min: 8, max: 12))
        let workout = Workout(id: "upper", day: 1, title: "Upper", exercises: [bench])
        var draft = ActiveSessionDraft(programId: "plan", workout: workout, startedAt: "2026-10-20T09:00:00Z", startedAtEpochMillis: 1_000,
                                       setsByExercise: [bench.id: [ExerciseSetLog(setNumber: 1, weightInput: "60", repsInput: "10",
                                                                                   weightKg: 60, completedReps: 10, isCompleted: true)]])
        draft.jointStressByExercise = [bench.id: JointStress.mild.rawValue]
        let saved = SessionProgress.from(draft: draft, nowEpochMillis: 5_000).exerciseLogs.first
        XCTAssertEqual(saved?.jointStress, "mild")

        let record = WorkoutSessionRecord(programId: "plan", workoutId: "upper", workoutTitle: "Upper", startedAt: "2026-10-20T09:00:00Z",
                                          completedAt: "2026-10-20T09:30:00Z", durationSeconds: 1800,
                                          exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", exerciseId: "barbell-bench-press", jointStress: "high")],
                                          workoutSnapshot: workout)
        XCTAssertEqual(WorkoutSessionUtils.restoreJointStressFromHistory(workout: workout, record: record), [bench.id: "high"])
        XCTAssertNil(JointStress(rawValue: "severe"))

        let decoded = try? JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded?.jointStressByExercise, [bench.id: "mild"])
    }

    /// Captures for review under forcedrep-ios/build/body-journal-review/: a saved day's rating lines, rated and
    /// unrated, at 393pt and at 320pt with the largest standard text, in every language.
    @MainActor func testHistoryDetailRatingLinesRenderInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/body-journal-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let bench = Exercise(id: "bench", name: "Bench Press", sets: 2, reps: RepTarget(min: 8, max: 12))
        let row = Exercise(id: "row", name: "Barbell Row", sets: 2, reps: RepTarget(min: 8, max: 12))
        let workout = Workout(id: "upper", day: 1, title: "Upper", exercises: [bench, row])
        let record = WorkoutSessionRecord(id: "saved", programId: "plan", workoutId: workout.id, workoutTitle: workout.title,
            startedAt: "2026-10-20T09:00:00Z", completedAt: "2026-10-20T10:00:00Z", durationSeconds: 3600, totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: bench.name, sets: [1, 2].map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 8) },
                                   targetSets: 2, jointStress: "mild"),
                SessionExerciseLog(exerciseName: row.name, sets: [1, 2].map { SessionSetLog(setNumber: $0, weightKg: 70, reps: 10) }, targetSets: 2)
            ], isComplete: true, workoutSnapshot: workout, performedDate: "2026-10-20")
        let detail = HistoryDayDetailData(date: WorkoutCalendar.parseDate("2026-10-20")!, dateString: "2026-10-20", status: .completed,
                                          sessionRecord: record, workout: workout)
        // Rows hand back the record and the log they rate.
        let items = HistoryDayDetailData.buildExerciseProgress(sessionRecord: record, workout: workout, history: [record])
        XCTAssertEqual(items.map(\.logIndex), [0, 1])
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let content = HistoryDetailView(detail: detail, history: [record], today: WorkoutCalendar.parseDate("2026-10-21")!,
                                                onBack: {}, jointStressRatings: true, onRateJointStress: { _, _, _ in })
                    .frame(width: width).background(AppColors.background)
                    .environment(\.sizeCategory, size)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: size == .large ? 1100 : 1700))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("history-rating-\(language)-\(Int(width)).png"))
            }
        }
    }

    /// Captures for review under forcedrep-ios/build/body-journal-review/: the ratings card, the Joints tab sample
    /// and the Body overview at 393pt and at 320pt with the largest standard text, in every language.
    @MainActor func testRatingsCardJointsTabAndBodyCardRenderInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/body-journal-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let entries = [BodyEntry(date: "2026-10-12", bodyweightKg: 81.4), BodyEntry(date: "2026-10-19", waistCm: 86)]
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let content = VStack(spacing: 16) {
                    ExerciseRatingsCard(effort: .easy, onEffort: { _ in }, jointStress: .high, onJointStress: { _ in })
                    BodySummaryCard(entries: entries, weightUnit: .kg, onLog: {}, onMeasurements: {})
                    JointJournalView(history: [], weightUnit: .kg, isPreview: true, ratingsEnabled: true, onEnableRatings: {})
                }
                .padding(16).frame(width: width).frame(maxHeight: .infinity, alignment: .top).background(AppColors.background)
                .environment(\.sizeCategory, size)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: size == .large ? 1300 : 1900))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                XCTAssertEqual(image.size.width, width)
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("body-journal-\(language)-\(Int(width)).png"))
            }
        }
    }
    /// Render the real Progress header and Body screen for visual review, including narrow translated labels.
    @MainActor func testProgressHeaderAndBodyScreenRenderInEveryLanguage() throws {
        let previousLanguage = LanguageManager.shared.languagePreference
        let previousTheme = ThemeManager.shared.selectedThemeId
        defer { LanguageManager.setLanguage(previousLanguage); ThemeManager.shared.setThemeId(previousTheme) }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/body-navigation-review").standardized
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        XCTAssertTrue(store.applyBodyEdit(date: BodyDay.today(), stored: BodyEntry(date: BodyDay.today(), bodyweightKg: 80.5, waistCm: 86), hideHealth: false))
        func capture<V: View>(_ view: V, name: String, width: CGFloat, size: ContentSizeCategory) throws {
            let controller = UIHostingController(rootView: view.environment(\.sizeCategory, size))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name + ".png"))
        }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for theme in ["default", "oat"] {
                ThemeManager.shared.setThemeId(theme)
                let suffix = "\(language)-\(theme)"
                try capture(HistoryView(store: store, onOpenSettings: {}, onSelectRecord: { _ in }),
                    name: "progress-\(suffix)-320-large", width: 320, size: .extraExtraExtraLarge)
                try capture(BodyLogView(store: store), name: "body-\(suffix)-320-large", width: 320, size: .extraExtraExtraLarge)
            }
        }
        LanguageManager.setLanguage("en")
        ThemeManager.shared.setThemeId("default")
        for (tab, name) in [(HistoryView.HistoryTab.calendar, "calendar"), (.volumeMatrix, "matrix"), (.formLab, "lab")] {
            try capture(HistoryView(store: store, initialTab: tab, onOpenSettings: {}, onSelectRecord: { _ in }),
                name: "progress-\(name)-393", width: 393, size: .large)
        }
        try capture(BodyLogView(store: store), name: "body-393", width: 393, size: .large)
    }

}
