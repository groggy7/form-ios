import Foundation

/// Projects the active draft into the display-ready snapshot the watch shows (docs/apple-watch.md).
enum WatchSnapshotBuilder {
    static func build(
        draft: ActiveSessionDraft?,
        unit: WeightUnit,
        language: String,
        isPremium: Bool,
        steps: ProgressionLoadSteps,
        recordsWorkouts: Bool = false,
        finished: WatchSnapshot.Finished? = nil,
        now: Int64
    ) -> WatchSnapshot {
        WatchSnapshot(
            revision: now,
            language: language,
            access: isPremium ? .premium : .locked,
            session: isPremium ? draft.map { session($0, unit: unit, steps: steps, now: now) } : nil,
            recordsWorkouts: recordsWorkouts,
            // Sent even while locked: it only tells the watch how to end a Health workout it is recording.
            finished: finished
        )
    }

    /// How a workout that left the iPhone ended. It was saved when its history record appeared or changed
    /// while it ran; a resumed workout that is discarded leaves its earlier record untouched.
    static func finished(sessionId: String, recordAtStart: WorkoutSessionRecord?, history: [WorkoutSessionRecord],
                         now: Int64) -> WatchSnapshot.Finished {
        let record = history.first { $0.id == sessionId }
        let saved = record != nil && record != recordAtStart
        let completedAt = saved ? WorkoutCalendar.parseIsoTimestamp(record?.completedAt).map { Int64($0.timeIntervalSince1970 * 1000) } : nil
        return WatchSnapshot.Finished(sessionId: sessionId, saved: saved, endedAt: min(now, completedAt ?? now))
    }

    /// The marker once `openedId` opens: a workout resumed from History keeps its ID and has not finished any more.
    /// Kept, its old marker would end the new watch recording at once.
    static func stillFinished(_ marker: WatchSnapshot.Finished?, openedId: String) -> WatchSnapshot.Finished? {
        marker?.sessionId == openedId ? nil : marker
    }

    private static func session(_ draft: ActiveSessionDraft, unit: WeightUnit, steps: ProgressionLoadSteps, now: Int64) -> WatchSnapshot.Session {
        let exercises = draft.workout.exercises
        return WatchSnapshot.Session(
            id: draft.id,
            title: draft.workout.displayTitle(programId: draft.programId),
            unit: unit.rawValue,
            exercises: exercises.map { exercise($0, in: draft, unit: unit, steps: steps, now: now) },
            currentIndex: min(max(0, draft.currentExerciseIndex), max(0, exercises.count - 1)),
            nextIndex: Supersets.nextIndex(draft),
            rest: rest(draft, now: now),
            allLogged: WorkoutSessionUtils.isComplete(draft: draft)
        )
    }

    private static func exercise(_ exercise: Exercise, in draft: ActiveSessionDraft, unit: WeightUnit,
                                 steps: ProgressionLoadSteps, now: Int64) -> WatchSnapshot.Exercise {
        let sets = draft.setsByExercise[exercise.id] ?? []
        let suggested = exercise.reps.flatMap { $0.toFailure ? nil : $0.min }
        let rows = sets.enumerated().map { index, set -> WatchSnapshot.SetRow in
            let reps = set.isCompleted ? set.completedReps ?? Int(set.repsInput) : Int(set.repsInput)
            return WatchSnapshot.SetRow(
                id: set.id,
                number: set.setNumber,
                isWarmup: set.isWarmup,
                load: load(set),
                reps: reps,
                suggestedReps: set.targetReps ?? suggested,
                isCompleted: set.isCompleted,
                hasParts: set.technique != nil || set.partialRepsInput != nil || !(set.extensions ?? []).isEmpty,
                restAfter: set.isCompleted ? nil : restAfter(completing: index, of: exercise, in: draft, now: now)
            )
        }
        return WatchSnapshot.Exercise(
            id: exercise.id,
            name: exercise.displayName,
            label: Supersets.label(draft.workout, exercise.id),
            sets: rows,
            loadStep: loadStep(exercise, unit: unit, steps: steps),
            allowsZeroLoad: WorkoutSessionUtils.allowsZeroWeight(exercise),
            isBodyweight: WorkoutSessionUtils.usesBodyweightResistance(exercise),
            isAssisted: WorkoutSessionUtils.isAssisted(exercise)
        )
    }

    /// The text the user typed, which is already in the session unit.
    private static func load(_ set: ExerciseSetLog) -> Double? {
        let text = set.weightInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Double(text).flatMap { $0.isFinite ? $0 : nil }
    }

    /// Asks the iPhone's own rule, so supersets and the workout's last set start no rest here either.
    private static func restAfter(completing index: Int, of exercise: Exercise, in draft: ActiveSessionDraft, now: Int64) -> Int? {
        guard var sets = draft.setsByExercise[exercise.id], sets.indices.contains(index) else { return nil }
        sets[index].isCompleted = true
        var probe = draft
        probe.setsByExercise[exercise.id] = sets
        return RestTimerUtils.afterCompletingSet(in: probe, exercise: exercise, setId: sets[index].id, nowEpochMillis: now)?.totalSeconds
    }

    private static func rest(_ draft: ActiveSessionDraft, now: Int64) -> WatchSnapshot.Rest? {
        guard let rest = draft.restTimer else { return nil }
        let remaining = rest.secondsRemaining(nowEpochMillis: now)
        guard remaining > 0 else { return nil }
        // A draft saved paused by an earlier version holds its rest, as the Live Activity shows it.
        let running = rest.isRunning && !draft.isPaused && rest.endsAtEpochMillis != nil
        return WatchSnapshot.Rest(
            setId: rest.setId,
            exerciseName: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: rest.exerciseName),
            totalSeconds: max(rest.totalSeconds, remaining),
            endsAt: running ? rest.endsAtEpochMillis : nil,
            pausedRemaining: running ? 0 : remaining,
            isRunning: running
        )
    }

    /// One crown step: the Smart Progression steps where `ProgressionEngine.loadStep` has one, and a
    /// plain 1 kg or 2.5 lb elsewhere, since the crown needs a step even where the coach must not invent one.
    static func loadStep(_ exercise: Exercise, unit: WeightUnit, steps: ProgressionLoadSteps) -> Double {
        let fallback = unit == .lbs ? 2.5 : 1
        if WorkoutSessionUtils.isAssisted(exercise) { return steps.machine(unit) }
        if WorkoutSessionUtils.usesBodyweightResistance(exercise) { return steps.bodyweight(unit) }
        let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) ?? ExerciseCatalog.key(exercise.name)
        switch EquipmentCatalog.shared.categoryId(id) {
        case "bar": return steps.bar(unit) ?? fallback
        case "dumbbell": return steps.dumbbell(unit)
        case "machine": return steps.machine(unit)
        default: return fallback
        }
    }
}
