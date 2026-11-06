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
        let ending: [Ending]
        let stats: [Stats]
    }
    private struct Validation: Decodable { let name: String; let exerciseId: String; let set: SessionSetLog; let error: String? }
    private struct Volume: Decodable { let name: String; let set: SessionSetLog; let loadVolumeKg: Double }
    private struct Notation: Decodable { let name: String; let unit: String; let set: SessionSetLog; let text: String }
    private struct Saved: Decodable { let name: String; let exerciseId: String; let draft: ExerciseSetLog; let saved: SessionSetLog }
    private struct Ending: Decodable { let name: String; let sets: [ExerciseSetLog]; let index: Int; let count: Int?; let remaining: [String] }
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

    func testEndingAfterATechnique() {
        for item in fixtures.ending {
            XCTAssertEqual(IntensitySets.endingCount(item.sets, at: item.index), item.count, item.name)
            XCTAssertEqual(IntensitySets.endingExercise(item.sets, at: item.index).map(\.id), item.remaining, item.name)
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

    func testTheRemoveActionNamesThePartItRemoves() {
        XCTAssertNil(IntensitySets.lastRemovablePart(main(1, 100, 6)))
        XCTAssertEqual(IntensitySets.lastRemovablePart(IntensitySets.addingPartials(to: main(1, 100, 6))), .partials)
        var set = IntensitySets.addingPartials(to: dropSet())
        XCTAssertEqual(IntensitySets.lastRemovablePart(set), .partials)
        set = IntensitySets.removingLastPart(set)
        XCTAssertEqual(IntensitySets.lastRemovablePart(set), .drop)
        let restPause = IntensitySets.addingExtension(.restPause, to: main(2, 100, 8), unit: .kg)
        XCTAssertEqual(IntensitySets.lastRemovablePart(restPause), .restPause)
        XCTAssertEqual(SetLoggingTable.removeKey(.restPause), "intensity.removeRestPause")
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

    func testEndHereRemovesUnloggedSetsAndTheCoachReadsTheEndedSession() {
        let set = dropSet()
        let open = [main(2, 100, 8, completed: false), main(3, 100, 8, completed: false)]
        let running = RestTimerState(exerciseName: bench.name, totalSeconds: 120, isRunning: true, endsAtEpochMillis: 161_000, pausedSecondsRemaining: 120, setId: set.id)
        let value = draft([set] + open, rest: running)
        XCTAssertEqual(IntensitySets.endingCount(value.setsByExercise[bench.id]!, at: 0), 1)
        XCTAssertEqual(IntensitySets.endingExercise(in: value, exerciseId: bench.id, at: 1), value, "only where it is offered")

        let ended = IntensitySets.endingExercise(in: value, exerciseId: bench.id, at: 0)
        XCTAssertEqual(ended.setsByExercise[bench.id]?.map(\.id), [set.id])
        XCTAssertNil(ended.restTimer, "no rest follows the workout's last set")
        let progress = SessionProgress.from(draft: ended, nowEpochMillis: 60_000)
        XCTAssertEqual(progress.exerciseLogs.first?.targetSets, 1)
        let record = progress.record(draft: ended, completedAtEpochMillis: 60_000)
        let coach = ProgressionEngine.computeProgression(exercise: bench, history: [record])
        XCTAssertEqual(coach?.rationaleKey, "progression.rationale.ended_with_drop")
        XCTAssertEqual(coach?.setTargets.map(\.weightKg), [100, 100, 100])
        XCTAssertEqual(coach?.lastTechniqueSets.map(\.setNumber), [1])

        // With another exercise still to do, the rest keeps running.
        let row = Exercise(id: "row", name: "Barbell Row", exerciseId: "barbell-row", prescription: "2 × 8–12", sets: 2, reps: RepTarget(min: 8, max: 12))
        var twoExercises = value
        twoExercises.workout = Workout(id: "w", day: 1, title: "Push", exercises: [bench, row])
        twoExercises.setsByExercise[row.id] = [main(1, 60, 8, completed: false)]
        XCTAssertEqual(IntensitySets.endingExercise(in: twoExercises, exerciseId: bench.id, at: 0).restTimer, running)
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

    func testBackupWritesTheCurrentSchemaAndRejectsInvalidTechniques() throws {
        let record = SessionProgress.from(draft: draft([dropSet()]), nowEpochMillis: 2_000).record(draft: draft([dropSet()]), completedAtEpochMillis: 2_000)
        var state = StoredAppState(programs: [], activeProgramId: "", currentWeekKey: "2026-W43", history: [record])
        state.schemaVersion = 4
        let data = try JSONEncoder().encode(FullBackupDocument(state: state, weightUnit: .kg))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, StoredAppState.currentSchemaVersion)
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
                                       onToggleExtension: { _, _ in }, onAddPartials: { _ in }, onUpdatePartials: { _, _, _ in }, onRemoveLastPart: { _ in },
                                       onEndExercise: { _ in })
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/intensity-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                let table = SetLoggingTable(sets: [drop, restPause, open], prescription: "3 × 8–12", isRestActive: true, isRestForCurrentExercise: true,
                                            previousSets: previousSets, onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in }, onAddSet: {}, onRemoveSet: { _ in },
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

/// Reps in reserve per working set (docs/adaptive-training.md#phase-a-effort-logging-free).
final class SetEffortTests: XCTestCase {
    private var previousLanguage: String!
    private let bench = Exercise(id: "bench", name: "Bench Press", exerciseId: "barbell-bench-press", sets: 3)

    override func setUp() {
        super.setUp()
        previousLanguage = LanguageManager.shared.languagePreference
        LanguageManager.setLanguage("en")
    }

    override func tearDown() {
        LanguageManager.setLanguage(previousLanguage)
        super.tearDown()
    }

    func testScalesShareOneStoredValue() {
        XCTAssertEqual(SetEffort.values, [0, 1, 2, 3, 4])
        XCTAssertEqual(SetEffort.values.map { SetEffort.chipLabel($0, scale: .rir) }, ["0", "1", "2", "3", "4+"])
        XCTAssertEqual(SetEffort.values.map { SetEffort.chipLabel($0, scale: .rpe) }, ["10", "9", "8", "7", "≤6"])
        XCTAssertEqual(SetEffort.tag(2, scale: .rir), "RIR 2")
        XCTAssertEqual(SetEffort.tag(4, scale: .rpe), "RPE ≤6")
        XCTAssertEqual(SetEffort.spokenLabel(1, scale: .rir), "1 rep in reserve")
        XCTAssertEqual(SetEffort.spokenLabel(0, scale: .rir), "0 reps in reserve")
        XCTAssertEqual(SetEffort.spokenLabel(4, scale: .rir), "4 or more reps in reserve")
        XCTAssertEqual(SetEffort.spokenLabel(2, scale: .rpe), "RPE 8")
        XCTAssertEqual(SetEffort.spokenLabel(4, scale: .rpe), "RPE 6 or lower")
    }

    func testRpeRoundsTowardTheHarderSide() {
        let cases: [(Double?, Int?)] = [(10, 0), (9.5, 0), (9, 1), (8.5, 1), (8, 2), (7, 3), (6.5, 3), (6, 4), (5, 4), (1, 4),
                                        (0, nil), (nil, nil), (10.5, nil), (-1, nil), (.nan, nil), (.infinity, nil)]
        for (rpe, rir) in cases {
            XCTAssertEqual(SetEffort.rir(fromRpe: rpe), rir, "RPE \(String(describing: rpe))")
        }
    }

    func testOnlyCompletedWorkingSetsCarryEffort() {
        let done = ExerciseSetLog(setNumber: 1, weightInput: "100", repsInput: "8", weightKg: 100, completedReps: 8, isCompleted: true)
        XCTAssertTrue(SetEffort.canRate(done))
        XCTAssertFalse(SetEffort.canRate(ExerciseSetLog(setNumber: 1)))
        XCTAssertFalse(SetEffort.canRate(ExerciseSetLog(setNumber: 1, isCompleted: true, isWarmup: true)))
        XCTAssertEqual(SetEffort.rating(done, rir: 2).rir, 2)
        XCTAssertNil(SetEffort.rating(done, rir: 7).rir)
        XCTAssertNil(SetEffort.rating(SetEffort.rating(done, rir: 2), rir: nil).rir)
        var warmup = done
        warmup.isWarmup = true
        XCTAssertNil(SetEffort.rating(warmup, rir: 2).rir)
    }

    private func draft(_ sets: [ExerciseSetLog]) -> ActiveSessionDraft {
        ActiveSessionDraft(programId: "p", workout: Workout(id: "w", day: 1, title: "Push", exercises: [bench]),
                           startedAt: "2026-11-06T10:00:00Z", startedAtEpochMillis: 1_000, setsByExercise: [bench.id: sets])
    }

    private func completed(_ number: Int, rir: Int?, warmup: Bool = false) -> ExerciseSetLog {
        ExerciseSetLog(setNumber: number, weightInput: "100", repsInput: "8", weightKg: 100, completedReps: 8,
                       isCompleted: true, isWarmup: warmup, rir: rir)
    }

    func testEffortIsSavedResumedAndClearedOnWarmups() throws {
        var open = completed(3, rir: 1)
        open.isCompleted = false
        let sets = [completed(1, rir: 2), completed(2, rir: nil), open]
        let record = SessionProgress.from(draft: draft(sets), nowEpochMillis: 2_000).record(draft: draft(sets), completedAtEpochMillis: 2_000)
        XCTAssertEqual(record.exerciseLogs[0].sets.map(\.rir), [2, nil], "an unticked set is not saved")
        let restored = try XCTUnwrap(WorkoutSessionUtils.restoreSetsFromHistory(workout: draft([]).workout, record: record)[bench.id])
        XCTAssertEqual(restored.map(\.rir), [2, nil, nil])

        let reindexed = AppStore.reindexSets([completed(1, rir: 3), completed(2, rir: 1)])
        XCTAssertEqual(reindexed.map(\.rir), [3, 1], "renumbering keeps effort")
        var toWarmup = [completed(1, rir: 3), completed(2, rir: 1)]
        toWarmup[0].isWarmup = true
        XCTAssertEqual(AppStore.reindexSets(toWarmup).map(\.rir), [nil, 1], "a set turned into a warmup loses its effort")
        XCTAssertNil(IntensitySets.clearingIntensity(completed(1, rir: 3)).rir)

        let toggled = WorkoutSessionUtils.togglingCompletion(of: 0, in: [completed(1, rir: 2)], prefillNextSet: true, unit: .kg)
        XCTAssertEqual(toggled[0].rir, 2, "undoing a tick keeps the value, as reps are kept")
    }

    func testDraftDecodingDropsAValueTheLoggerNeverWrites() throws {
        let json = #"{"id":"a","setNumber":1,"isCompleted":true,"rir":9}"#
        XCTAssertNil(try JSONDecoder().decode(ExerciseSetLog.self, from: Data(json.utf8)).rir)
        let valid = #"{"id":"a","setNumber":1,"isCompleted":true,"rir":0}"#
        XCTAssertEqual(try JSONDecoder().decode(ExerciseSetLog.self, from: Data(valid.utf8)).rir, 0)
    }

    func testBackupCarriesEffortAndRejectsValuesTheLoggerNeverWrites() throws {
        let sets = [completed(1, rir: 2), completed(2, rir: nil)]
        let record = SessionProgress.from(draft: draft(sets), nowEpochMillis: 2_000).record(draft: draft(sets), completedAtEpochMillis: 2_000)
        let state = StoredAppState(programs: [], activeProgramId: "", currentWeekKey: "2026-W45", history: [record])
        let data = try JSONEncoder().encode(FullBackupDocument(state: state, weightUnit: .kg))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 7)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "\"rir\"").count - 1, 1, "an unrated set writes no field")
        let restored = try JSONDecoder().decode(FullBackupDocument.self, from: data)
        XCTAssertEqual(restored.state.history[0].exerciseLogs[0].sets.map(\.rir), [2, nil])

        for bad in ["\"rir\":5", "\"rir\":-1"] {
            let broken = text.replacingOccurrences(of: "\"rir\":2", with: bad)
            XCTAssertNotEqual(broken, text)
            XCTAssertThrowsError(try JSONDecoder().decode(FullBackupDocument.self, from: Data(broken.utf8)), bad)
        }
        var warmupRecord = record
        warmupRecord.exerciseLogs[0].sets[0].isWarmup = true
        let warmupData = try JSONEncoder().encode(FullBackupDocument(state: StoredAppState(programs: [], activeProgramId: "",
            currentWeekKey: "2026-W45", history: [warmupRecord]), weightUnit: .kg))
        XCTAssertThrowsError(try JSONDecoder().decode(FullBackupDocument.self, from: warmupData), "effort on a warmup")
    }

    func testHistoryShowsSavedEffortOnTheChosenScale() {
        let sets = [SessionSetLog(setNumber: 1, weightKg: 100, reps: 8, isWarmup: true, rir: nil),
                    SessionSetLog(setNumber: 1, weightKg: 100, reps: 8, rir: 2),
                    SessionSetLog(setNumber: 2, weightKg: 100, reps: 8),
                    SessionSetLog(setNumber: 3, weightKg: 100, reps: 7, rir: 0)]
        XCTAssertEqual(SetEffort.summary(sets, scale: .rir), "RIR 2 · – · 0")
        XCTAssertEqual(SetEffort.summary(sets, scale: .rpe), "RPE 8 · – · 10")
        XCTAssertNil(SetEffort.summary([SessionSetLog(setNumber: 1, weightKg: 100, reps: 8)], scale: .rir))
        XCTAssertEqual(SetEffort.tag(of: sets[1], scale: .rir), "RIR 2")
        XCTAssertNil(SetEffort.tag(of: sets[2], scale: .rir))
    }
}

