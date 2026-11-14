import SwiftUI
import XCTest
@testable import FormApp

/// Executes the shared training-block contract (gym/docs/block-fixtures.json, rules in gym/docs/training-blocks.md).
/// Android TrainingBlockFixturesTest runs the same file; update it with scripts/sync_progression_fixtures.cjs.
final class TrainingBlockFixtureTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Schedule: Decodable { let length: Int; let targets: [Int] }
        struct Window: Decodable { let target: Int; let window: [Int] }
        struct Performance: Decodable { let name: String; let previous: [[Double]]; let current: [[Double]]; let fell: Bool }
        struct Row: Decodable {
            let key: String; let sets: Int; let primary: [String]; let secondary: [String]
            let baseSets: Int?; let jointHigh: Int?; let highThisWeek: Bool?; let performanceFell: Bool?
        }
        struct Answer: Decodable { let pump: String?; let workload: String?; let soreness: String? }
        struct Change: Decodable { let muscle: String; let from: Double; let to: Double; let reasons: [String] }
        struct Expected: Decodable { let sets: [String: Int]; let additions: [String]?; let changes: [Change]? }
        struct WeekCase: Decodable {
            let name: String; let kind: String; let exercises: [Row]; let focus: [String]?; let additions: [String]?
            let feedback: [String: [Answer]]?; let expected: Expected
        }
        struct ReadinessCase: Decodable {
            struct Expected: Decodable { let offered: Bool; let options: [String]; let moreRirTarget: Int? }
            let name: String; let answers: [String: String]; let target: Int?; let deload: Bool; let expected: Expected
        }
        struct FewerSetsCase: Decodable {
            struct Row: Decodable { let done: Bool?; let warmup: Bool? }
            struct Expected: Decodable { let kept: [Int]; let sets: Int }
            let name: String; let sets: Int; let rows: [Row]; let expected: Expected
        }
        struct Strength: Decodable {
            struct Top: Decodable { let reps: Int; let rir: Int }
            struct Backoff: Decodable { let sets: Int; let reps: Int; let percent: Double }
            struct ScheduleRow: Decodable { let weeksToTest: Int; let top: Top?; let backoff: Backoff?; let test: [Double]? }
            struct WeekRow: Decodable { let key: String; let sets: Int }
            struct WeekCase: Decodable { let name: String; let length: Int; let lifts: [String]; let exercises: [WeekRow]; let expected: [[String: Int]] }
            struct Lift: Decodable { let exerciseId: String; let name: String }
            struct LoadCase: Decodable { let name: String; let unit: String; let exercise: Lift; let e1rm: Double; let reps: Int; let rir: Int; let expected: Double }
            struct BackoffCase: Decodable { let name: String; let unit: String; let exercise: Lift; let top: Double; let percent: Double; let expected: Double }
            struct AttemptCase: Decodable { let name: String; let unit: String; let exercise: Lift; let e1rm: Double; let expected: [Double] }
            struct ChoiceRow: Decodable { let key: String; let exerciseId: String }
            struct ChoiceCase: Decodable { let name: String; let exercises: [ChoiceRow]; let expected: [String] }
            let lengths: [Int]
            let lifts: [String]
            let choices: [ChoiceCase]
            let schedule: [ScheduleRow]
            let weeks: [WeekCase]
            let loads: [LoadCase]
            let backoffs: [BackoffCase]
            let attempts: [AttemptCase]
        }
        struct StartWorkout: Decodable { let id: String; let day: Int }
        struct StartCase: Decodable { let name: String; let today: Int; let workouts: [StartWorkout]; let completed: [String]; let expected: String }
        let references: [String: [Double]]
        let start: [StartCase]
        let strength: Strength
        let readiness: [ReadinessCase]
        let fewerSets: [FewerSetsCase]
        let schedule: [Schedule]
        let windows: [Window]
        let performance: [Performance]
        let weeks: [WeekCase]
    }

    private func load() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("block-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    func testReferenceRangesMatchVolumeMatrix() throws {
        let fixtures = try load()
        XCTAssertEqual(Set(fixtures.references.keys), Set(TrainingBlockRules.muscles))
        for (muscle, range) in fixtures.references {
            let landmark = try XCTUnwrap(VolumeLandmark.defaults[muscle])
            XCTAssertEqual(Double(landmark.mev), range[0], muscle)
            XCTAssertEqual(Double(landmark.mavMax), range[1], muscle)
        }
    }

    func testScheduleWindowsAndPerformanceMatch() throws {
        let fixtures = try load()
        for row in fixtures.schedule {
            XCTAssertEqual(TrainingBlockRules.targets(length: row.length), row.targets, "length \(row.length)")
            XCTAssertTrue(TrainingBlockRules.isDeload(length: row.length, week: row.length))
            XCTAssertFalse(TrainingBlockRules.isDeload(length: row.length, week: row.length - 1))
        }
        XCTAssertEqual(TrainingBlockRules.targets(length: 7), [])
        for row in fixtures.windows {
            XCTAssertEqual(TrainingBlockRules.window(target: row.target), row.window[0]...row.window[1])
        }
        for row in fixtures.performance {
            func pairs(_ rows: [[Double]]) -> [(Double, Int)] { rows.map { ($0[0], Int($0[1])) } }
            XCTAssertEqual(TrainingBlockRules.performanceFell(previous: pairs(row.previous), current: pairs(row.current)), row.fell, row.name)
        }
    }

    /// The setup's default start week (docs/training-blocks.md#weeks).
    func testTheSetupSuggestsAWeekWithWorkoutsLeft() throws {
        for row in try load().start {
            let workouts = row.workouts.map {
                Workout(id: $0.id, day: $0.day, title: $0.id,
                        exercises: [Exercise(id: "e", name: "Barbell Bench Press", sets: 3, reps: RepTarget(min: 8, max: 12))])
            }
            let program = Program(id: "p", name: "P", workouts: workouts)
            XCTAssertEqual(TrainingBlocks.suggestsNextWeek(program, completed: row.completed.map { "p:\($0)" }, today: row.today),
                           row.expected == "next", row.name)
        }
    }

    /// Only squat, bench, deadlift and overhead press variations can be tested (docs/training-blocks.md#strength-blocks).
    func testStrengthBlocksOfferOnlyTestLifts() throws {
        let strength = try load().strength
        XCTAssertEqual(TrainingBlocks.testLifts, Set(strength.lifts))
        for row in strength.choices {
            var workoutIds: [String] = []
            for exercise in row.exercises {
                let id = String(exercise.key.split(separator: "/")[0])
                if !workoutIds.contains(id) { workoutIds.append(id) }
            }
            let workouts = workoutIds.enumerated().map { index, workoutId in
                Workout(id: workoutId, day: index + 1, title: workoutId, exercises: row.exercises.filter { $0.key.hasPrefix(workoutId + "/") }.map {
                    Exercise(id: String($0.key.split(separator: "/")[1]),
                             name: ExerciseCatalog.canonicalExercises[$0.exerciseId]?.name ?? $0.exerciseId,
                             exerciseId: $0.exerciseId, sets: 3, reps: RepTarget(min: 5, max: 8))
                })
            }
            XCTAssertEqual(TrainingBlocks.liftChoices(Program(id: "p", name: "P", workouts: workouts)).map(\.key), row.expected, row.name)
        }
    }

    func testStrengthMatchesTheSharedContract() throws {
        let strength = try load().strength
        XCTAssertEqual(TrainingBlockRules.strengthLengths, strength.lengths[0]...strength.lengths[1])
        for row in strength.schedule {
            let plan = try XCTUnwrap(TrainingBlockRules.strengthWeek(length: 8, week: 8 - row.weeksToTest))
            if let test = row.test {
                XCTAssertTrue(plan.test)
                XCTAssertEqual(TrainingBlockRules.testPercents, test)
                XCTAssertEqual(plan.liftSets, 3)
                XCTAssertEqual(plan.liftReps, 1)
            } else if let top = row.top, let backoff = row.backoff {
                XCTAssertEqual(plan.topReps, top.reps, "\(row.weeksToTest)")
                XCTAssertEqual(plan.topRir, top.rir, "\(row.weeksToTest)")
                XCTAssertEqual(plan.backoffSets, backoff.sets)
                XCTAssertEqual(plan.backoffReps, backoff.reps)
                XCTAssertEqual(plan.backoffPercent, backoff.percent)
                XCTAssertEqual(plan.liftSets, 1 + backoff.sets)
            }
        }
        XCTAssertNil(TrainingBlockRules.strengthWeek(length: 3, week: 1))
        for fixture in strength.weeks {
            for (index, expected) in fixture.expected.enumerated() {
                XCTAssertEqual(TrainingBlockRules.strengthSets(fixture.exercises.map { (key: $0.key, sets: $0.sets) }, lifts: Set(fixture.lifts),
                                                               length: fixture.length, week: index + 1), expected, "\(fixture.name) week \(index + 1)")
            }
        }
        func lift(_ row: Fixtures.Strength.Lift) -> Exercise { Exercise(id: "lift", name: row.name, exerciseId: row.exerciseId, sets: 3, reps: RepTarget(min: 5, max: 5)) }
        for row in strength.loads {
            let unit = WeightUnit.fromCode(row.unit)
            let target = TrainingBlockRules.topSetTarget(e1rm: unit.toCanonicalKg(row.e1rm), reps: row.reps, rir: row.rir)
            let load = try XCTUnwrap(ProgressionEngine.gridLoadKg(exercise: lift(row.exercise), targetKg: target, unit: unit), row.name)
            XCTAssertEqual(unit.toDisplay(load), row.expected, accuracy: 1e-6, row.name)
        }
        for row in strength.backoffs {
            let unit = WeightUnit.fromCode(row.unit)
            let load = try XCTUnwrap(ProgressionEngine.gridLoadKg(exercise: lift(row.exercise), targetKg: unit.toCanonicalKg(row.top) * row.percent / 100, unit: unit))
            XCTAssertEqual(unit.toDisplay(load), row.expected, accuracy: 1e-6, row.name)
        }
        for row in strength.attempts {
            let unit = WeightUnit.fromCode(row.unit)
            let loads = try XCTUnwrap(ProgressionEngine.attemptsKg(exercise: lift(row.exercise), e1rmKg: unit.toCanonicalKg(row.e1rm), unit: unit))
            XCTAssertEqual(loads.map { (unit.toDisplay($0) * 1000).rounded() / 1000 }, row.expected, row.name)
        }
    }

    func testReadinessMatchesTheSharedContract() throws {
        for fixture in try load().readiness {
            let a = fixture.answers
            let check = ReadinessCheck(sleep: a["sleep"], energy: a["energy"], soreness: a["soreness"], choice: a["choice"])
            let offered = Readiness.offersLighterDay(check)
            XCTAssertEqual(offered, fixture.expected.offered, fixture.name)
            XCTAssertEqual(offered ? Readiness.options(blockTarget: fixture.target, deload: fixture.deload) : [], fixture.expected.options, fixture.name)
            if let moreRir = fixture.expected.moreRirTarget {
                var chosen = check; chosen.choice = "more_rir"
                XCTAssertEqual(Readiness.target(fixture.target, check: chosen), moreRir, fixture.name)
            }
            var planned = check; planned.choice = "planned"
            XCTAssertEqual(Readiness.target(fixture.target, check: planned), fixture.target, "\(fixture.name) planned keeps the target")
        }
    }

    func testFewerSetsMatchesTheSharedContract() throws {
        for fixture in try load().fewerSets {
            let rows = fixture.rows.enumerated().map { index, row in
                ExerciseSetLog(id: "row-\(index)", setNumber: index + 1, isCompleted: row.done ?? false, isWarmup: row.warmup ?? false)
            }
            let exercise = Exercise(id: "e", name: "Bench", sets: fixture.sets, reps: RepTarget(min: 8, max: 12))
            let draft = ActiveSessionDraft(programId: "p", workout: Workout(id: "w", day: 1, title: "W", exercises: [exercise]),
                                           startedAt: "2026-11-07T10:00:00Z", startedAtEpochMillis: 0, setsByExercise: ["e": rows])
            let lighter = Readiness.fewerSets(draft)
            XCTAssertEqual(lighter.setsByExercise["e"]?.map(\.id), fixture.expected.kept.map { "row-\($0)" }, fixture.name)
            XCTAssertEqual(lighter.workout.exercises.first?.sets, fixture.expected.sets, fixture.name)
        }
    }

    func testEveryWeekCaseMatchesTheSharedContract() throws {
        for fixture in try load().weeks {
            let exercises = fixture.exercises.map { row in
                TrainingBlockRules.Exercise(key: row.key, sets: row.sets, primary: row.primary, secondary: row.secondary,
                                            baseSets: row.baseSets, jointHigh: row.jointHigh ?? 0,
                                            highThisWeek: row.highThisWeek ?? false, performanceFell: row.performanceFell ?? false)
            }
            if fixture.kind == "deload" {
                XCTAssertEqual(TrainingBlockRules.deloadWeek(Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0.sets) })),
                               fixture.expected.sets, fixture.name)
                continue
            }
            let week = fixture.kind == "first"
                ? TrainingBlockRules.firstWeek(exercises, focus: fixture.focus ?? [])
                : TrainingBlockRules.nextWeek(exercises, feedback: (fixture.feedback ?? [:]).mapValues { answers in
                    answers.map { MuscleFeedback(pump: $0.pump, workload: $0.workload, soreness: $0.soreness) }
                }, additions: fixture.additions ?? [])
            XCTAssertEqual(week.sets, fixture.expected.sets, "\(fixture.name) sets")
            XCTAssertEqual(week.additions, fixture.expected.additions ?? [], "\(fixture.name) additions")
            XCTAssertEqual(week.changes, (fixture.expected.changes ?? []).map {
                BlockMuscleChange(muscle: $0.muscle, from: $0.from, to: $0.to, reasons: $0.reasons)
            }, "\(fixture.name) changes")
        }
    }
}

