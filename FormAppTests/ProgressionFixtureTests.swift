import XCTest
@testable import FormApp

/// Executes the shared smart progression contract (gym/docs/progression-fixtures.json).
/// Android ProgressionFixturesTest runs the same file; update it with scripts/sync_progression_fixtures.cjs.
final class ProgressionFixtureTests: XCTestCase {
    private struct Fixtures: Decodable {
        let formatting: [Formatting]
        let progression: [Case]
    }
    private struct Formatting: Decodable {
        let value: Double
        let valueUnit: String
        let unit: String
        let display: String
        let exact: String
    }
    private struct Case: Decodable {
        let name: String
        let unit: String
        let activeSessionId: String?
        let context: Context?
        let exercise: FixtureExercise
        let history: [Record]
        let expected: Expected
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
        let warmups: [[Double]]?
        let working: [[Double]]
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
    }

    private func load() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("progression-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    func testFormattingFollowsTheSharedRoundingRule() throws {
        for fixture in try load().formatting {
            let kg = WeightUnit.fromCode(fixture.valueUnit).toCanonicalKg(fixture.value)
            let unit = WeightUnit.fromCode(fixture.unit)
            let label = "\(fixture.value) \(fixture.valueUnit) in \(fixture.unit)"
            XCTAssertEqual(unit.formatWeight(kg), fixture.display, "display \(label)")
            XCTAssertEqual(unit.formatExactWeight(kg), fixture.exact, "exact \(label)")
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
                                SessionSetLog(setNumber: index + 1, weightKg: loadUnit.toCanonicalKg(pair[0]), reps: Int(pair[1]), isWarmup: warmup)
                            }
                        }
                        return SessionExerciseLog(exerciseName: log.exerciseName,
                            sets: sets(log.warmups, warmup: true) + sets(log.working, warmup: false),
                            targetSets: log.targetSets, exerciseId: log.exerciseId)
                    },
                    workoutSnapshot: record.snapshot.map { snapshot in
                        Workout(id: record.workoutId ?? "fixture", day: 1, title: "Fixture",
                                exercises: snapshot.enumerated().map { $1.exercise(id: "snapshot-\($0)") })
                    })
            }
            let expected = fixture.expected
            let rec = ProgressionEngine.computeProgression(exercise: exercise, history: history, weightUnit: unit,
                                                           activeSessionId: fixture.activeSessionId, context: context)
            guard let action = expected.action else { XCTAssertNil(rec, name); continue }
            guard let rec else { XCTFail("\(name): no recommendation"); continue }
            XCTAssertEqual(rec.action.rawValue, action, "\(name) action")
            XCTAssertEqual(rec.rationaleKey, expected.rationaleKey, "\(name) rationale")
            if let id = expected.exerciseId { XCTAssertEqual(rec.exerciseId, id, "\(name) exerciseId") }
            if let display = expected.suggestedWeightDisplay { XCTAssertEqual(rec.suggestedWeightDisplay, display, "\(name) suggested") }
            if let delta = expected.weightDeltaDisplay { XCTAssertEqual(rec.weightDeltaDisplay, delta, "\(name) delta") }

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
                XCTAssertEqual(row.completedReps, target.reps, "\(name) applied set \(index + 1) reps")
            }

            // Prefill next must never overwrite applied targets: complete each set in order with it on.
            var current = after
            for index in after.indices {
                current = WorkoutSessionUtils.togglingCompletion(of: index, in: current, prefillNextSet: true, unit: unit)
                XCTAssertTrue(current[index].isCompleted, "\(name) set \(index + 1) completes")
                XCTAssertEqual(current.map { row in var row = row; row.isCompleted = false; return row }, after,
                               "\(name) rows keep their applied targets after completing set \(index + 1)")
            }
        }
    }
}
