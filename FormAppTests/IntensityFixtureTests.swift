import XCTest
import SwiftUI
@testable import FormApp

/// Executes the shared intensity-set contract (gym/docs/intensity-fixtures.json).
/// Android IntensityFixturesTest runs the same file; update it with scripts/sync_intensity_fixtures.cjs.
final class IntensityFixtureTests: XCTestCase {
    private struct Fixtures: Decodable {
        let validation: [Validation]
        let volume: [Volume]
        let notation: [Notation]
        let saved: [Saved]
        let stats: [Stats]
    }
    private struct Validation: Decodable { let name: String; let exerciseId: String; let set: SessionSetLog; let error: String? }
    private struct Volume: Decodable { let name: String; let set: SessionSetLog; let loadVolumeKg: Double }
    private struct Notation: Decodable { let name: String; let unit: String; let set: SessionSetLog; let text: String }
    private struct Saved: Decodable { let name: String; let exerciseId: String; let draft: ExerciseSetLog; let saved: SessionSetLog }
    private struct Stats: Decodable {
        struct Expected: Decodable {
            let prWeightKg: Double; let prReps: Int; let estimated1rmKg: Double; let totalVolumeKg: Double; let lifetimeSets: Int
        }
        let name: String; let exerciseName: String; let exerciseId: String; let sets: [SessionSetLog]; let expected: Expected
    }

    private var fixtures: Fixtures!
    private var previousLanguage: String!

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("intensity-fixtures.json")
        fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        previousLanguage = LanguageManager.shared.languagePreference
        LanguageManager.setLanguage("en")
    }

    override func tearDown() {
        LanguageManager.setLanguage(previousLanguage)
        super.tearDown()
    }

    private func exercise(_ id: String) -> Exercise {
        Exercise(name: ExerciseCatalog.canonicalExercises[id]?.name ?? id, exerciseId: id)
    }

    func testValidation() {
        for item in fixtures.validation {
            let assisted = WorkoutSessionUtils.isAssisted(exercise(item.exerciseId))
            XCTAssertEqual(IntensitySets.restoreError(item.set, assisted: assisted), item.error, item.name)
        }
    }

    func testLoadVolume() {
        for item in fixtures.volume {
            XCTAssertEqual(IntensitySets.loadVolume(item.set), item.loadVolumeKg, accuracy: 1e-9, item.name)
        }
    }

    func testNotation() {
        for item in fixtures.notation {
            XCTAssertEqual(IntensitySets.notation(item.set, unit: WeightUnit.fromCode(item.unit)), item.text, item.name)
        }
    }

    func testSavedSets() {
        for item in fixtures.saved {
            let saved = IntensitySets.savedSet(item.draft, exercise: exercise(item.exerciseId), unit: .kg)
            XCTAssertEqual(saved, item.saved, item.name)
        }
    }

    func testExerciseStats() {
        for item in fixtures.stats {
            let record = WorkoutSessionRecord(
                id: "fixture", programId: "p", workoutId: "w", workoutTitle: "Fixture",
                startedAt: "2026-10-01T10:00:00Z", completedAt: "2026-10-01T11:00:00Z", durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(exerciseName: item.exerciseName, sets: item.sets, exerciseId: item.exerciseId)]
            )
            let stats = PersonalRecordTracker.computeExerciseHistoryStats(history: [record], exerciseName: item.exerciseName)
            XCTAssertEqual(stats.prWeightKg ?? -1, item.expected.prWeightKg, accuracy: 1e-9, item.name)
            XCTAssertEqual(stats.prReps, item.expected.prReps, item.name)
            XCTAssertEqual(stats.estimated1rmKg ?? -1, item.expected.estimated1rmKg, accuracy: 1e-6, item.name)
            XCTAssertEqual(stats.totalVolumeKg, item.expected.totalVolumeKg, accuracy: 1e-9, item.name)
            XCTAssertEqual(stats.lifetimeSets, item.expected.lifetimeSets, item.name)
        }
    }
}