final class EffortTableRenderTests: XCTestCase {
    /// The effort line at the session card's real width: 38 pt of card padding each side leaves 244 pt at 320 pt.
    @MainActor func testEffortLineRendersAtNarrowWidthAndLargeTextInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        func set(_ number: Int, rir: Int?, completed: Bool) -> ExerciseSetLog {
            ExerciseSetLog(id: "set-\(number)", setNumber: number, weightInput: completed ? "100" : "", repsInput: completed ? "8" : "",
                           weightKg: completed ? 100 : nil, completedReps: completed ? 8 : nil, isCompleted: completed, inputTouched: completed, rir: rir)
        }
        let sets = [set(1, rir: 2, completed: true), set(2, rir: 1, completed: true), set(3, rir: nil, completed: false)]
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/effort-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for scale in SetEffort.Scale.allCases {
                for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                    let table = SetLoggingTable(sets: sets, prescription: "3 × 8–12", onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in },
                                                onAddSet: {}, onRemoveSet: { _ in }, weightUnit: .kg,
                                                effort: EffortActions(scale: scale) { _, _ in })
                        .padding(.horizontal, 38).padding(.vertical, 16)
                        .frame(width: width).frame(maxHeight: .infinity, alignment: .top).background(AppColors.background)
                        .environment(\.sizeCategory, size)
                    let controller = UIHostingController(rootView: table)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: size == .large ? 700 : 1000))
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
                    try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("effort-\(language)-\(scale.rawValue)-\(Int(width)).png"))
                }
            }
        }
    }
}

