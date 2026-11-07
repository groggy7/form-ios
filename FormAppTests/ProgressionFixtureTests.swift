import XCTest
@testable import FormApp

/// Executes the shared smart progression contract (gym/docs/progression-fixtures.json).
/// Android ProgressionFixturesTest runs the same file; update it with scripts/sync_progression_fixtures.cjs.
final class ProgressionFixtureTests: XCTestCase {
    private struct Fixtures: Decodable {
        let formatting: [Formatting]
        let progression: [Case]
        let adjustment: [AdjustmentCase]
    }
    /// The mid-workout adjustment (docs/adaptive-training.md#b2-mid-workout-adjustment).
    private struct AdjustmentCase: Decodable {
        struct Row: Decodable {
            let load: Double?
            let reps: Int?
            let done: Bool?
            let warmup: Bool?
            let rir: Int?
        }
        struct Expected: Decodable {
            let direction: String
            let target: [Double]
            let rows: [Int]
            let applied: String
        }
        let name: String
        let unit: String
        let steps: Steps?
        let blockTarget: Int?
        let exercise: FixtureExercise
        let sets: [Row]
        let expected: Expected?
    }
    private struct Formatting: Decodable {
        let value: Double
        let valueUnit: String
        let unit: String
        let display: String
        let exact: String
        let loadable: String
        let barbell: String
    }
    private struct Case: Decodable {
        let name: String
        let unit: String
        let activeSessionId: String?
        let context: Context?
        let steps: Steps?
        let platesKg: [Double]?
        let platesLbs: [Double]?
        let barType: String?
        let exercise: FixtureExercise
        let history: [Record]
        let expected: Expected
    }
    private struct Steps: Decodable {
        let dumbbell: Double?
        let machine: Double?
    }
    private struct Context: Decodable {
        let programId: String
        let workoutId: String
        let now: String
    }
    private struct FixtureExercise: Decodable {
        let exerciseId: String?
        let name: String
        let sets: Int
        let reps: [Int]
        let toFailure: Bool?

        func exercise(id: String) -> Exercise {
            Exercise(id: id, name: name, exerciseId: exerciseId, sets: sets,
                     reps: RepTarget(min: reps[0], max: reps[1], toFailure: toFailure ?? false))
        }
    }
    private struct Record: Decodable {
        let id: String
        let completedAt: String
        let programId: String?
        let workoutId: String?
        let snapshot: [FixtureExercise]?
        let logs: [Log]
    }
    private struct Log: Decodable {
        let exerciseId: String?
        let exerciseName: String
        let targetSets: Int?
        let loadUnit: String?
        let effort: String?
        let warmups: [[Double]]?
        let working: [[Double]]
        /// Each working set's reps in reserve; null leaves a set unrated.
        let rir: [Int?]?
        /// A drop, rest-pause or partials on the working set at a 1-based position.
        let techniques: [Technique]?
    }
    private struct Technique: Decodable {
        let set: Int
        let technique: String?
        let extensions: [[Double]]?
        let partialReps: Int?
    }
    private struct Expected: Decodable {
        let action: String?
        let rationaleKey: String?
        let exerciseId: String?
        let suggestedWeightDisplay: String?
        let weightDeltaDisplay: String?
        let targetUnit: String?
        let targets: [[Double]]?
        let applied: [String]?
        let variation: String?
        let rationaleArgs: [String: String]?
        let techniqueSets: [Int]?
    }

