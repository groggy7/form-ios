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

    func testUpNextFollowsTheIphonesOrderWithItsPrefill() throws {
        let session = try XCTUnwrap(snapshot(draft()).session)
        let next = try XCTUnwrap(session.upNext)
        XCTAssertEqual(next.set.id, "b2")
        XCTAssertEqual(next.load, 80, "The previous set's load")
        XCTAssertEqual(next.reps, 7, "The coach's target before the previous set's reps")
        var paired = draft()
        paired.setsByExercise["bench"]![2] = ExerciseSetLog(id: "b2", setNumber: 2, weightInput: "80", repsInput: "7", weightKg: 80,
                                                           completedReps: 7, isCompleted: true)
        paired.currentExerciseIndex = 2
        paired.setsByExercise["push"]![0].isCompleted = true
        XCTAssertEqual(snapshot(paired).session?.upNext?.set.id, "c1", "The pending superset partner comes first")
        paired.setsByExercise["curl"]![0].isCompleted = true
        XCTAssertNil(snapshot(paired).session?.upNext, "Every set is logged")
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

    // MARK: Apple Health workout (phase 2)

    private func record(completedAt: String, sets: Int = 1) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: "s", programId: "p", workoutId: "w", workoutTitle: "Push", startedAt: "2026-10-31T10:00:00.000Z",
                             completedAt: completedAt, durationSeconds: 1800, totalCompletedSets: sets)
    }

    func testFinishedMarkerTellsASaveFromADiscard() {
        let saved = record(completedAt: "2026-10-31T10:30:00.000Z")
        let savedAt = Int64(WorkoutCalendar.parseIsoTimestamp(saved.completedAt)!.timeIntervalSince1970 * 1000)
        XCTAssertEqual(WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: nil, history: [saved], now: now),
                       WatchSnapshot.Finished(sessionId: "s", saved: true, endedAt: savedAt))
        XCTAssertEqual(WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: nil, history: [], now: now),
                       WatchSnapshot.Finished(sessionId: "s", saved: false, endedAt: now), "Discarded")
        XCTAssertFalse(WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: saved, history: [saved], now: now).saved,
                       "A resumed workout that is discarded leaves its earlier record")
        XCTAssertTrue(WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: saved, history: [record(completedAt: "2026-10-31T11:00:00.000Z", sets: 2)],
                                                    now: now).saved, "Saving a resumed workout changes its record")
        let future = record(completedAt: "2099-01-01T00:00:00.000Z")
        XCTAssertEqual(WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: nil, history: [future], now: now).endedAt, now)
    }

    func testWorkoutPlanStartsAdoptsAndEndsWithTheIphoneWorkout() {
        let active = WatchSnapshotBuilder.build(draft: draft(), unit: .kg, language: "en", isPremium: true, steps: steps,
                                                recordsWorkouts: true, now: now)
        XCTAssertEqual(active.workoutStep(running: nil, skipped: []), .start(sessionId: "s"))
        var off = active
        off.recordsWorkouts = false
        XCTAssertNil(off.workoutStep(running: nil, skipped: []), "The iPhone setting is off")
        XCTAssertNil(snapshot(draft(), premium: false).workoutStep(running: nil, skipped: []), "Locked")
        XCTAssertNil(active.workoutStep(running: nil, skipped: ["s"]), "Health access was declined for it")

        let launched = RunningWorkout(sessionId: nil, startedAt: now)
        XCTAssertEqual(active.workoutStep(running: launched, skipped: []), .adopt(sessionId: "s"))
        var idle = WatchSnapshotBuilder.build(draft: nil, unit: .kg, language: "en", isPremium: true, steps: steps, recordsWorkouts: true,
                                              finished: WatchSnapshot.Finished(sessionId: "old", saved: true, endedAt: now - 60_000), now: now)
        XCTAssertNil(idle.workoutStep(running: launched, skipped: []), "Waits for its workout; an older one's end is not its own")
        idle.finished = WatchSnapshot.Finished(sessionId: "quick", saved: false, endedAt: now + 5_000)
        XCTAssertEqual(idle.workoutStep(running: launched, skipped: []), .finish(save: false, endedAt: now + 5_000),
                       "Discarded before its first snapshot arrived")

        let recording = RunningWorkout(sessionId: "s", startedAt: now)
        XCTAssertNil(active.workoutStep(running: recording, skipped: []))
        var done = idle
        done.finished = WatchSnapshot.Finished(sessionId: "s", saved: true, endedAt: now + 1_800_000)
        XCTAssertEqual(done.workoutStep(running: recording, skipped: []), .finish(save: true, endedAt: now + 1_800_000))
        done.finished = nil
        XCTAssertEqual(done.workoutStep(running: recording, skipped: []), .finish(save: false, endedAt: nil),
                       "Its workout vanished without word from the iPhone")
        XCTAssertEqual(snapshot(draft(), premium: false).workoutStep(running: recording, skipped: []), .finish(save: false, endedAt: nil))
        var next = active
        next.finished = WatchSnapshot.Finished(sessionId: "s", saved: true, endedAt: now)
        XCTAssertNil(next.workoutStep(running: nil, skipped: []), "A workout that already ended is not started again")
    }

    func testLosingRecordingAccessDiscardsEvenAnUnadoptedWorkout() {
        let active = WatchSnapshotBuilder.build(draft: draft(), unit: .kg, language: "en", isPremium: true,
                                                steps: steps, recordsWorkouts: true, now: now)
        var locked = active
        locked.access = .locked
        locked.session = nil
        var staleLocked = active
        staleLocked.access = .locked
        var disabled = active
        disabled.recordsWorkouts = false
        for running in [RunningWorkout(sessionId: nil, startedAt: now), RunningWorkout(sessionId: "s", startedAt: now)] {
            for blocked in [locked, staleLocked, disabled] {
                XCTAssertEqual(blocked.workoutStep(running: running, skipped: []), .finish(save: false, endedAt: nil))
                XCTAssertNil(blocked.workoutStep(running: nil, skipped: []))
            }
        }
        locked.finished = WatchSnapshot.Finished(sessionId: "s", saved: true, endedAt: now + 1_000)
        XCTAssertEqual(locked.workoutStep(running: RunningWorkout(sessionId: "s", startedAt: now), skipped: []),
                       .finish(save: true, endedAt: now + 1_000), "A completed paid workout can still finish after entitlement changes")
    }

    func testAWorkoutResumedFromHistoryKeepsItsNewRecording() {
        let marker = WatchSnapshotBuilder.finished(sessionId: "s", recordAtStart: nil,
                                                   history: [record(completedAt: "2026-10-31T10:30:00.000Z")], now: now)
        func resumed(_ finished: WatchSnapshot.Finished?) -> WatchSnapshot {
            WatchSnapshotBuilder.build(draft: draft(), unit: .kg, language: "en", isPremium: true, steps: steps,
                                       recordsWorkouts: true, finished: finished, now: now)
        }
        let opened = RunningWorkout(sessionId: nil, startedAt: now - 5_000)
        let adopted = RunningWorkout(sessionId: "s", startedAt: now - 5_000)
        XCTAssertEqual(resumed(marker).workoutStep(running: adopted, skipped: []), .finish(save: true, endedAt: marker.endedAt),
                       "The old marker would end the new recording")
        let cleared = resumed(WatchSnapshotBuilder.stillFinished(marker, openedId: "s"))
        XCTAssertEqual(cleared.workoutStep(running: opened, skipped: []), .adopt(sessionId: "s"))
        XCTAssertNil(cleared.workoutStep(running: adopted, skipped: []), "Keeps recording")
        XCTAssertEqual(cleared.workoutStep(running: nil, skipped: []), .start(sessionId: "s"))
        XCTAssertEqual(WatchSnapshotBuilder.stillFinished(marker, openedId: "other"), marker, "Another workout's marker stays")
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