/// The mid-workout load adjustment under the first working set (docs/adaptive-training.md#b2-mid-workout-adjustment).
final class LoadAdjustmentRenderTests: XCTestCase {
    private let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 3,
                                 reps: RepTarget(min: 8, max: 12))

    private func rows(reps: Int, rir: Int) -> [ExerciseSetLog] {
        [ExerciseSetLog(id: "set-1", setNumber: 1, weightInput: "100", repsInput: "\(reps)", weightKg: 100, completedReps: reps,
                        isCompleted: true, inputTouched: true, rir: rir),
         ExerciseSetLog(id: "set-2", setNumber: 2, weightInput: "100", repsInput: "\(reps)", weightKg: 100, completedReps: reps, inputTouched: true),
         ExerciseSetLog(id: "set-3", setNumber: 3)]
    }

    func testTheCardReadsTheOfferOnTheChosenScale() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")
        let easier = try XCTUnwrap(ProgressionEngine.loadAdjustment(exercise: bench, sets: rows(reps: 12, rir: 4), unit: .kg))
        XCTAssertEqual(easier.setIndex, 0)
        XCTAssertEqual(LanguageManager.t(easier.direction.titleKey, ["set": easier.setNumber, "effort": SetEffort.tag(easier.rir, scale: .rir)]),
                       "Set 1 felt easier than planned (RIR 4+)")
        let harder = try XCTUnwrap(ProgressionEngine.loadAdjustment(exercise: bench, sets: rows(reps: 6, rir: 0), unit: .kg))
        XCTAssertEqual(LanguageManager.t(harder.direction.titleKey, ["set": harder.setNumber, "effort": SetEffort.tag(harder.rir, scale: .rpe)]),
                       "Set 1 was harder than planned (RPE 10)")
        XCTAssertEqual(harder.target, ProgressionSetTarget(weightKg: 97.5, reps: 8))
        // Use writes loads only; afterwards nothing is offered.
        let used = WorkoutSessionUtils.applyingProgressionTargets(easier.targets, to: rows(reps: 12, rir: 4), unit: .kg)
        XCTAssertEqual(used.map(\.weightInput), ["100", "102.5", "102.5"])
        XCTAssertEqual(used.map(\.repsInput), ["12", "12", ""])
        XCTAssertNil(ProgressionEngine.loadAdjustment(exercise: bench, sets: used, unit: .kg))
    }

    /// The card at the session card's real width: 38 pt of card padding each side leaves 244 pt at 320 pt.
    @MainActor func testTheCardRendersAtNarrowWidthAndLargeTextInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/adjustment-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (name, sets, scale) in [("easier", rows(reps: 12, rir: 4), SetEffort.Scale.rir), ("harder", rows(reps: 6, rir: 0), .rpe)] {
                let offer = try XCTUnwrap(ProgressionEngine.loadAdjustment(exercise: bench, sets: sets, unit: .kg), "\(language) \(name)")
                for (width, size) in [(CGFloat(393), ContentSizeCategory.large), (320, .extraExtraExtraLarge)] {
                    let table = SetLoggingTable(sets: sets, prescription: "3 × 8–12", onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in },
                                                onAddSet: {}, onRemoveSet: { _ in }, weightUnit: .kg,
                                                effort: EffortActions(scale: scale) { _, _ in },
                                                adjustment: AdjustmentSlot(afterIndex: offer.setIndex, content: AnyView(LoadAdjustmentCard(
                                                    adjustment: offer, scale: scale, weightUnit: .kg, onUse: {}, onKeep: {}))))
                        .padding(.horizontal, 38).padding(.vertical, 16)
                        .frame(width: width).frame(maxHeight: .infinity, alignment: .top).background(AppColors.background)
                        .environment(\.sizeCategory, size)
                    let controller = UIHostingController(rootView: table)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: size == .large ? 900 : 1400))
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
                    try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("adjustment-\(name)-\(language)-\(Int(width)).png"))
                }
            }
        }
    }
}
