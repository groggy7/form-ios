import Foundation

/// Applies a watch command to the active draft with the workout screen's own transitions (docs/apple-watch.md).
/// Returns nil when the command does not apply: another workout, a missing or already-changed set,
/// a rest the watch no longer sees, or a value the iPhone would not accept.
enum WatchCommandHandler {
    static func apply(_ command: WatchCommand, to draft: ActiveSessionDraft, unit: WeightUnit,
                      prefillNextSet: Bool, now: Int64) -> ActiveSessionDraft? {
        guard command.sessionId == draft.id else { return nil }
        switch command.kind {
        case .completeSet: return completeSet(command, in: draft, unit: unit, prefillNextSet: prefillNextSet, now: now)
        case .undoSet:
            guard let (exercise, index) = locate(command, in: draft), draft.setsByExercise[exercise.id]?[index].isCompleted == true else { return nil }
            return changed(WorkoutSessionUtils.toggledSet(draft, exerciseId: exercise.id, index: index,
                                                          prefillNextSet: prefillNextSet, unit: unit, now: now), from: draft)
        case .selectExercise:
            guard let index = draft.workout.exercises.firstIndex(where: { $0.id == command.exerciseId }),
                  index != draft.currentExerciseIndex else { return nil }
            var copy = draft
            copy.currentExerciseIndex = index
            return copy
        case .pauseRest, .resumeRest, .addRest, .skipRest:
            guard let rest = draft.restTimer, rest.setId == command.setId, rest.secondsRemaining(nowEpochMillis: now) > 0 else { return nil }
            var copy = draft
            switch command.kind {
            case .pauseRest: copy.restTimer = rest.paused(nowEpochMillis: now)
            case .resumeRest: copy.restTimer = rest.resumed(nowEpochMillis: now)
            case .addRest: copy.restTimer = rest.adjusted(by: command.seconds ?? 30, nowEpochMillis: now)
            default: copy.restTimer = nil
            }
            return changed(copy, from: draft)
        case .refresh: return nil
        }
    }

    private static func completeSet(_ command: WatchCommand, in draft: ActiveSessionDraft, unit: WeightUnit,
                                    prefillNextSet: Bool, now: Int64) -> ActiveSessionDraft? {
        guard let (exercise, index) = locate(command, in: draft), var sets = draft.setsByExercise[exercise.id],
              !sets[index].isCompleted else { return nil }
        if command.load != nil || command.reps != nil {
            let set = sets[index]
            let weight = command.load.map { weightInput($0, from: command.unit, to: unit, exercise: exercise) } ?? set.weightInput
            guard let weight, let reps = WorkoutSessionUtils.sanitizedRepsInput(command.reps.map(String.init) ?? set.repsInput) else { return nil }
            sets[index] = WorkoutSessionUtils.editedSet(set, weight: weight, reps: reps, exercise: exercise, unit: unit)
        }
        var edited = draft
        edited.setsByExercise[exercise.id] = sets
        let toggled = WorkoutSessionUtils.toggledSet(edited, exerciseId: exercise.id, index: index,
                                                     prefillNextSet: prefillNextSet, unit: unit, now: now)
        // An invalid or out-of-order set stays open on the iPhone, so the edit is not kept either.
        return toggled.setsByExercise[exercise.id]?[index].isCompleted == true ? toggled : nil
    }

    private static func locate(_ command: WatchCommand, in draft: ActiveSessionDraft) -> (Exercise, Int)? {
        guard let exercise = draft.workout.exercises.first(where: { $0.id == command.exerciseId }),
              let index = draft.setsByExercise[exercise.id]?.firstIndex(where: { $0.id == command.setId }) else { return nil }
        return (exercise, index)
    }

    /// The watch's display-unit load as set text in the iPhone's current unit; nil when it is not a valid load.
    private static func weightInput(_ load: Double, from code: String?, to unit: WeightUnit, exercise: Exercise) -> String? {
        let source = code.flatMap(WeightUnit.init(rawValue:)) ?? unit
        guard load.isFinite, load >= 0, load <= WorkoutSessionUtils.maxAllowedWeight(unit: source) else { return nil }
        let text: String
        if source == unit {
            let rounded = (load * 100).rounded() / 100
            text = rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(rounded)
        } else {
            text = WorkoutSessionUtils.formatWeightInput(source.toCanonicalKg(load), unit: unit,
                                                         barbell: WorkoutSessionUtils.usesBarbellPlates(exercise))
        }
        return WorkoutSessionUtils.sanitizedWeightInput(text, unit: unit)
    }

    private static func changed(_ draft: ActiveSessionDraft, from original: ActiveSessionDraft) -> ActiveSessionDraft? {
        draft == original ? nil : draft
    }
}
