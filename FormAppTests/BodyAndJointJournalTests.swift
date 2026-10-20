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

    func testRelativeStrengthExcludesBodyweightAndNeedsARecentWeighIn() {
        let today = date(40)
        let history = [record("1", date(35), [
            log("Barbell Back Squat", "barbell-back-squat", nil, [SessionSetLog(setNumber: 1, weightKg: 140, reps: 1)]),
            log("Weighted Pull-Ups", "weighted-pull-ups", nil, [SessionSetLog(setNumber: 1, weightKg: 40, reps: 1)]),
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
        XCTAssertEqual(json["schemaVersion"] as? Int, 6)
        XCTAssertEqual((json["bodyEntries"] as? [Any])?.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(FullBackupDocument.self, from: data).state.bodyEntries, entries)
        // Older backups carry no body log; newer schemas are refused rather than silently dropped.
        let old = #"{"schemaVersion":5,"programs":[],"activeProgramId":"","completed":[],"currentWeekKey":"2026-W43","weeklyArchives":[],"history":[]}"#
        XCTAssertNil(try JSONDecoder().decode(FullBackupDocument.self, from: Data(old.utf8)).state.bodyEntries)
        let newer = old.replacingOccurrences(of: "\"schemaVersion\":5", with: "\"schemaVersion\":7")
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

    /// Captures for review under forcedrep-ios/build/body-journal-review/: the ratings card, the Joints tab sample
    /// and the Progress card at 393pt and at 320pt with the largest standard text, in every language.
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
                    BodySummaryCard(entries: entries, weightUnit: .kg, onOpen: {})
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
}