/// iOS behavior around drop sets, rest-pause and partials that the shared fixtures do not cover.
final class IntensitySetsBehaviorTests: XCTestCase {
    private let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3 × 8–12",
                                 sets: 3, reps: RepTarget(min: 8, max: 12))

    private func draft(_ sets: [ExerciseSetLog], rest: RestTimerState? = nil) -> ActiveSessionDraft {
        ActiveSessionDraft(programId: "p", workout: Workout(id: "w", day: 1, title: "Push", exercises: [bench]),
                           startedAt: "2026-10-20T10:00:00Z", startedAtEpochMillis: 1_000, setsByExercise: [bench.id: sets],
                           restTimer: rest, weightInputUnit: .kg)
    }

    private func main(_ number: Int, _ weight: Double, _ reps: Int, completed: Bool = true) -> ExerciseSetLog {
        ExerciseSetLog(setNumber: number, weightInput: WorkoutSessionUtils.formatWeightInput(weight), repsInput: "\(reps)",
                       weightKg: weight, completedReps: reps, isCompleted: completed, inputTouched: true)
    }

    private func dropSet() -> ExerciseSetLog {
        var set = IntensitySets.addingExtension(.drop, to: main(1, 100, 6), unit: .kg)
        set = IntensitySets.editingExtension(set, at: 0, weight: "70", reps: "5", exercise: bench, unit: .kg)
        return IntensitySets.togglingExtension(set, at: 0, exercise: bench, unit: .kg)
    }

    func testSavedSessionCountsOneSetAndAddsDropVolume() {
        let progress = SessionProgress.from(draft: draft([dropSet(), main(2, 100, 8)]), nowEpochMillis: 2_000)
        XCTAssertEqual(progress.completedSets, 2)
        XCTAssertEqual(progress.volumeKg, 100 * 6 + 70 * 5 + 100 * 8, accuracy: 1e-9)
        let saved = progress.exerciseLogs[0].sets[0]
        XCTAssertEqual(saved.technique, "drop")
        XCTAssertEqual(saved.setExtensions, [SessionSetExtension(weightKg: 70, reps: 5)])
    }

    func testDropMustBeLighterAndAssistedDropsAddAssistance() {
        var set = IntensitySets.addingExtension(.drop, to: main(1, 100, 6), unit: .kg)
        set = IntensitySets.editingExtension(set, at: 0, weight: "100", reps: "5", exercise: bench, unit: .kg)
        XCTAssertEqual(IntensitySets.extensionValidationError(set, at: 0, exercise: bench, unit: .kg), "intensity.validation.dropLighter")
        XCTAssertFalse(IntensitySets.togglingExtension(set, at: 0, exercise: bench, unit: .kg).extensions![0].isCompleted)
        let assisted = Exercise(name: "Assisted Pull-up", exerciseId: "assisted-pull-up")
        var help = IntensitySets.addingExtension(.drop, to: main(1, 20, 6), unit: .kg)
        help = IntensitySets.editingExtension(help, at: 0, weight: "10", reps: "4", exercise: assisted, unit: .kg)
        XCTAssertEqual(IntensitySets.extensionValidationError(help, at: 0, exercise: assisted, unit: .kg), "intensity.validation.dropAssistance")
        help = IntensitySets.editingExtension(help, at: 0, weight: "30", reps: "4", exercise: assisted, unit: .kg)
        XCTAssertNil(IntensitySets.extensionValidationError(help, at: 0, exercise: assisted, unit: .kg))
    }

    func testOneTechniquePerSetAndSixExtensionsAtMost() {
        var set = IntensitySets.addingExtension(.restPause, to: main(1, 100, 8), unit: .kg)
        XCTAssertFalse(IntensitySets.canAdd(.drop, to: set))
        for _ in 0..<10 { set = IntensitySets.addingExtension(.restPause, to: set, unit: .kg) }
        XCTAssertEqual(set.extensions?.count, IntensitySets.maxExtensions)
        XCTAssertFalse(IntensitySets.canAdd(.restPause, to: ExerciseSetLog(setNumber: 1, isWarmup: true)))
    }

    func testRemoveLastPartRemovesPartialsBeforeTheExtension() {
        var set = IntensitySets.addingPartials(to: dropSet())
        XCTAssertEqual(set.extensions?.last?.partialRepsInput, "")
        XCTAssertFalse(IntensitySets.canAddPartials(to: set))
        set = IntensitySets.removingLastPart(set)
        XCTAssertNil(set.extensions?.last?.partialRepsInput)
        set = IntensitySets.removingLastPart(set)
        XCTAssertNil(set.extensions)
        XCTAssertNil(set.technique)
    }

    func testUndoingOrInvalidatingTheSetUnticksItsExtensions() {
        let undone = WorkoutSessionUtils.togglingCompletion(of: 0, in: [dropSet()], prefillNextSet: false, unit: .kg)
        XCTAssertFalse(undone[0].isCompleted)
        XCTAssertFalse(undone[0].extensions![0].isCompleted)
        // A heavier drop than a lowered main load is no longer valid.
        let lowered = WorkoutSessionUtils.editedSet(dropSet(), weight: "60", reps: "6", exercise: bench, unit: .kg)
        XCTAssertTrue(lowered.isCompleted)
        XCTAssertFalse(lowered.extensions![0].isCompleted)
    }

    func testRestRestartsOnlyForTheSetThatStartedIt() {
        let set = dropSet()
        let running = RestTimerState(exerciseName: bench.name, totalSeconds: 180, isRunning: true, endsAtEpochMillis: 61_000, pausedSecondsRemaining: 180, setId: set.id)
        let restarted = IntensitySets.restAfterTickingExtension(in: draft([set, main(2, 100, 8, completed: false)], rest: running), setId: set.id, exercise: bench, nowEpochMillis: 50_000)
        XCTAssertEqual(restarted?.endsAtEpochMillis, 50_000 + Int64(RestTimerUtils.restSeconds(for: bench)) * 1000)
        XCTAssertEqual(restarted?.setId, set.id)
        let other = IntensitySets.restAfterTickingExtension(in: draft([set], rest: running), setId: "another", exercise: bench, nowEpochMillis: 50_000)
        XCTAssertEqual(other, running)
        var paused = running; paused.isRunning = false
        XCTAssertEqual(IntensitySets.restAfterTickingExtension(in: draft([set], rest: paused), setId: set.id, exercise: bench, nowEpochMillis: 50_000), paused)
    }

    func testWarmupConversionDropsTechniqueAndReindexKeepsIt() {
        let working = AppStore.reindexSets([main(1, 60, 10), dropSet()])
        XCTAssertEqual(working[1].technique, "drop")
        var warm = dropSet(); warm.isWarmup = true
        let converted = AppStore.reindexSets([warm])
        XCTAssertNil(converted[0].technique)
        XCTAssertNil(converted[0].extensions)
    }

    func testResumeAndUnitSwitchKeepDrops() {
        let progress = SessionProgress.from(draft: draft([dropSet()]), nowEpochMillis: 2_000)
        let record = progress.record(draft: draft([dropSet()]), completedAtEpochMillis: 2_000)
        let restored = WorkoutSessionUtils.restoreSetsFromHistory(workout: draft([]).workout, record: record)[bench.id]!
        XCTAssertEqual(restored[0].extensions?.first?.weightKg, 70)
        XCTAssertEqual(restored[0].extensions?.first?.isCompleted, true)
        let pounds = WorkoutSessionUtils.rebaseWeightInputs(draft([dropSet()]), from: .kg, to: .lbs)
        XCTAssertEqual(pounds.setsByExercise[bench.id]?[0].extensions?[0].weightKg, 70, "a ticked drop keeps the load it was lifted at")
        XCTAssertEqual(pounds.setsByExercise[bench.id]?[0].extensions?[0].weightInput, WorkoutSessionUtils.formatWeightInput(70, unit: .lbs, barbell: true))
    }

    func testBackupWritesSchemaFiveAndRejectsInvalidTechniques() throws {
        let record = SessionProgress.from(draft: draft([dropSet()]), nowEpochMillis: 2_000).record(draft: draft([dropSet()]), completedAtEpochMillis: 2_000)
        var state = StoredAppState(programs: [], activeProgramId: "", currentWeekKey: "2026-W43", history: [record])
        state.schemaVersion = 4
        let data = try JSONEncoder().encode(FullBackupDocument(state: state, weightUnit: .kg))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 5)
        let restored = try JSONDecoder().decode(FullBackupDocument.self, from: data)
        XCTAssertEqual(restored.state.history[0].exerciseLogs[0].sets[0].setExtensions.first?.weightKg, 70)

        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"drop\"", with: "\"cluster\"")
        XCTAssertThrowsError(try JSONDecoder().decode(FullBackupDocument.self, from: Data(text.utf8)))
    }

    func testProgressionIgnoresExtensionsAndShowsThemAsContext() throws {
        func record(_ id: String, _ date: String, _ sets: [SessionSetLog]) -> WorkoutSessionRecord {
            WorkoutSessionRecord(id: id, programId: "p", workoutId: "w", workoutTitle: "Push", startedAt: date, completedAt: date,
                                 durationSeconds: 3600, exerciseLogs: [SessionExerciseLog(exerciseName: bench.name, sets: sets, exerciseId: "barbell-bench-press")])
        }
        let plain = (1...3).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 9) }
        var dropped = plain
        dropped[2].technique = "drop"; dropped[2].extensions = [SessionSetExtension(weightKg: 60, reps: 6)]
        let now = ISO8601DateFormatter().string(from: Date())
        let withoutDrop = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bench, history: [record("a", now, plain)]))
        let withDrop = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bench, history: [record("a", now, dropped)]))
        XCTAssertEqual(withDrop.setTargets, withoutDrop.setTargets)
        XCTAssertEqual(withDrop.action, withoutDrop.action)
        XCTAssertEqual(withDrop.lastTechniqueSets.map(\.setNumber), [3])
        XCTAssertTrue(withoutDrop.lastTechniqueSets.isEmpty)
    }

    func testVolumeMatrixCountsADropSetOnceAndReportsIt() throws {
        let catalog = try XCTUnwrap(ExerciseMuscleCatalog.shared)
        var sets = (1...3).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 9) }
        sets[2].technique = "drop"; sets[2].extensions = [SessionSetExtension(weightKg: 60, reps: 6), SessionSetExtension(weightKg: 40, reps: 6)]
        let session = WorkoutSessionRecord(id: "s", programId: "p", workoutId: "w", workoutTitle: "Push",
                                           startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 600,
                                           exerciseLogs: [SessionExerciseLog(exerciseName: bench.name, sets: sets, exerciseId: "barbell-bench-press")])
        let report = VolumeMatrixEngine.computeLoggedVolume(targetWeekKey: "2026-W38", history: [session], catalog: catalog)
        XCTAssertEqual(report.totalWorkingSets, 3)
        XCTAssertEqual(report.techniqueSets, 1)
        XCTAssertEqual(report.muscleSummaries["chest"]?.directSets, 3)
        XCTAssertEqual(report.muscleSummaries["chest"]?.contributions.first?.techniqueSets, 1)
    }
}

