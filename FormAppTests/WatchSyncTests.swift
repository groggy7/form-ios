import XCTest
@testable import FormApp

final class WatchSyncTests: XCTestCase {
    private let now: Int64 = 1_800_000_000_000
    private let steps = ProgressionLoadSteps(dumbbellKg: 2, machineKg: 5, smallestPlateKg: 1.25)

    private func draft() -> ActiveSessionDraft {
        let exercises = [
            Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 2,
                     reps: RepTarget(min: 6, max: 8), restSeconds: 120),
            Exercise(id: "curl", name: "Curl", exerciseId: "dumbbell-hammer-curl", sets: 1, restSeconds: 60, supersetId: "pair"),
            Exercise(id: "push", name: "Triceps Pushdown", sets: 1, restSeconds: 90, supersetId: "pair")
        ]
        let sets: [String: [ExerciseSetLog]] = [
            "bench": [ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "40", repsInput: "10", weightKg: 40, completedReps: 10,
                                     isCompleted: true, isWarmup: true),
                      ExerciseSetLog(id: "b1", setNumber: 1, weightInput: "80", repsInput: "8", weightKg: 80, completedReps: 8, isCompleted: true),
                      ExerciseSetLog(id: "b2", setNumber: 2, targetReps: 7)],
            "curl": [ExerciseSetLog(id: "c1", setNumber: 1, weightInput: "14", repsInput: "12", weightKg: 14, completedReps: 12)],
            "push": [ExerciseSetLog(id: "p1", setNumber: 1, weightInput: "30", repsInput: "12", weightKg: 30, completedReps: 12)]
        ]
        return ActiveSessionDraft(id: "s", programId: "p", workout: Workout(id: "w", day: 1, title: "Push", exercises: exercises),
                                  startedAt: "2026-10-31T10:00:00Z", startedAtEpochMillis: now - 600_000, setsByExercise: sets)
    }

    private func snapshot(_ draft: ActiveSessionDraft?, premium: Bool = true, unit: WeightUnit = .kg) -> WatchSnapshot {
        WatchSnapshotBuilder.build(draft: draft, unit: unit, language: "en", isPremium: premium, steps: steps, now: now)
    }

    private func command(_ kind: WatchCommand.Kind, exercise: String? = "bench", set: String? = nil,
                         load: Double? = nil, unit: String? = "kg", reps: Int? = nil) -> WatchCommand {
        WatchCommand(kind: kind, sessionId: "s", exerciseId: exercise, setId: set, load: load, unit: unit, reps: reps, sentAt: now)
    }

    private func apply(_ command: WatchCommand, to draft: ActiveSessionDraft, unit: WeightUnit = .kg) -> ActiveSessionDraft? {
        WatchCommandHandler.apply(command, to: draft, unit: unit, prefillNextSet: true, now: now)
    }

    // MARK: Snapshot

    func testSnapshotShowsTheCurrentExerciseSetsAndTheRestEachSetWouldStart() throws {
        let session = try XCTUnwrap(snapshot(draft()).session)
        XCTAssertEqual(session.title, "Push")
        XCTAssertEqual(session.unit, "kg")
        XCTAssertEqual(session.exercises.map(\.label), [nil, "A1", "A2"])
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.nextIndex, 1)
        XCTAssertFalse(session.allLogged)
        let bench = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(bench.loadStep, 2.5, "Two of the smallest plate")
        XCTAssertEqual(bench.sets.map(\.id), ["w1", "b1", "b2"])
        XCTAssertEqual(bench.sets[0].isWarmup, true)
        XCTAssertEqual(bench.sets[1].load, 80)
        XCTAssertEqual(bench.sets[1].restAfter, nil, "A completed set starts nothing")
        XCTAssertEqual(bench.sets[2].load, nil)
        XCTAssertEqual(bench.sets[2].reps, nil)
        XCTAssertEqual(bench.sets[2].suggestedReps, 7, "The coach's target comes before the prescription")
        XCTAssertEqual(bench.sets[2].restAfter, 120)
    }

    func testTheFirstSupersetHalfStartsNoRestAndTheLastSetOfTheWorkoutStartsNone() throws {
        var paired = draft()
        let curl = try XCTUnwrap(snapshot(paired).session?.exercises[1])
        XCTAssertEqual(curl.sets.first?.restAfter, nil, "A1 defers rest to A2")
        XCTAssertEqual(curl.loadStep, 2, "The dumbbell step")
        XCTAssertEqual(snapshot(paired).session?.exercises[2].sets.first?.restAfter, 90, "A2 rests while the workout continues")
        paired.setsByExercise["bench"]![2] = ExerciseSetLog(id: "b2", setNumber: 2, weightInput: "80", repsInput: "7", weightKg: 80,
                                                           completedReps: 7, isCompleted: true)
        paired.setsByExercise["curl"]![0].isCompleted = true
        XCTAssertEqual(snapshot(paired).session?.exercises[2].sets.first?.restAfter, nil, "Nothing rests after the workout's last set")
    }

    func testLockedOrIdleSnapshotsCarryNoWorkout() {
        XCTAssertEqual(snapshot(draft(), premium: false).access, .locked)
        XCTAssertNil(snapshot(draft(), premium: false).session)
        XCTAssertEqual(snapshot(nil).access, .premium)
        XCTAssertNil(snapshot(nil).session)
    }

    func testSnapshotRestMirrorsRunningAndPausedRests() throws {
        var resting = draft()
        resting.restTimer = RestTimerState(exerciseName: "Barbell Bench Press", totalSeconds: 120, isRunning: true,
                                           endsAtEpochMillis: now + 90_000, pausedSecondsRemaining: 120, setId: "b1")
        let running = try XCTUnwrap(snapshot(resting).session?.rest)
        XCTAssertEqual(running.setId, "b1")
        XCTAssertEqual(running.endsAt, now + 90_000)
        XCTAssertEqual(running.secondsRemaining(now: now), 90)
        resting.restTimer = resting.restTimer?.paused(nowEpochMillis: now)
        let paused = try XCTUnwrap(snapshot(resting).session?.rest)
        XCTAssertFalse(paused.isRunning)
        XCTAssertEqual(paused.secondsRemaining(now: now + 60_000), 90)
        resting.restTimer = RestTimerState(exerciseName: "Bench", totalSeconds: 60, isRunning: true, endsAtEpochMillis: now - 1)
        XCTAssertNil(snapshot(resting).session?.rest, "An ended rest is not shown")
    }

    func testSnapshotAndCommandSurviveTheWatchConnectivityEncoding() throws {
        let original = snapshot(draft())
        let data = try XCTUnwrap(WatchSync.encoded(original))
        XCTAssertEqual(WatchSync.decoded(WatchSnapshot.self, from: data), original)
        let sent = command(.completeSet, set: "b2", load: 82.5, reps: 7)
        XCTAssertEqual(WatchSync.decoded(WatchCommand.self, from: WatchSync.encoded(sent)), sent)
        XCTAssertNil(WatchSync.decoded(WatchCommand.self, from: Data(#"{"id":"x","kind":"teleport","sentAt":1}"#.utf8)),
                     "A newer watch's unknown command is ignored")
    }

    // MARK: Commands

    func testCompletingASetLogsTheWatchValuesAndStartsTheRest() throws {
        let done = try XCTUnwrap(apply(command(.completeSet, set: "b2", load: 82.5, reps: 7), to: draft()))
        let set = try XCTUnwrap(done.setsByExercise["bench"]?[2])
        XCTAssertTrue(set.isCompleted)
        XCTAssertEqual(set.weightInput, "82.5")
        XCTAssertEqual(set.weightKg, 82.5)
        XCTAssertEqual(set.completedReps, 7)
        XCTAssertEqual(done.restTimer?.setId, "b2")
        XCTAssertEqual(done.restTimer?.endsAtEpochMillis, now + 120_000)
        XCTAssertNil(apply(command(.completeSet, set: "b2", load: 82.5, reps: 7), to: done), "A repeated command changes nothing")
    }

    func testCompletingConvertsALoadSentInTheOtherUnit() throws {
        let done = try XCTUnwrap(apply(command(.completeSet, set: "b2", load: 185, unit: "lbs", reps: 7), to: draft()))
        let set = try XCTUnwrap(done.setsByExercise["bench"]?[2])
        XCTAssertEqual(set.weightInput, WorkoutSessionUtils.formatWeightInput(WeightUnit.lbs.toCanonicalKg(185), unit: .kg, barbell: true))
        XCTAssertTrue(set.isCompleted)
    }

    func testInvalidStaleOrOutOfOrderCompletionsAreIgnored() {
        let open = draft()
        XCTAssertNil(apply(command(.completeSet, set: "b2", load: 82.5), to: open), "No reps entered or sent")
        XCTAssertNil(apply(command(.completeSet, set: "b2", load: 1_501, reps: 5), to: open), "Above the maximum load")
        XCTAssertNil(apply(command(.completeSet, set: "missing", load: 80, reps: 5), to: open))
        var other = command(.completeSet, set: "b2", load: 80, reps: 5)
        other.sessionId = "another-workout"
        XCTAssertNil(apply(other, to: open))
        var gap = open
        gap.setsByExercise["bench"]![1].isCompleted = false
        XCTAssertNil(apply(command(.completeSet, set: "b2", load: 80, reps: 5), to: gap), "Earlier sets come first, as on the iPhone")
        XCTAssertNil(apply(command(.completeSet, exercise: "curl", set: "b2", load: 80, reps: 5), to: open), "The set belongs to another exercise")
    }

    func testUndoReopensTheSetAndCancelsItsRest() throws {
        let done = try XCTUnwrap(apply(command(.completeSet, set: "b2", load: 82.5, reps: 7), to: draft()))
        let undone = try XCTUnwrap(apply(command(.undoSet, set: "b2"), to: done))
        XCTAssertEqual(undone.setsByExercise["bench"]?[2].isCompleted, false)
        XCTAssertNil(undone.restTimer)
        XCTAssertNil(apply(command(.undoSet, set: "b2"), to: undone))
    }

    func testSelectingAnExerciseMovesTheIphone() {
        XCTAssertEqual(apply(command(.selectExercise, exercise: "push"), to: draft())?.currentExerciseIndex, 2)
        XCTAssertNil(apply(command(.selectExercise, exercise: "bench"), to: draft()), "Already current")
        XCTAssertNil(apply(command(.selectExercise, exercise: "gone"), to: draft()))
    }

    func testRestCommandsOnlyChangeTheRestTheWatchSaw() throws {
        var resting = draft()
        resting.restTimer = RestTimerState(exerciseName: "Bench", totalSeconds: 120, isRunning: true,
                                           endsAtEpochMillis: now + 90_000, pausedSecondsRemaining: 120, setId: "b1")
        let paused = try XCTUnwrap(apply(command(.pauseRest, set: "b1"), to: resting))
        XCTAssertEqual(paused.restTimer?.isRunning, false)
        XCTAssertEqual(paused.restTimer?.pausedSecondsRemaining, 90)
        XCTAssertNil(apply(command(.pauseRest, set: "b1"), to: paused), "Pause is not a toggle")
        let resumed = try XCTUnwrap(apply(command(.resumeRest, set: "b1"), to: paused))
        XCTAssertEqual(resumed.restTimer?.endsAtEpochMillis, now + 90_000)
        var longer = command(.addRest, set: "b1")
        longer.seconds = 30
        XCTAssertEqual(apply(longer, to: resting)?.restTimer?.endsAtEpochMillis, now + 120_000)
        XCTAssertNil(try XCTUnwrap(apply(command(.skipRest, set: "b1"), to: resting)).restTimer)
        XCTAssertNil(apply(command(.skipRest, set: "b2"), to: resting), "A different rest")
        XCTAssertNil(apply(command(.skipRest, set: "b1"), to: draft()), "No rest")
    }

    func testRestTransitionsMatchTheWorkoutScreen() {
        let rest = RestTimerState(exerciseName: "Bench", totalSeconds: 60, isRunning: true, endsAtEpochMillis: now + 20_000)
        XCTAssertEqual(rest.adjusted(by: 30, nowEpochMillis: now).totalSeconds, 60, "50 s remain, within the original total")
        XCTAssertEqual(rest.adjusted(by: 60, nowEpochMillis: now).totalSeconds, 80)
        let stopped = rest.adjusted(by: -30, nowEpochMillis: now)
        XCTAssertFalse(stopped.isRunning)
        XCTAssertEqual(stopped.pausedSecondsRemaining, 0)
        XCTAssertEqual(stopped.resumed(nowEpochMillis: now), stopped, "A finished rest does not restart")
    }
}