/// Training blocks against programs, history and the muscle catalog; Android TrainingBlocksTest matches.
final class TrainingBlocksTests: XCTestCase {
    private let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 3, reps: RepTarget(min: 8, max: 12))
    private let raise = Exercise(id: "raise", name: "Dumbbell Lateral Raise", exerciseId: "dumbbell-lateral-raise", sets: 3, reps: RepTarget(min: 12, max: 15))
    private let squat = Exercise(id: "squat", name: "Barbell Back Squat", exerciseId: "barbell-back-squat", sets: 4, reps: RepTarget(min: 6, max: 10))
    private let extensionLift = Exercise(id: "extension", name: "Leg Extension", exerciseId: "leg-extension", sets: 3, reps: RepTarget(min: 10, max: 15))
    private var upper: Workout { Workout(id: "upper", day: 1, title: "Upper", exercises: [bench, raise]) }
    private var lower: Workout { Workout(id: "lower", day: 3, title: "Lower", exercises: [squat, extensionLift]) }
    private var program: Program { Program(id: "p", name: "Upper Lower", workouts: [upper, lower]) }

    func testTheEstimateReadsTheLiftFromAnyRecentSession() throws {
        let now = try XCTUnwrap(WorkoutCalendar.parseIsoTimestamp("2026-11-20T12:00:00Z"))
        let block = try XCTUnwrap(TrainingBlocks.startStrength(program, length: 5, lifts: ["lower/squat"], startWeek: "2026-W45", id: "s"))
        // Another program's leg day: the same squat under its own exercise id, and another exercise.
        var legsSquat = squat
        legsSquat.id = "legs-squat"
        let front = Exercise(id: "front", name: "Barbell Front Squat", exerciseId: "barbell-front-squat", sets: 3, reps: RepTarget(min: 3, max: 5))
        let legs = Workout(id: "legs", day: 2, title: "Legs", exercises: [legsSquat, front])
        var elsewhere = record("legs", block, week: 1, workout: legs, completedAt: "2026-11-03T18:00:00Z",
                               sets: ["legs-squat": [(140, 4)], "front": [(150, 3)]])
        elsewhere.programId = "other"
        elsewhere.blockId = nil
        elsewhere.blockWeek = nil
        XCTAssertEqual(try XCTUnwrap(TrainingBlocks.estimatedOneRepMaxKg(workout: lower, exercise: squat, history: [elsewhere], now: now)),
                       140.0 * 36 / 33, accuracy: 1e-6, "the squat logged in another workout counts")
        var stale = elsewhere
        stale.id = "stale"
        stale.startedAt = "2026-09-01T18:00:00Z"
        stale.completedAt = "2026-09-01T18:00:00Z"
        XCTAssertNil(TrainingBlocks.estimatedOneRepMaxKg(workout: lower, exercise: squat, history: [stale], now: now), "but not past the 42 days")
        XCTAssertNil(TrainingBlocks.estimatedOneRepMaxKg(workout: lower, exercise: squat, history: [elsewhere], now: now, excludeSessionId: "legs"),
                     "and not this session")
        let own = record("own", block, week: 1, workout: lower, completedAt: "2026-11-10T18:00:00Z", sets: ["squat": [(130, 5)]])
        XCTAssertEqual(try XCTUnwrap(TrainingBlocks.estimatedOneRepMaxKg(workout: lower, exercise: squat, history: [own, elsewhere], now: now)),
                       140.0 * 36 / 33, accuracy: 1e-6, "the best of both")
    }

    func testSummaryBarsShowSmallDifferencesAsSmall() throws {
        // A taper week's estimate 0.7 kg under week 1 stays nearly as tall; week 2 had no session.
        let taper = weekBarFractions([147.3, nil, 146.6], fromZero: false)
        XCTAssertEqual(try XCTUnwrap(taper[0]), 1, accuracy: 1e-9)
        XCTAssertNil(taper[1])
        XCTAssertGreaterThan(try XCTUnwrap(taper[2]), 0.95, "a 0.5% dip is no drop")
        // A real 10% gain still shows clearly.
        XCTAssertLessThan(try XCTUnwrap(weekBarFractions([140, 154], fromZero: false)[0]), 0.45)
        XCTAssertEqual(weekBarFractions([10, 20], fromZero: true), [0.5, 1])
        XCTAssertEqual(weekBarFractions([120], fromZero: false), [1], "one week fills its bar")
    }

    private func record(_ id: String, _ block: TrainingBlock, week: Int, workout: Workout, completedAt: String,
                        sets: [String: [(Double, Int)]], feedback: [String: MuscleFeedback]? = nil,
                        jointStress: [String: String] = [:]) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: id, programId: program.id, workoutId: workout.id, workoutTitle: workout.title, startedAt: completedAt,
            completedAt: completedAt, durationSeconds: 3600,
            exerciseLogs: workout.exercises.map { exercise in
                SessionExerciseLog(exerciseName: exercise.name,
                                   sets: (sets[exercise.id] ?? []).enumerated().map { SessionSetLog(setNumber: $0.offset + 1, weightKg: $0.element.0, reps: $0.element.1) },
                                   exerciseId: exercise.exerciseId, jointStress: jointStress[exercise.id])
            },
            blockId: block.id, blockWeek: week, muscleFeedback: feedback)
    }

    func testWeekKeysCountCalendarWeeksAcrossTheYear() throws {
        let block = TrainingBlock(id: "b", programId: "p", startWeek: "2026-W52", length: 5)
        XCTAssertNil(TrainingBlocks.weekIndex(block, weekKey: "2026-W51"))
        XCTAssertEqual(TrainingBlocks.weekIndex(block, weekKey: "2026-W52"), 1)
        XCTAssertEqual(TrainingBlocks.weekIndex(block, weekKey: "2027-W01"), 3)
        XCTAssertEqual(TrainingBlocks.weekKey(try XCTUnwrap(TrainingBlocks.monday("2026-W45"))), "2026-W45")
        XCTAssertNil(TrainingBlocks.monday("2026-W5"))
    }

    func testStartingABlockUsesTheProgramAndAddsFocusSets() throws {
        let block = try XCTUnwrap(TrainingBlocks.start(program, length: 5, focus: ["side-delts", "calves"], startWeek: "2026-W45", id: "b"))
        XCTAssertEqual(TrainingBlocks.focusChoices(program), ["chest", "side-delts", "quads", "glutes"])
        XCTAssertEqual(block.weeks[0].sets, ["upper/bench": 3, "upper/raise": 4, "lower/squat": 4, "lower/extension": 3])
        XCTAssertEqual(block.weeks[0].changes, [BlockMuscleChange(muscle: "side-delts", from: 3, to: 4, reasons: ["focus"])])
        XCTAssertEqual(block.additions, ["upper/raise"])
        XCTAssertTrue(block.weeks[0].reviewed)
        XCTAssertEqual(TrainingBlocks.activeWeek(block, programId: "p", weekKey: "2026-W45"), 1)
        XCTAssertNil(TrainingBlocks.activeWeek(block, programId: "other", weekKey: "2026-W45"))
        let later = try XCTUnwrap(TrainingBlocks.start(program, length: 4, focus: [], startWeek: "2026-W46"))
        XCTAssertNil(TrainingBlocks.activeWeek(later, programId: "p", weekKey: "2026-W45"), "a block started next week is not active yet")
    }

    func testEachWeekFollowsThePreviousWeeksAnswersAndLogs() throws {
        var block = try XCTUnwrap(TrainingBlocks.start(program, length: 4, focus: [], startWeek: "2026-W45", id: "b"))
        let history = [
            record("u1", block, week: 1, workout: upper, completedAt: "2026-11-02T18:00:00Z",
                   sets: ["bench": [(100, 10), (100, 10), (100, 9)], "raise": [(10, 15), (10, 15), (10, 14)]],
                   feedback: ["chest": MuscleFeedback(pump: "great", workload: "easy", soreness: "healed_early"),
                              "side-delts": MuscleFeedback(pump: "low", workload: "right", soreness: "never")]),
            record("l1", block, week: 1, workout: lower, completedAt: "2026-11-04T18:00:00Z",
                   sets: ["squat": [(120, 8), (120, 8), (120, 8), (120, 8)], "extension": [(50, 12), (50, 12), (50, 12)]],
                   feedback: ["quads": MuscleFeedback(workload: "too_much")]),
            record("other", TrainingBlock(id: "old", programId: "p", startWeek: "2026-W40", length: 4), week: 1, workout: upper,
                   completedAt: "2026-11-03T18:00:00Z", sets: [:], feedback: ["chest": MuscleFeedback(soreness: "still_sore")])
        ]
        XCTAssertEqual(TrainingBlocks.advance(block, program: program, history: history, weekKey: "2026-W45"), block)
        block = TrainingBlocks.advance(block, program: program, history: history, weekKey: "2026-W46")
        XCTAssertEqual(block.weeks[1].sets, ["upper/bench": 4, "upper/raise": 5, "lower/squat": 3, "lower/extension": 3])
        XCTAssertEqual(block.weeks[1].changes.map(\.muscle), ["chest", "side-delts", "quads"])
        XCTAssertEqual(block.weeks[1].changes[1].reasons, ["recovered", "low_pump"])
        XCTAssertFalse(block.weeks[1].reviewed)

        let session = TrainingBlocks.sessionWorkout(block, week: 2, workout: upper)
        XCTAssertEqual(session.exercises.map(\.sets), [4, 5])
        XCTAssertEqual(upper.exercises.map(\.sets), [3, 3])

        let weekTwo = history + [record("u2", block, week: 2, workout: upper, completedAt: "2026-11-09T18:00:00Z",
                                        sets: ["bench": [(100, 9), (100, 9), (100, 9), (100, 8)]],
                                        feedback: ["chest": MuscleFeedback(workload: "easy", soreness: "never")],
                                        jointStress: ["raise": JointStress.high.rawValue])]
        let edited = TrainingBlocks.edit(block, week: 2, sets: ["lower/squat": 4, "unknown": 4, "upper/bench": 11])
        XCTAssertEqual(edited.weeks[1].edited, ["lower/squat"])
        XCTAssertEqual(edited.weeks[1].sets["upper/bench"], 4, "out-of-range counts are ignored")
        let three = TrainingBlocks.advance(edited, program: program, history: weekTwo, weekKey: "2026-W47")
        XCTAssertEqual(three.weeks[2].changes, [BlockMuscleChange(muscle: "chest", from: 4, to: 4, reasons: ["performance"])])
        XCTAssertEqual(three.weeks[2].sets["lower/squat"], 4, "the lifter's edit carries forward")

        let done = TrainingBlocks.advance(three, program: program, history: weekTwo, weekKey: "2026-W50")
        XCTAssertEqual(done.weeks.count, 4)
        XCTAssertEqual(done.weeks[3].sets, ["upper/bench": 2, "upper/raise": 3, "lower/squat": 2, "lower/extension": 2])
        XCTAssertTrue(TrainingBlocks.isFinished(done, weekKey: "2026-W49"))
        XCTAssertFalse(TrainingBlocks.isFinished(done, weekKey: "2026-W48"))
        XCTAssertNil(TrainingBlocks.activeWeek(done, programId: "p", weekKey: "2026-W49"))
    }

    func testAStrengthBlockPeaksItsLiftsForTheTest() throws {
        XCTAssertEqual(TrainingBlocks.liftChoices(program).map(\.key), ["upper/bench", "lower/squat"])
        let block = try XCTUnwrap(TrainingBlocks.startStrength(program, length: 5, lifts: ["lower/squat", "upper/raise", "lower/squat"],
                                                               startWeek: "2026-W45", id: "s"))
        XCTAssertEqual(block.lifts, ["lower/squat"], "only barbell lifts, once each")
        XCTAssertTrue(block.isStrength)
        XCTAssertEqual(block.weeks.count, 5)
        XCTAssertTrue(block.weeks.allSatisfy(\.reviewed))
        XCTAssertEqual(TrainingBlocks.advance(block, program: program, history: [], weekKey: "2026-W48"), block)
        let week1 = TrainingBlocks.sessionWorkout(block, week: 1, workout: lower)
        XCTAssertEqual(week1.exercises[0].sets, 4)
        XCTAssertEqual(week1.exercises[0].reps, RepTarget(min: 5, max: 5))
        XCTAssertEqual(week1.exercises[1].sets, 3)
        XCTAssertEqual(TrainingBlocks.sessionWorkout(block, week: 4, workout: lower).exercises.map(\.sets), [3, 2])
        let test = TrainingBlocks.sessionWorkout(block, week: 5, workout: lower)
        XCTAssertEqual(test.exercises[0].sets, 3)
        XCTAssertEqual(test.exercises[0].reps, RepTarget(min: 1, max: 1))
        XCTAssertEqual(TrainingBlocks.strengthLift(block, week: 4, workout: lower, exercise: squat)?.topReps, 2)
        XCTAssertNil(TrainingBlocks.strengthLift(block, week: 4, workout: lower, exercise: extensionLift))

        let now = try XCTUnwrap(WorkoutCalendar.parseIsoTimestamp("2026-11-20T12:00:00Z"))
        var old = record("old", block, week: 1, workout: lower, completedAt: "2026-09-01T18:00:00Z", sets: ["squat": [(200, 3)]])
        old.blockId = nil
        old.blockWeek = nil
        let history = [old,
            record("l1", block, week: 1, workout: lower, completedAt: "2026-11-02T18:00:00Z", sets: ["squat": [(140, 5), (120, 5)]]),
            record("l3", block, week: 3, workout: lower, completedAt: "2026-11-16T18:00:00Z", sets: ["squat": [(150, 4), (130, 4)]]),
            record("l5", block, week: 5, workout: lower, completedAt: "2026-11-30T18:00:00Z", sets: ["squat": [(150, 1), (160, 1), (165, 1)]])]
        XCTAssertEqual(try XCTUnwrap(TrainingBlocks.estimatedOneRepMaxKg(workout: lower, exercise: squat, history: Array(history.prefix(3)), now: now)),
                       150.0 * 36 / 33, accuracy: 1e-6, "the last 42 days only")
        XCTAssertNil(TrainingBlocks.estimatedOneRepMaxKg(workout: upper, exercise: bench, history: history, now: now))
        let progress = try XCTUnwrap(TrainingBlocks.liftProgress(block, program: program, history: history).first)
        XCTAssertEqual(progress.exerciseName, "Barbell Back Squat")
        XCTAssertEqual(progress.byWeek.count, 4)
        XCTAssertEqual(progress.byWeek[0] ?? 0, 140.0 * 36 / 32, accuracy: 1e-6)
        XCTAssertNil(progress.byWeek[1])
        XCTAssertEqual(progress.testKg, 165)

        let state = StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: "2026-W45", trainingBlock: block)
        let json = try XCTUnwrap(AppStore.encodeBackup(FullBackupDocument(state: state, weightUnit: .kg)))
        XCTAssertEqual(try JSONDecoder().decode(FullBackupDocument.self, from: Data(json.utf8)).state.trainingBlock, block)
        var noLift = block
        noLift.lifts = []
        XCTAssertNil(TrainingBlocks.sanitize(noLift, programs: [program]), "a strength block needs a lift")
        var long = block
        long.length = 8
        XCTAssertEqual(TrainingBlocks.sanitize(long, programs: [program])?.length, 8)
        var muscleLong = block
        muscleLong.kind = nil
        muscleLong.length = 8
        XCTAssertNil(TrainingBlocks.sanitize(muscleLong, programs: [program]), "muscle blocks stay 4 to 6 weeks")
    }

    func testFeedbackIsAskedAroundEachMusclesFirstAndLastExercise() {
        let workout = Workout(id: "w", day: 1, title: "Mixed", exercises: [bench, squat, raise, extensionLift])
        let plan = TrainingBlocks.feedbackPlan(workout)
        XCTAssertEqual(plan.sorenessBefore, [0: ["chest"], 1: ["quads", "glutes"], 2: ["side-delts"]])
        XCTAssertEqual(plan.pumpAfter, [0: ["chest"], 1: ["glutes"], 2: ["side-delts"], 3: ["quads"]])
    }

    func testSummaryComparesTheFirstAndLastHardWeeks() throws {
        let block = try XCTUnwrap(TrainingBlocks.start(program, length: 4, focus: [], startWeek: "2026-W45", id: "b"))
        let history = [
            record("u1", block, week: 1, workout: upper, completedAt: "2026-11-02T18:00:00Z", sets: ["bench": [(100, 10)]]),
            record("u3", block, week: 3, workout: upper, completedAt: "2026-11-16T18:00:00Z", sets: ["bench": [(100, 12), (105, 8)]]),
            record("l1", block, week: 1, workout: lower, completedAt: "2026-11-04T18:00:00Z", sets: ["squat": [(120, 8)]])
        ]
        let changes = TrainingBlocks.strengthChanges(block, program: program, history: history)
        XCTAssertEqual(changes.map(\.exerciseName), ["Barbell Bench Press"])
        XCTAssertEqual(changes[0].fromKg, 100.0 * 36 / 27, accuracy: 1e-6)
        // 100 × 12 is past Rep Lab's 1–10 rep limit, so 105 × 8 is the best estimate.
        XCTAssertEqual(changes[0].toKg, 105.0 * 36 / 29, accuracy: 1e-6)
        XCTAssertEqual(TrainingBlocks.setsByWeek(block, program: program).first { $0.muscle == "chest" }?.weeks, [3])
    }

    func testBackupsCarryTheBlockAndSessionFields() throws {
        let block = try XCTUnwrap(TrainingBlocks.start(program, length: 6, focus: ["chest"], startWeek: "2026-W45", id: "b"))
        let saved = record("u1", block, week: 1, workout: upper, completedAt: "2026-11-02T18:00:00Z", sets: ["bench": [(100, 10)]],
                           feedback: ["chest": MuscleFeedback(pump: "low", workload: "easy", soreness: "never"), "forearms": MuscleFeedback(pump: "low")])
        let state = StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: "2026-W45", history: [saved], trainingBlock: block)
        let json = try XCTUnwrap(AppStore.encodeBackup(FullBackupDocument(state: state, weightUnit: .kg)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, StoredAppState.currentSchemaVersion)
        XCTAssertEqual(StoredAppState.currentSchemaVersion, 8)
        let restored = try JSONDecoder().decode(FullBackupDocument.self, from: Data(json.utf8)).state
        XCTAssertEqual(restored.trainingBlock, block)
        let record = try XCTUnwrap(restored.history.first)
        XCTAssertEqual(record.blockId, "b")
        XCTAssertEqual(record.blockWeek, 1)
        XCTAssertEqual(record.muscleFeedback.map { Array($0.keys) }, ["chest"], "muscles without a reference are never asked")

        var orphan = state
        orphan.trainingBlock?.programId = "gone"
        let orphanJson = try XCTUnwrap(AppStore.encodeBackup(FullBackupDocument(state: orphan, weightUnit: .kg)))
        XCTAssertNil(try JSONDecoder().decode(FullBackupDocument.self, from: Data(orphanJson.utf8)).state.trainingBlock)
        var broken = state
        broken.trainingBlock?.length = 9
        let brokenJson = try XCTUnwrap(AppStore.encodeBackup(FullBackupDocument(state: broken, weightUnit: .kg)))
        let brokenState = try JSONDecoder().decode(FullBackupDocument.self, from: Data(brokenJson.utf8)).state
        XCTAssertNil(brokenState.trainingBlock)
        XCTAssertEqual(brokenState.history.count, 1)
    }

    func testDraftsKeepBlockFieldsAndTheRecordCarriesThem() throws {
        var draft = ActiveSessionDraft(programId: "p", workout: upper, startedAt: "2026-11-02T18:00:00Z", startedAtEpochMillis: 0,
                                       blockId: "b", blockWeek: 2,
                                       muscleFeedback: ["chest": MuscleFeedback(pump: "low"), "forearms": MuscleFeedback(pump: "low")])
        let decoded = try JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded.blockId, "b")
        XCTAssertEqual(decoded.blockWeek, 2)
        XCTAssertEqual(decoded.muscleFeedback, ["chest": MuscleFeedback(pump: "low")])
        draft.blockWeek = 9
        XCTAssertNil(try JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(draft)).blockId)
        let saved = SessionProgress.from(draft: decoded, nowEpochMillis: 1_000).record(draft: decoded, completedAtEpochMillis: 1_000)
        XCTAssertEqual(saved.blockId, "b")
        XCTAssertEqual(saved.muscleFeedback, ["chest": MuscleFeedback(pump: "low")])
    }
}