    private func load() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("progression-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    /// A case's load-step settings in its unit, over the app's defaults.
    private func loadSteps(_ settings: Steps?, unit: WeightUnit, platesKg: [Double]? = nil, platesLbs: [Double]? = nil,
                           barType: String? = nil) -> ProgressionLoadSteps {
        let defaults = ProgressionLoadSteps()
        return ProgressionLoadSteps.from(
            dumbbellKg: unit == .kg ? (settings?.dumbbell ?? defaults.dumbbellKg) : defaults.dumbbellKg,
            dumbbellLbs: unit == .lbs ? (settings?.dumbbell ?? defaults.dumbbellLbs) : defaults.dumbbellLbs,
            machineKg: unit == .kg ? (settings?.machine ?? defaults.machineKg) : defaults.machineKg,
            machineLbs: unit == .lbs ? (settings?.machine ?? defaults.machineLbs) : defaults.machineLbs,
            platesKg: platesKg ?? WarmupPlateEngine.defaultPlatesKg,
            platesLbs: platesLbs ?? WarmupPlateEngine.defaultPlatesLbs,
            barType: BarType.fromKey(barType))
    }

    func testEveryAdjustmentCaseMatchesTheSharedContract() throws {
        for fixture in try load().adjustment {
            let name = fixture.name
            let unit = WeightUnit.fromCode(fixture.unit)
            let exercise = fixture.exercise.exercise(id: "fixture-exercise")
            var warmups = 0
            let rows = fixture.sets.enumerated().map { index, row -> ExerciseSetLog in
                let warmup = row.warmup == true
                if warmup { warmups += 1 }
                let kg = row.load.map { unit.toCanonicalKg($0) }
                return ExerciseSetLog(id: "row-\(index)", setNumber: warmup ? warmups : index + 1 - warmups,
                                      weightInput: kg.map { unit.formatExactWeight($0) } ?? "", repsInput: row.reps.map(String.init) ?? "",
                                      weightKg: kg, completedReps: row.reps, isCompleted: row.done == true,
                                      inputTouched: row.load != nil || row.reps != nil ? true : nil, isWarmup: warmup, rir: row.rir)
            }
            let steps = loadSteps(fixture.steps, unit: unit)
            let window = fixture.blockTarget.map { TrainingBlockRules.window(target: $0) } ?? SetEffort.targetWindow
            let offer = ProgressionEngine.loadAdjustment(exercise: exercise, sets: rows, unit: unit, steps: steps, window: window)
            guard let expected = fixture.expected else { XCTAssertNil(offer, name); continue }
            guard let offer else { XCTFail("\(name): no adjustment"); continue }
            XCTAssertEqual(offer.direction.rawValue, expected.direction, "\(name) direction")
            XCTAssertEqual(unit.toDisplay(offer.target.weightKg ?? .nan), expected.target[0], accuracy: 1e-6, "\(name) target load")
            XCTAssertEqual(offer.target.reps, Int(expected.target[1]), "\(name) target reps")
            XCTAssertEqual(offer.rows, expected.rows, "\(name) rows")

            let after = WorkoutSessionUtils.applyingProgressionTargets(offer.targets, to: rows, unit: unit)
            for (index, row) in after.enumerated() {
                if offer.rows.contains(index) {
                    XCTAssertEqual(row.weightInput, expected.applied, "\(name) row \(index) load text")
                    XCTAssertEqual(row.weightKg, offer.target.weightKg, "\(name) row \(index) keeps the canonical target")
                    XCTAssertEqual(row.repsInput, rows[index].repsInput, "\(name) row \(index) keeps typed reps")
                    XCTAssertEqual(row.targetReps, offer.target.reps, "\(name) row \(index) reps hint")
                } else {
                    XCTAssertEqual(row, rows[index], "\(name) row \(index) is untouched")
                }
            }
            XCTAssertNil(ProgressionEngine.loadAdjustment(exercise: exercise, sets: after, unit: unit, steps: steps, window: window),
                         "\(name) offers nothing once used")
        }
    }

    func testFormattingFollowsTheSharedRoundingRule() throws {
        for fixture in try load().formatting {
            let kg = WeightUnit.fromCode(fixture.valueUnit).toCanonicalKg(fixture.value)
            let unit = WeightUnit.fromCode(fixture.unit)
            let label = "\(fixture.value) \(fixture.valueUnit) in \(fixture.unit)"
            XCTAssertEqual(unit.formatWeight(kg), fixture.display, "display \(label)")
            XCTAssertEqual(unit.formatExactWeight(kg), fixture.exact, "exact \(label)")
            XCTAssertEqual(unit.formatLoadableWeight(kg), fixture.loadable, "loadable \(label)")
            XCTAssertEqual(unit.formatLoadableWeight(kg, barbell: true), fixture.barbell, "barbell \(label)")
        }
    }

    func testEveryProgressionCaseMatchesTheSharedContract() throws {
        for fixture in try load().progression {
            let name = fixture.name
            let unit = WeightUnit.fromCode(fixture.unit)
            let exercise = fixture.exercise.exercise(id: "fixture-exercise")
            let context = try fixture.context.map { context in
                ProgressionContext(programId: context.programId, workoutId: context.workoutId,
                                   now: try XCTUnwrap(WorkoutCalendar.parseIsoTimestamp(context.now), name))
            }
            let history = fixture.history.map { record in
                WorkoutSessionRecord(id: record.id, programId: record.programId ?? "fixture", workoutId: record.workoutId ?? "fixture", workoutTitle: "Fixture",
                    startedAt: record.completedAt, completedAt: record.completedAt, durationSeconds: 60,
                    exerciseLogs: record.logs.map { log in
                        let loadUnit = WeightUnit.fromCode(log.loadUnit ?? fixture.unit)
                        func sets(_ pairs: [[Double]]?, warmup: Bool) -> [SessionSetLog] {
                            (pairs ?? []).enumerated().map { index, pair in
                                var set = SessionSetLog(setNumber: index + 1, weightKg: loadUnit.toCanonicalKg(pair[0]), reps: Int(pair[1]), isWarmup: warmup,
                                                        rir: warmup ? nil : log.rir.flatMap { index < $0.count ? $0[index] : nil })
                                if !warmup, let technique = log.techniques?.first(where: { $0.set == index + 1 }) {
                                    set.partialReps = technique.partialReps
                                    set.technique = technique.technique
                                    set.extensions = technique.extensions?.map { SessionSetExtension(weightKg: loadUnit.toCanonicalKg($0[0]), reps: Int($0[1])) }
                                }
                                return set
                            }
                        }
                        return SessionExerciseLog(exerciseName: log.exerciseName,
                            sets: sets(log.warmups, warmup: true) + sets(log.working, warmup: false),
                            targetSets: log.targetSets, exerciseId: log.exerciseId, effort: log.effort)
                    },
                    workoutSnapshot: record.snapshot.map { snapshot in
                        Workout(id: record.workoutId ?? "fixture", day: 1, title: "Fixture",
                                exercises: snapshot.enumerated().map { $1.exercise(id: "snapshot-\($0)") })
                    })
            }
            let expected = fixture.expected
            let steps = loadSteps(fixture.steps, unit: unit, platesKg: fixture.platesKg, platesLbs: fixture.platesLbs, barType: fixture.barType)
            let rec = ProgressionEngine.computeProgression(exercise: exercise, history: history, weightUnit: unit,
                                                           activeSessionId: fixture.activeSessionId, context: context, steps: steps)
            guard let action = expected.action else { XCTAssertNil(rec, name); continue }
            guard let rec else { XCTFail("\(name): no recommendation"); continue }
            XCTAssertEqual(rec.action.rawValue, action, "\(name) action")
            XCTAssertEqual(rec.rationaleKey, expected.rationaleKey, "\(name) rationale")
            if let id = expected.exerciseId { XCTAssertEqual(rec.exerciseId, id, "\(name) exerciseId") }
            if let display = expected.suggestedWeightDisplay { XCTAssertEqual(rec.suggestedWeightDisplay, display, "\(name) suggested") }
            if let delta = expected.weightDeltaDisplay { XCTAssertEqual(rec.weightDeltaDisplay, delta, "\(name) delta") }
            XCTAssertEqual(rec.suggestedVariationId, expected.variation, "\(name) variation")
            if let sets = expected.techniqueSets {
                XCTAssertEqual(rec.lastTechniqueSets.map(\.setNumber), sets, "\(name) last-time sets")
            }
            for (key, value) in expected.rationaleArgs ?? [:] {
                XCTAssertEqual(rec.rationaleArgs[key], value, "\(name) rationale argument \(key)")
            }

            let targetUnit = WeightUnit.fromCode(expected.targetUnit ?? fixture.unit)
            let targets = expected.targets ?? []
            XCTAssertEqual(rec.setTargets.count, targets.count, "\(name) target count")
            for (index, (want, got)) in zip(targets, rec.setTargets).enumerated() {
                XCTAssertEqual(targetUnit.toDisplay(got.weightKg ?? .nan), want[0], accuracy: 1e-6, "\(name) set \(index + 1) load")
                XCTAssertEqual(got.reps, Int(want[1]), "\(name) set \(index + 1) reps")
            }

            guard let applied = expected.applied else { continue }
            let rows = rec.setTargets.indices.map { ExerciseSetLog(setNumber: $0 + 1) }
            let after = WorkoutSessionUtils.applyingProgressionTargets(rec.applicableTargets(sets: rows), to: rows, unit: unit)
            XCTAssertEqual(after.map(\.weightInput), applied, "\(name) applied text")
            for (index, (row, target)) in zip(after, rec.setTargets).enumerated() {
                XCTAssertEqual(row.weightKg, target.weightKg, "\(name) applied set \(index + 1) keeps the canonical target")
                // Apply never records reps: the target is only the empty field's placeholder.
                XCTAssertEqual(row.repsInput, "", "\(name) applied set \(index + 1) leaves reps empty")
                XCTAssertNil(row.completedReps, "\(name) applied set \(index + 1) has no logged reps")
                XCTAssertEqual(row.targetReps, target.reps, "\(name) applied set \(index + 1) reps hint")
                XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(row, allowsZeroWeight: true), "\(name) applied set \(index + 1) cannot be recorded without reps")
            }

            // The user enters actual reps; prefill next must never overwrite applied loads: complete each set in order with it on.
            var entered = after
            for index in entered.indices {
                let reps = rec.setTargets[index].reps
                entered[index].repsInput = "\(reps)"
                entered[index].completedReps = reps
            }
            var current = entered
            for index in entered.indices {
                current = WorkoutSessionUtils.togglingCompletion(of: index, in: current, prefillNextSet: true, unit: unit)
                XCTAssertTrue(current[index].isCompleted, "\(name) set \(index + 1) completes")
                XCTAssertEqual(current.map { row in var row = row; row.isCompleted = false; return row }, entered,
                               "\(name) rows keep their applied loads after completing set \(index + 1)")
                XCTAssertEqual(current[index].weightKg, rec.setTargets[index].weightKg, "\(name) set \(index + 1) keeps its canonical load")
            }
        }
    }
}