/// Renders the session table with drop, rest-pause and partials rows for visual review
/// (forcedrep-ios/build/intensity-review/), at 393 and 320 points, large text, in all five languages.
final class IntensityTableRenderTests: XCTestCase {
    @MainActor func testTechniqueRowsRenderAtNarrowWidthAndLargeTextInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3 × 8–12", sets: 3,
                             reps: RepTarget(min: 8, max: 12))
        func main(_ number: Int, _ weight: Double, _ reps: Int, completed: Bool) -> ExerciseSetLog {
            ExerciseSetLog(id: "set-\(number)", setNumber: number, weightInput: WorkoutSessionUtils.formatWeightInput(weight), repsInput: "\(reps)",
                           weightKg: weight, completedReps: reps, isCompleted: completed, inputTouched: true)
        }
        var drop = IntensitySets.addingExtension(.drop, to: main(1, 100, 6, completed: true), unit: .kg)
        drop = IntensitySets.editingExtension(drop, at: 0, weight: "70", reps: "5", exercise: bench, unit: .kg)
        drop = IntensitySets.togglingExtension(drop, at: 0, exercise: bench, unit: .kg)
        drop = IntensitySets.addingExtension(.drop, to: drop, unit: .kg)
        drop = IntensitySets.editingExtension(drop, at: 1, weight: "50", reps: "", exercise: bench, unit: .kg)
        var restPause = IntensitySets.addingExtension(.restPause, to: main(2, 100, 8, completed: true), unit: .kg)
        restPause = IntensitySets.editingExtension(restPause, at: 0, weight: "", reps: "3", exercise: bench, unit: .kg)
        restPause = IntensitySets.togglingExtension(restPause, at: 0, exercise: bench, unit: .kg)
        restPause = IntensitySets.addingPartials(to: restPause)
        restPause = IntensitySets.editingPartials(restPause, extensionIndex: 0, input: "2")
        let open = ExerciseSetLog(id: "set-3", setNumber: 3)
        let previousSets: [Int: SessionSetLog] = [0: SessionSetLog(setNumber: 1, weightKg: 100, reps: 6, technique: "drop",
                                                                  extensions: [SessionSetExtension(weightKg: 70, reps: 4)])]
        let actions = IntensityActions(exercise: bench, previousSets: previousSets, onAddExtension: { _, _ in }, onUpdateExtension: { _, _, _, _ in },
                                       onToggleExtension: { _, _ in }, onAddPartials: { _ in }, onUpdatePartials: { _, _, _ in }, onRemoveLastPart: { _ in })
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/intensity-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let table = SetLoggingTable(sets: [drop, restPause, open], prescription: "3 × 8–12", isRestActive: true, isRestForCurrentExercise: true,
                                            prText: "100x8", onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in }, onAddSet: {}, onRemoveSet: { _ in },
                                            weightUnit: .kg, intensity: actions)
                    .padding(16).frame(width: width).frame(maxHeight: .infinity, alignment: .top).background(AppColors.background)
                    .environment(\.sizeCategory, size)
                let controller = UIHostingController(rootView: table)
                let height: CGFloat = size == .large ? 1150 : 1700
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
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
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("table-\(language)-\(Int(width)).png"))
            }
        }
    }
}