/// A block through the store and the views at narrow widths with large text (docs/training-blocks.md).
final class TrainingBlockStoreAndRenderTests: XCTestCase {
    private let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 2, reps: RepTarget(min: 8, max: 12))
    private let raise = Exercise(id: "raise", name: "Dumbbell Lateral Raise", exerciseId: "dumbbell-lateral-raise", sets: 3, reps: RepTarget(min: 12, max: 15))
    private let squat = Exercise(id: "squat", name: "Barbell Back Squat", exerciseId: "barbell-back-squat", sets: 4, reps: RepTarget(min: 6, max: 10))
    private var upper: Workout { Workout(id: "upper", day: 1, title: "Upper", exercises: [bench, raise]) }
    private var lower: Workout { Workout(id: "lower", day: 3, title: "Lower", exercises: [squat]) }
    private var program: Program { Program(id: "p", name: "Upper Lower", workouts: [upper, lower]) }

    private func preservingDefaults(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        try body()
    }

    func testAStartInsideABlockWeekTakesThatWeeksSetsAndKeepsItsAnswers() throws {
        try preservingDefaults {
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: store.state.currentWeekKey), durable: true))
            XCTAssertTrue(store.startTrainingBlock(length: 4, focus: ["chest"], nextWeek: false))
            let block = try XCTUnwrap(store.state.trainingBlock)
            XCTAssertEqual(block.startWeek, store.state.currentWeekKey)
            XCTAssertTrue(store.startActiveSession(programId: "p", workout: upper, allowPast: true))
            let draft = try XCTUnwrap(store.activeSession)
            XCTAssertEqual(draft.blockId, block.id)
            XCTAssertEqual(draft.blockWeek, 1)
            XCTAssertEqual(draft.workout.exercises.map(\.sets), [3, 3], "the focus set is in the session")
            XCTAssertEqual(draft.setsByExercise["bench"]?.count, 3)
            store.setMuscleFeedback(muscle: "chest", feedback: MuscleFeedback(pump: "low", workload: "bad"))
            store.setMuscleFeedback(muscle: "forearms", feedback: MuscleFeedback(pump: "low"))
            XCTAssertEqual(store.activeSession?.muscleFeedback, ["chest": MuscleFeedback(pump: "low")])
            store.abandonActiveSession()

            XCTAssertTrue(store.startTrainingBlock(length: 5, focus: [], nextWeek: true))
            XCTAssertNotEqual(store.state.trainingBlock?.startWeek, store.state.currentWeekKey)
            XCTAssertTrue(store.startActiveSession(programId: "p", workout: upper, allowPast: true))
            XCTAssertNil(store.activeSession?.blockId, "a block that starts next week leaves this week ordinary")
            store.setMuscleFeedback(muscle: "chest", feedback: MuscleFeedback(pump: "low"))
            XCTAssertNil(store.activeSession?.muscleFeedback, "only block sessions keep answers")
            store.abandonActiveSession()
            store.endTrainingBlock()
            XCTAssertNil(store.state.trainingBlock)
        }
    }

    func testALighterDayIsChosenOnceAndSaved() throws {
        try preservingDefaults {
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: store.state.currentWeekKey), durable: true))
            XCTAssertTrue(store.startActiveSession(programId: "p", workout: upper, allowPast: true))
            defer { store.abandonActiveSession() }
            store.chooseReadiness("fewer_sets")
            XCTAssertNil(store.activeSession?.readiness, "nothing is offered before two low answers")
            store.setReadiness(ReadinessCheck(sleep: "poor", energy: "low", soreness: "bad"))
            XCTAssertEqual(store.activeSession?.readiness, ReadinessCheck(sleep: "poor", energy: "low"))
            store.chooseReadiness("fewer_sets")
            var draft = try XCTUnwrap(store.activeSession)
            XCTAssertEqual(draft.workout.exercises.map(\.sets), [1, 2])
            XCTAssertEqual(draft.workout.exercises.map { draft.setsByExercise[$0.id]?.count }, [1, 2])
            store.chooseReadiness("fewer_sets")
            XCTAssertEqual(store.activeSession?.workout.exercises.map(\.sets), [1, 2], "a choice is made once")
            store.setReadiness(ReadinessCheck(sleep: "ok", energy: "low"))
            draft = try XCTUnwrap(store.activeSession)
            XCTAssertEqual(draft.readiness?.choice, "fewer_sets", "changing an answer keeps the choice")
            let saved = SessionProgress.from(draft: draft, nowEpochMillis: 1_000).record(draft: draft, completedAtEpochMillis: 1_000)
            XCTAssertEqual(saved.readiness, ReadinessCheck(sleep: "ok", energy: "low", choice: "fewer_sets"))
            let state = StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: "2026-W45", history: [saved])
            let json = try XCTUnwrap(AppStore.encodeBackup(FullBackupDocument(state: state, weightUnit: .kg)))
            XCTAssertEqual(try JSONDecoder().decode(FullBackupDocument.self, from: Data(json.utf8)).state.history.first?.readiness, saved.readiness)
        }
    }

    /// The back-off card moves under the ticked top set, right above the back-off rows its Use fills.
    func testTheBackOffCardSitsUnderTheTickedTopSet() throws {
        let plan = try XCTUnwrap(TrainingBlockRules.strengthWeek(length: 6, week: 1))
        func rows(_ done: [Bool], warmup: Bool = false) -> [ExerciseSetLog] {
            (warmup ? [ExerciseSetLog(id: "w", setNumber: 1, isCompleted: true, isWarmup: true)] : [])
                + done.enumerated().map { ExerciseSetLog(id: "s\($0.offset)", setNumber: $0.offset + 1, isCompleted: $0.element) }
        }
        XCTAssertNil(plan.backoffCardRow(rows([false, false, false, false])), "before the top set the card stays above the rows")
        XCTAssertEqual(plan.backoffCardRow(rows([true, false, false, false])), 0)
        XCTAssertEqual(plan.backoffCardRow(rows([true, true, false, false])), 0, "it stays while a back-off is open")
        XCTAssertEqual(plan.backoffCardRow(rows([true, false, false, false], warmup: true)), 1, "warmups come first")
        XCTAssertNil(plan.backoffCardRow(rows([true, true, true, true])), "nothing is left to load")
        let test = try XCTUnwrap(TrainingBlockRules.strengthWeek(length: 6, week: 6))
        XCTAssertNil(test.backoffCardRow(rows([true, false, false])), "the test's singles keep their card above the rows")
        // Ticking the top set leaves the first back-off row empty; later rows and the test's singles pre-fill.
        XCTAssertFalse(plan.prefillsAfter(rows([false, false, false, false]), index: 0))
        XCTAssertFalse(plan.prefillsAfter(rows([false, false, false, false], warmup: true), index: 1), "after warmups too")
        XCTAssertTrue(plan.prefillsAfter(rows([true, false, false, false]), index: 1))
        XCTAssertTrue(test.prefillsAfter(rows([false, false, false]), index: 0))
    }

    /// A strength block through the store: the week's lift sets, the card's Use, and the test week's singles.
    @MainActor func testAStrengthBlockSessionSuggestsTopSetThenBackOffs() throws {
        try preservingDefaults {
            let previous = LanguageManager.shared.languagePreference
            defer { LanguageManager.setLanguage(previous) }
            LanguageManager.setLanguage("en")
            let access = ProAccessManager.shared
            access.setFeatureOverride(.autoProgression, unlocked: true)
            defer { access.setFeatureOverride(.autoProgression, unlocked: nil) }
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            let earlier = WorkoutCalendar.formatIsoTimestamp(Date().addingTimeInterval(-5 * 86_400))
            let prior = WorkoutSessionRecord(id: "earlier", programId: "p", workoutId: "lower", workoutTitle: "Lower", startedAt: earlier,
                completedAt: earlier, durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(exerciseName: squat.name, sets: [SessionSetLog(setNumber: 1, weightKg: 140, reps: 5)], exerciseId: squat.exerciseId)])
            XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: store.state.currentWeekKey,
                                                         history: [prior]), durable: true))
            XCTAssertTrue(store.startTrainingBlock(length: 6, focus: [], nextWeek: false, strength: true, lifts: ["lower/squat"]))
            XCTAssertTrue(store.startActiveSession(programId: "p", workout: lower, allowPast: true))
            defer { store.abandonActiveSession() }
            let draft = try XCTUnwrap(store.activeSession)
            XCTAssertEqual(draft.workout.exercises.map(\.sets), [4], "this lower day is the squat alone")
            XCTAssertEqual(draft.setsByExercise["squat"]?.count, 4)
            let estimate = TrainingBlocks.estimatedOneRepMaxKg(workout: draft.workout, exercise: draft.workout.exercises[0], history: store.state.history,
                                                               excludeSessionId: draft.id)
            XCTAssertEqual(try XCTUnwrap(estimate), 157.5, accuracy: 1e-6)
            func render(_ draft: ActiveSessionDraft, name: String) throws {
                let controller = UIHostingController(rootView: ActiveSessionView(store: store, draft: draft))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1500))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/block-review").standardized
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("\(name).png"))
            }
            try render(draft, name: "strength-session-top")
            // The top set ticked as the screen does: the next row stays empty, and the back-off card sits under the top set.
            var ticked = draft
            var top = try XCTUnwrap(ticked.setsByExercise["squat"]?.first)
            top.weightInput = "132.5"; top.weightKg = 132.5; top.repsInput = "5"; top.completedReps = 5; top.inputTouched = true
            ticked.setsByExercise["squat"]?[0] = top
            let plan = try XCTUnwrap(TrainingBlocks.strengthLift(store.state.trainingBlock, week: 1, workout: ticked.workout,
                                                                 exercise: ticked.workout.exercises[0]))
            ticked = WorkoutSessionUtils.toggledSet(ticked, exerciseId: "squat", index: 0,
                                                    prefillNextSet: plan.prefillsAfter(ticked.setsByExercise["squat"] ?? [], index: 0), now: 0)
            XCTAssertEqual(ticked.setsByExercise["squat"]?.map(\.weightInput), ["132.5", "", "", ""])
            XCTAssertEqual(plan.backoffCardRow(ticked.setsByExercise["squat"] ?? []), 0)
            store.activeSession = ticked
            try render(ticked, name: "strength-session-backoff")
        }
    }

    @MainActor private func render<V: View>(_ view: V, width: CGFloat, size: ContentSizeCategory, height: CGFloat, name: String) throws {
        let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/block-review").standardized
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let controller = UIHostingController(rootView: view.frame(width: width).frame(maxHeight: .infinity, alignment: .top)
            .environment(\.sizeCategory, size))
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
        try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("\(name).png"))
    }

    /// The folded question rows count answers and wait on a lighter-day choice.
    func testQuestionPromptsCountAnswersAndWaitOnAChoice() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")
        XCTAssertEqual(QuestionPrompt.readiness(nil).status, "0/3 answered")
        XCTAssertFalse(QuestionPrompt.readiness(nil).done)
        let rough = QuestionPrompt.readiness(ReadinessCheck(sleep: "poor", energy: "low"))
        XCTAssertEqual(rough.status, "Choose today's plan")
        XCTAssertFalse(rough.done)
        XCTAssertEqual(QuestionPrompt.readiness(ReadinessCheck(sleep: "poor", energy: "low", choice: "more_rir")).status, "2/3 answered")
        let soreness = QuestionPrompt.soreness(["chest", "triceps"], answers: ["chest": MuscleFeedback(soreness: "healed_early")])
        XCTAssertEqual(soreness.status, "1/2 answered")
        XCTAssertTrue(QuestionPrompt.soreness(["chest"], answers: ["chest": MuscleFeedback(soreness: "healed_early")]).done)
        XCTAssertEqual(readinessApplied(ReadinessCheck(choice: "fewer_sets"), lighterTarget: nil), "Lighter day: one set fewer per exercise.")
        XCTAssertNil(readinessApplied(ReadinessCheck(choice: "planned"), lighterTarget: "RIR 3"))
    }

    /// The workout screen inside a block week: the target in the pill, soreness before chest's first set, pump and workload after.
    @MainActor func testTheWorkoutScreenAsksTheBlockQuestions() throws {
        try preservingDefaults {
            let previous = LanguageManager.shared.languagePreference
            defer { LanguageManager.setLanguage(previous) }
            LanguageManager.setLanguage("en")
            let access = ProAccessManager.shared
            access.setFeatureOverride(.autoProgression, unlocked: true)
            defer { access.setFeatureOverride(.autoProgression, unlocked: nil) }
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            store.readinessCheck = true
            defer { store.readinessCheck = false }
            XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: "p", currentWeekKey: store.state.currentWeekKey), durable: true))
            XCTAssertTrue(store.startTrainingBlock(length: 4, focus: [], nextWeek: false))
            XCTAssertTrue(store.startActiveSession(programId: "p", workout: upper, allowPast: true))
            defer { store.abandonActiveSession() }
            store.setReadiness(ReadinessCheck(sleep: "poor", energy: "low"))
            store.chooseReadiness("more_rir")
            // With reps in reserve on every set, the pump card follows the sets without the effort rating.
            for (name, completed, rir) in [("soreness", false, nil), ("pump", true, nil), ("pump-rir", true, 2)] as [(String, Bool, Int?)] {
                var draft = try XCTUnwrap(store.activeSession)
                draft.setsByExercise["bench"] = (1...2).map {
                    var set = ExerciseSetLog(id: "b\($0)", setNumber: $0, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10,
                                             isCompleted: completed, inputTouched: true)
                    set.rir = rir
                    return set
                }
                store.activeSession = draft
                let controller = UIHostingController(rootView: ActiveSessionView(store: store, draft: draft))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1700))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let outputDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../build/block-review").standardized
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                try XCTUnwrap(image.pngData()).write(to: outputDir.appendingPathComponent("block-session-\(name).png"))
            }
        }
    }

    @MainActor func testEveryBlockViewRendersAtNarrowWidthAndLargeTextInEveryLanguage() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        var block = try XCTUnwrap(TrainingBlocks.start(program, length: 5, focus: ["side-delts"], startWeek: "2026-W45", id: "b"))
        let record = WorkoutSessionRecord(id: "u1", programId: "p", workoutId: "upper", workoutTitle: "Upper", startedAt: "2026-11-02T18:00:00Z",
            completedAt: "2026-11-02T19:00:00Z", durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(exerciseName: bench.name, sets: [SessionSetLog(setNumber: 1, weightKg: 100, reps: 10)], exerciseId: bench.exerciseId)],
            blockId: "b", blockWeek: 1,
            muscleFeedback: ["chest": MuscleFeedback(pump: "low", workload: "easy", soreness: "healed_early"), "side-delts": MuscleFeedback(soreness: "still_sore")])
        block = TrainingBlocks.advance(block, program: program, history: [record], weekKey: "2026-W46")
        let strengthBlock = try XCTUnwrap(TrainingBlocks.startStrength(program, length: 5, lifts: ["lower/squat"], startWeek: "2026-W45", id: "s"))
        let strengthRecord = WorkoutSessionRecord(id: "l1", programId: "p", workoutId: "lower", workoutTitle: "Lower", startedAt: "2026-11-04T18:00:00Z",
            completedAt: "2026-11-04T19:00:00Z", durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(exerciseName: squat.name, sets: [SessionSetLog(setNumber: 1, weightKg: 140, reps: 5)], exerciseId: squat.exerciseId)],
            blockId: "s", blockWeek: 1)
        LanguageManager.setLanguage("en")
        XCTAssertEqual(BlockCardState.of(block: block, activeProgram: program, programs: [program], weekKey: "2026-W46", unlocked: true),
                       .active(block, week: 2, target: 2, ready: true))
        XCTAssertEqual(BlockFormat.reasons(block.weeks[1].changes[0].reasons), "Recovered early, low pump")
        XCTAssertEqual(BlockFormat.targets(length: 4, scale: .rir), "RIR\u{00A0}3 · RIR\u{00A0}2 · RIR\u{00A0}1 · Deload")
        XCTAssertEqual(BlockCardState.of(block: block, activeProgram: program, programs: [program], weekKey: "2026-W50", unlocked: true), .complete(block))
        XCTAssertEqual(BlockCardState.of(block: block, activeProgram: program, programs: [program], weekKey: "2026-W44", unlocked: true), .upcoming(block))
        XCTAssertEqual(BlockCardState.of(block: block, activeProgram: program, programs: [program], weekKey: "2026-W46", unlocked: false), .locked)
        // Every Method card has its words in every language: no key falls back to its name.
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for key in ["method.title", "method.open", "method.sources"] + ["principle", "rir", "adjust", "blocks", "strength", "readiness"]
                .flatMap({ ["method.\($0)Title", "method.\($0)Text"] }) {
                XCTAssertNotEqual(LanguageManager.t(key), key, "\(language) \(key)")
            }
        }
        LanguageManager.setLanguage("en")
        XCTAssertEqual(BlockSheet.method.id, "method")

        let sets = [ExerciseSetLog(id: "s1", setNumber: 1, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true, inputTouched: true, rir: 2),
                    ExerciseSetLog(id: "s2", setNumber: 2, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true, inputTouched: true)]
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for (width, size, label) in [(CGFloat(393), ContentSizeCategory.large, "393"), (320, .extraExtraExtraLarge, "320")] {
                let page = { (content: AnyView) in
                    ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(20) }.background(AppColors.surface)
                }
                try render(VStack(spacing: 12) {
                    TrainingBlockCard(state: .of(block: block, activeProgram: program, programs: [program], weekKey: "2026-W46", unlocked: true),
                                      scale: .rir, onStart: {}, onReview: { _ in }, onSummary: {}, onEnd: {}, onLocked: {})
                    SetLoggingTable(sets: sets, prescription: "2 × 8–12", onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in },
                                    onAddSet: {}, onRemoveSet: { _ in }, effort: EffortActions(scale: .rir) { _, _ in }, prescriptionSuffix: "RIR 2",
                                    ratings: AnyView(BlockFeedbackCard(muscles: ["chest"], answers: [:], questions: .pumpAndWorkload) { _, _ in }))
                    BlockFeedbackCard(muscles: ["side-delts"], answers: [:], questions: .soreness) { _, _ in }
                    // The folded rows: a waiting choice, a partly answered block, and an answered check.
                    QuestionPrompts(prompts: [.readiness(ReadinessCheck(sleep: "poor", energy: "low")),
                                              .soreness(["chest", "side-delts"], answers: ["chest": MuscleFeedback(soreness: "healed_early")])]) { _ in }
                    QuestionPrompts(prompts: [.readiness(ReadinessCheck(sleep: "good", energy: "high", soreness: "none"))]) { _ in }
                    ReadinessCard(check: ReadinessCheck(sleep: "poor", energy: "low"), options: Readiness.options(blockTarget: 2, deload: false),
                                  lighterTarget: nil, onAnswer: { _ in }, onChoose: { _ in })
                }.padding(.horizontal, 20).padding(.vertical, 16).background(AppColors.background),
                    width: width, size: size, height: size == .large ? 2000 : 2700, name: "block-card-\(language)-\(label)")
                for (state, strength, focus) in [("", false, false), ("-focus", false, true), ("-strength", true, false)] {
                    try render(page(AnyView(TrainingBlockSetupContent(program: program, scale: .rir, replacesBlock: true, onStart: { _, _, _ in },
                                                                      readinessCheck: .constant(true), opensOnStrength: strength, opensFocus: focus))),
                               width: width, size: size, height: size == .large ? 1100 : 1900, name: "block-setup\(state)-\(language)-\(label)")
                }
                try render(page(AnyView(TrainingBlockWeekContent(block: block, week: 2, program: program, scale: .rpe) { _ in })),
                           width: width, size: size, height: size == .large ? 900 : 1500, name: "block-week-\(language)-\(label)")
                try render(page(AnyView(TrainingBlockWeekContent(block: block, week: 2, program: program, scale: .rpe, onStartWeek: { _ in },
                                                                 opensEditing: true))),
                           width: width, size: size, height: size == .large ? 1100 : 1900, name: "block-week-edit-\(language)-\(label)")
                try render(page(AnyView(TrainingBlockSummaryContent(block: block, program: program, history: [record], weightUnit: .kg,
                                                                    onStartAnother: {}, onDone: {}))),
                           width: width, size: size, height: size == .large ? 900 : 1500, name: "block-summary-\(language)-\(label)")
                // Five full weeks: sets rise, the raise eases off, and the deload halves them.
                var full = block
                full.weeks = (0..<5).map { week in
                    TrainingBlockWeek(sets: block.weeks[0].sets.mapValues { sets in sets })
                }
                for week in 0..<5 {
                    for key in full.weeks[week].sets.keys {
                        let sets = block.weeks[0].sets[key] ?? 0
                        full.weeks[week].sets[key] = week == 4 ? (sets + 1) / 2 : key.contains("raise") ? sets - week / 2 : sets + week / 2 + week % 2
                    }
                }
                try render(page(AnyView(TrainingBlockSummaryContent(block: full, program: program, history: [record], weightUnit: .kg,
                                                                    onStartAnother: {}, onDone: {}))),
                           width: width, size: size, height: size == .large ? 900 : 1500, name: "block-summary-full-\(language)-\(label)")
                try render(page(AnyView(TrainingBlockMethodContent())),
                           width: width, size: size, height: size == .large ? 2200 : 2700, name: "block-method-\(language)-\(label)")
                try render(page(AnyView(TrainingBlockWeekContent(block: strengthBlock, week: 4, program: program, scale: .rir) { _ in })),
                           width: width, size: size, height: size == .large ? 900 : 1500, name: "block-strength-week-\(language)-\(label)")
                try render(page(AnyView(TrainingBlockSummaryContent(block: strengthBlock, program: program, history: [strengthRecord], weightUnit: .kg,
                                                                    onStartAnother: {}, onDone: {}))),
                           width: width, size: size, height: size == .large ? 900 : 1500, name: "block-strength-summary-\(language)-\(label)")
            }
        }
    }
}
