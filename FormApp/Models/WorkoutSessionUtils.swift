import Foundation

public enum RestTimerUtils {
    public static let restPresets: [Int] = [60, 90, 120, 180, 240]

    /// Evaluate the latest draft after logging the set, independent of exercise order.
    public static func afterCompletingSet(in draft: ActiveSessionDraft, exercise: Exercise, setId: String? = nil, nowEpochMillis: Int64) -> RestTimerState? {
        guard !WorkoutSessionUtils.isComplete(draft: draft), !Supersets.defersRest(draft, exerciseId: exercise.id, setId: setId) else { return nil }
        let seconds = restSeconds(for: exercise)
        guard seconds > 0 else { return nil }
        return RestTimerState(
            exerciseName: exercise.name,
            totalSeconds: seconds,
            isRunning: true,
            endsAtEpochMillis: nowEpochMillis + Int64(seconds) * 1000,
            pausedSecondsRemaining: seconds,
            setId: setId
        )
    }

    public static func formatSecondsToTime(_ totalSeconds: Int) -> String {
        let clamped = max(0, totalSeconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    public static func restSeconds(for exercise: Exercise) -> Int {
        if let explicit = exercise.restSeconds {
            return explicit
        }
        let type = exercise.resolvedMovement
        let name = exercise.name.lowercased()

        if type == .squat || type == .hinge ||
            (type == .press && (name.contains("barbell") || name.contains("bench") || name.contains("overhead"))) ||
            (type == .row && name.contains("barbell")) {
            return 180
        }

        let isSecondaryCompound = (type == .lunge) || (type == .pullUp) ||
            (type == .row && (name.contains("dumbbell") || name.contains("cable"))) ||
            (type == .press && (name.contains("incline") || name.contains("dumbbell") || name.contains("floor") || name.contains("push-up")))

        return isSecondaryCompound ? 120 : 90
    }
}

public struct SessionProgress {
    public var durationSeconds: Int
    public var completedSets: Int
    public var volumeKg: Double
    public var exerciseLogs: [SessionExerciseLog]
    public var hasProgress: Bool

    public static func from(draft: ActiveSessionDraft, nowEpochMillis: Int64) -> SessionProgress {
        let allSets = draft.setsByExercise.values.flatMap { $0 }
        let completed = draft.workout.exercises.flatMap { ex in
            (draft.setsByExercise[ex.id] ?? []).filter { $0.isCompleted && WorkoutSessionUtils.canCompleteSet($0, allowsZeroWeight: WorkoutSessionUtils.allowsZeroWeight(ex)) }
        }
        let completedWorking = completed.filter { !$0.isWarmup }
        let duration = draft.currentDurationSeconds(nowEpochMillis: nowEpochMillis)
        
        let unit = draft.weightInputUnit ?? .kg
        let logs = draft.workout.exercises.map { ex -> SessionExerciseLog in
            let configured = draft.setsByExercise[ex.id] ?? []
            let workingCount = configured.filter { !$0.isWarmup }.count
            let sets = configured.filter { completed.contains($0) }.map {
                IntensitySets.savedSet($0, exercise: ex, unit: unit)
            }
            let target = workingCount > 0 ? workingCount : WorkoutSessionUtils.initialSetCount(exercise: ex)
            return SessionExerciseLog(
                exerciseName: ex.name,
                sets: sets,
                targetSets: target,
                exerciseId: ExerciseCatalog.resolveCanonicalId(stableId: ex.exerciseId, name: ex.name),
                effort: draft.effortByExercise?[ex.id].flatMap(ProgressionEffort.init(rawValue:))?.rawValue,
                jointStress: draft.jointStressByExercise?[ex.id].flatMap(JointStress.init(rawValue:))?.rawValue,
                setupNote: ex.setupNote
            )
        }

        let hasProg = !(draft.note ?? "").isEmpty || allSets.contains {
            $0.isCompleted || (!$0.weightInput.trimmingCharacters(in: .whitespaces).isEmpty && ($0.inputTouched == true || $0.weightInput != "0")) || !$0.repsInput.trimmingCharacters(in: .whitespaces).isEmpty
        }

        // Drops and rest-pause efforts add their load volume; the set still counts once.
        let volume = zip(draft.workout.exercises, logs).filter { !WorkoutSessionUtils.isAssisted($0.0) }.reduce(0.0) { total, pair in
            total + pair.1.sets.filter { !$0.isWarmup }.reduce(0) { $0 + IntensitySets.loadVolume($1) }
        }

        return SessionProgress(
            durationSeconds: duration,
            completedSets: completedWorking.count,
            volumeKg: volume,
            exerciseLogs: logs,
            hasProgress: hasProg
        )
    }

    public func record(draft: ActiveSessionDraft, completedAtEpochMillis: Int64) -> WorkoutSessionRecord {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let completedAt = formatter.string(from: Date(timeIntervalSince1970: Double(completedAtEpochMillis) / 1000.0))

        return WorkoutSessionRecord(
            id: draft.id,
            programId: draft.programId,
            workoutId: draft.workout.id,
            workoutTitle: draft.workout.title,
            startedAt: draft.startedAt,
            completedAt: completedAt,
            durationSeconds: durationSeconds,
            totalVolumeKg: volumeKg,
            totalCompletedSets: completedSets,
            exerciseLogs: exerciseLogs,
            isComplete: WorkoutSessionUtils.isComplete(draft: draft),
            scheduledDate: draft.scheduledDate,
            workoutSnapshot: draft.workout, note: draft.note
        )
    }
}

public enum WorkoutSessionUtils {
    /// One pure transition shared by training and resume/undo regression fixtures.
    public static func toggledSet(_ draft: ActiveSessionDraft, exerciseId: String, index: Int,
                                  prefillNextSet: Bool = true, unit: WeightUnit = .kg, now: Int64) -> ActiveSessionDraft {
        guard let exercise = draft.workout.exercises.first(where: { $0.id == exerciseId }),
              let sets = draft.setsByExercise[exerciseId], sets.indices.contains(index) else { return draft }
        let set = sets[index]
        guard set.isCompleted || (canCompleteSet(set, allowsZeroWeight: allowsZeroWeight(exercise)) && isSetEnabled(sets: sets, index: index)) else { return draft }
        var copy = draft
        copy.setsByExercise[exerciseId] = togglingCompletion(of: index, in: sets, prefillNextSet: prefillNextSet, unit: unit,
                                                           barbell: usesBarbellPlates(exercise))
        if !set.isCompleted { copy.restTimer = RestTimerUtils.afterCompletingSet(in: copy, exercise: exercise, setId: set.id, nowEpochMillis: now) }
        else if copy.restTimer?.setId == set.id { copy.restTimer = nil }
        return copy
    }

    public static func isAssisted(exerciseId: String?, name: String) -> Bool {
        let id = ExerciseCatalog.resolveCanonicalId(stableId: exerciseId, name: name)
        return id == "assisted-pull-up" || id == "assisted-dip-machine"
    }

    public static func isAssisted(_ exercise: Exercise) -> Bool { isAssisted(exerciseId: exercise.exerciseId, name: exercise.name) }

    public static func defaultsToZeroAddedWeight(_ exercise: Exercise) -> Bool {
        defaultsToZeroAddedWeight(exerciseId: exercise.exerciseId, name: exercise.name)
    }

    public static func defaultsToZeroAddedWeight(exerciseId: String?, name: String) -> Bool {
        guard let id = ExerciseCatalog.resolveCanonicalId(stableId: exerciseId, name: name) else { return false }
        return ExerciseCatalog.canonicalExercises[id]?.searchKeywords.contains { $0.lowercased() == "bodyweight" } == true
    }

    public static func usesBodyweightResistance(_ exercise: Exercise) -> Bool {
        usesBodyweightResistance(exerciseId: exercise.exerciseId, name: exercise.name)
    }

    public static func usesBodyweightResistance(exerciseId: String?, name: String) -> Bool {
        defaultsToZeroAddedWeight(exerciseId: exerciseId, name: name) || ["weighted-pull-ups", "weighted-push-up-with-vest"].contains(
            ExerciseCatalog.resolveCanonicalId(stableId: exerciseId, name: name) ?? "")
    }

    /// The live count belongs in the header; retain custom instructions and timed targets verbatim.
    public static func sessionPrescription(_ prescription: String) -> String {
        let target = prescription.replacingOccurrences(of: #"^\s*\d+\s*[×x]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return target.range(of: #"^\d+(?:\s*[–−-]\s*\d+)?$"#, options: .regularExpression) != nil
            ? LanguageManager.t("progression.coach.reps", ["reps": target]) : LanguageManager.content(target)
    }

    public static func formatSessionPr(weightKg: Double, reps: Int, unit: WeightUnit = .kg, isBodyweight: Bool = false, isAssisted: Bool = false) -> String {
        if isBodyweight && !isAssisted {
            let added = weightKg == 0 ? "" : " +\(unit.formatDisplayWeight(weightKg))"
            return "BW\(added) ×\(reps)"
        }
        return !isAssisted && weightKg == 0 ? "×\(reps)" : "\(formatWeight(weightKg, unit: unit))x\(reps)"
    }

    public static func sessionPrAccessibilityLabel(_ text: String, unit: WeightUnit) -> String {
        if text.hasPrefix("BW") {
            let parts = String(text.dropFirst(2)).components(separatedBy: " ×")
            let load = parts[0].isEmpty ? "" : " \(parts[0].trimmingCharacters(in: .whitespaces)) \(unit.label)"
            return "\(LanguageManager.t("exercise.history.bodyweight"))\(load), \(parts.last!) \(LanguageManager.t("exercise.history.reps"))"
        }
        return text.hasPrefix("×") ? "\(text.dropFirst()) \(LanguageManager.t("exercise.history.reps"))" : text
    }

    public static func newSet(exercise: Exercise, number: Int) -> ExerciseSetLog {
        defaultsToZeroAddedWeight(exercise)
            ? ExerciseSetLog(setNumber: number, weightInput: "0", weightKg: 0)
            : ExerciseSetLog(setNumber: number)
    }

    public static func editedSet(_ set: ExerciseSetLog, weight: String, reps: String, exercise: Exercise, unit: WeightUnit) -> ExerciseSetLog {
        var edited = set
        edited.weightInput = weight; edited.repsInput = reps
        edited.weightKg = weightForEditedInput(weight, existing: set, unit: unit)
        edited.completedReps = Int(reps); edited.inputTouched = true
        edited.isCompleted = set.isCompleted && canCompleteSet(edited, allowsZeroWeight: allowsZeroWeight(exercise))
        return IntensitySets.revokingInvalidExtensions(edited, exercise: exercise, unit: unit)
    }

    /// Completed sets without any load (bodyweight work) read as bodyweight, not as "0 kg" of volume.
    public static func bodyweightVolumeLabel(_ volumeKg: Double, completedSets: Int) -> String? {
        volumeKg <= 0 && completedSets > 0 ? LanguageManager.t("exercise.history.bodyweight") : nil
    }

    /// Post-save notice: volume in the selected unit, or bodyweight when no set carried load.
    public static func workoutRecordedNotice(_ volumeKg: Double, completedSets: Int, unit: WeightUnit) -> String {
        bodyweightVolumeLabel(volumeKg, completedSets: completedSets) != nil
            ? LanguageManager.t("notice.workoutRecordedBodyweight", ["sets": completedSets])
            : LanguageManager.t("notice.workoutRecorded", [
                "sets": completedSets,
                "volume": "\(unit.formatVolume(volumeKg)) \(unit.label)"
            ])
    }

    public static func resistanceVolume(_ log: SessionExerciseLog) -> Double {
        guard !isAssisted(exerciseId: log.exerciseId, name: log.exerciseName) else { return 0 }
        return log.sets.filter { !$0.isWarmup }.reduce(0) { $0 + IntensitySets.loadVolume($1) }
    }

    public static func resistanceVolume(_ record: WorkoutSessionRecord) -> Double {
        record.exerciseLogs.contains { isAssisted(exerciseId: $0.exerciseId, name: $0.exerciseName) }
            ? record.exerciseLogs.reduce(0) { $0 + resistanceVolume($1) } : record.totalVolumeKg
    }

    public static func currentSetNumber(_ sets: [ExerciseSetLog]) -> Int {
        sets.firstIndex(where: { !$0.isCompleted }).map { $0 + 1 } ?? sets.count
    }

    public static func isSetEnabled(sets: [ExerciseSetLog], index: Int) -> Bool {
        guard index > 0 else { return true }
        return sets[..<index].allSatisfy { $0.isCompleted }
    }

    public static func maxAllowedWeight(unit: WeightUnit = .kg) -> Double {
        return unit == .lbs ? 3000.0 : 1500.0
    }

    public static func adjustWeight(_ input: String, by delta: Int, unit: WeightUnit = .kg) -> String {
        let current = sanitizedWeightInput(input, unit: unit).flatMap { Double($0) } ?? 0
        let maxLimit = maxAllowedWeight(unit: unit)
        let adjusted = (min(maxLimit, max(0, current + Double(delta))) * 100).rounded() / 100
        if adjusted.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(adjusted))"
        }
        return "\(adjusted)"
    }

    public static func adjustReps(_ input: String, by delta: Int) -> String {
        let current = min(999, max(0, Int(input) ?? 0))
        let adjusted = min(999, max(0, current + delta))
        return adjusted == 0 ? "" : "\(adjusted)"
    }

    public static func prefillSet(_ target: ExerciseSetLog, from previous: ExerciseSetLog?, unit: WeightUnit = .kg, barbell: Bool = false) -> ExerciseSetLog {
        guard target.inputTouched != true, !target.isCompleted, (target.weightInput.isEmpty || target.weightInput == "0"), target.repsInput.isEmpty,
              (target.weightKg == nil || (target.weightKg == 0 && target.weightInput == "0")), target.completedReps == nil, let previous, canCompleteSet(previous, allowsZeroWeight: true) else { return target }
        let canonicalWeight = previous.weightKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let weight = canonicalWeight.map { formatWeightInput($0, unit: unit, barbell: barbell) } ?? previous.weightInput
        let reps = previous.repsInput.isEmpty ? previous.completedReps.map { "\($0)" } ?? "" : previous.repsInput
        guard let weight = sanitizedWeightInput(weight, unit: unit), let reps = sanitizedRepsInput(reps) else { return target }
        var result = target
        result.weightInput = weight
        // The new row stores the load its text shows: exact for a load logged in this unit, the nearest
        // loadable weight for a converted one. Only legacy input-only rows need a one-time interpretation.
        result.weightKg = canonicalWeight.map { unit.loadableKg($0, barbell: barbell) } ?? Double(weight).map { unit.toCanonicalKg($0) }
        result.repsInput = reps
        result.completedReps = Int(reps)
        result.inputTouched = true
        return result
    }

    public static func rebaseWeightInputs(_ draft: ActiveSessionDraft, from oldUnit: WeightUnit, to newUnit: WeightUnit) -> ActiveSessionDraft {
        var result = draft
        let barbellIds = Set(draft.workout.exercises.filter(usesBarbellPlates).map(\.id))
        for (exerciseId, sets) in draft.setsByExercise {
            let barbell = barbellIds.contains(exerciseId)
            result.setsByExercise[exerciseId] = sets.map { set in
                var copy = set
                let inputHasDigits = set.weightInput.rangeOfCharacter(from: .decimalDigits) != nil
                let canonical = set.weightKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                    ?? (inputHasDigits ? sanitizedWeightInput(set.weightInput, unit: oldUnit).flatMap(Double.init).map { oldUnit.toCanonicalKg($0) } : nil)
                if let canonical {
                    // Completed rows keep the load they were lifted at; open rows take the loadable weight they show.
                    copy.weightKg = set.isCompleted ? canonical : newUnit.loadableKg(canonical, barbell: barbell)
                    copy.weightInput = formatWeightInput(canonical, unit: newUnit, barbell: barbell)
                }
                copy.extensions = set.extensions?.map { part in
                    // Drop loads follow the same rule; rest-pause efforts have no load of their own.
                    var part = part
                    let digits = part.weightInput.rangeOfCharacter(from: .decimalDigits) != nil
                    let canonical = part.weightKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                        ?? (digits ? sanitizedWeightInput(part.weightInput, unit: oldUnit).flatMap(Double.init).map { oldUnit.toCanonicalKg($0) } : nil)
                    if let canonical {
                        part.weightKg = part.isCompleted ? canonical : newUnit.loadableKg(canonical, barbell: barbell)
                        part.weightInput = formatWeightInput(canonical, unit: newUnit, barbell: barbell)
                    }
                    return part
                }
                return copy
            }
        }
        result.weightInputUnit = newUnit
        return result
    }

    /// Toggles one set's completion. Completing it prefills the next row when the setting is on;
    /// prefill only fills untouched rows, so applied targets and user edits are never overwritten.
    public static func togglingCompletion(of index: Int, in sets: [ExerciseSetLog], prefillNextSet: Bool, unit: WeightUnit, barbell: Bool = false) -> [ExerciseSetLog] {
        guard sets.indices.contains(index) else { return sets }
        var sets = sets
        let currentSet = sets[index]
        sets[index].isCompleted = !currentSet.isCompleted
        if currentSet.isCompleted, var parts = sets[index].extensions {
            // Undoing the set unticks its extensions; they are saved only with a completed set.
            for part in parts.indices { parts[part].isCompleted = false }
            sets[index].extensions = parts
        }
        if !currentSet.isCompleted, prefillNextSet, sets.indices.contains(index + 1) {
            sets[index + 1] = prefillSet(sets[index + 1], from: currentSet, unit: unit, barbell: barbell)
        }
        return sets
    }

    /// Re-checked against the latest rows: only unfinished working rows receive a target.
    public static func applyingProgressionTargets(_ targets: [Int: ProgressionSetTarget], to sets: [ExerciseSetLog], unit: WeightUnit) -> [ExerciseSetLog] {
        sets.enumerated().map { index, set in
            guard let target = targets[index], !set.isWarmup, !set.isCompleted,
                  sanitizedWeightInput(target.weightInput(unit: unit, fallback: set.weightInput), unit: unit) != nil else { return set }
            return target.applied(to: set, unit: unit)
        }
    }

    public static func weightForEditedInput(_ input: String, existing set: ExerciseSetLog, unit: WeightUnit) -> Double? {
        guard let normalized = sanitizedWeightInput(input, unit: unit), let display = Double(normalized) else { return nil }
        if let canonical = set.weightKg, canonical.isFinite, canonical >= 0 {
            let previousInput = set.weightInput.isEmpty ? formatWeightInput(canonical, unit: unit) : set.weightInput
            if normalized == sanitizedWeightInput(previousInput, unit: unit) {
                return canonical // Reps-only edits do not reinterpret rounded display text.
            }
        }
        return unit.toCanonicalKg(display)
    }

    public static func isComplete(draft: ActiveSessionDraft) -> Bool {
        guard !draft.workout.exercises.isEmpty else { return false }
        return draft.workout.exercises.allSatisfy { ex in
            let sets = draft.setsByExercise[ex.id] ?? []
            let workingSets = sets.filter { !$0.isWarmup }
            if !workingSets.isEmpty {
                return workingSets.allSatisfy { $0.isCompleted && canCompleteSet($0, allowsZeroWeight: allowsZeroWeight(ex)) }
            } else {
                return !sets.isEmpty && sets.allSatisfy { $0.isCompleted && canCompleteSet($0, allowsZeroWeight: allowsZeroWeight(ex)) }
            }
        }
    }

    private static let setCountRegex = try! NSRegularExpression(pattern: #"^(\d+)\s*[×x]"#, options: .caseInsensitive)

    public static func initialSetCount(prescription: String) -> Int {
        let trimmed = prescription.trimmingCharacters(in: .whitespaces)
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        if let match = setCountRegex.firstMatch(in: trimmed, options: [], range: range),
           let groupRange = Range(match.range(at: 1), in: trimmed),
           let count = Int(trimmed[groupRange]) {
            return min(max(1, count), 10)
        }
        return 3
    }

    public static func initialSetCount(exercise: Exercise) -> Int {
        if let sets = exercise.sets {
            return min(max(1, sets), 10)
        }
        return initialSetCount(prescription: exercise.prescription)
    }

    public static func initialSets(for workout: Workout) -> [String: [ExerciseSetLog]] {
        var map: [String: [ExerciseSetLog]] = [:]
        for ex in workout.exercises {
            let count = initialSetCount(exercise: ex)
            map[ex.id] = (1...count).map { newSet(exercise: ex, number: $0) }
        }
        return map
    }

    /// Each workout exercise's log in a saved record, matched by snapshot position, identity or name.
    private static func historyLogs(workout: Workout, record: WorkoutSessionRecord) -> [SessionExerciseLog?] {
        var logsByName: [String: SessionExerciseLog] = [:]
        var logsById: [String: SessionExerciseLog] = [:]
        for log in record.exerciseLogs {
            let key = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
            logsByName[key] = log
            if let id = log.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                logsById[id] = log
            }
        }

        let usesSnapshot = record.workoutSnapshot == workout
        let snapshotIndices = WorkoutCalendar.snapshotLogIndices(exercises: workout.exercises, logs: record.exerciseLogs)
        return workout.exercises.enumerated().map { idx, ex in
            let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
            let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()

            let stableId = ExerciseCatalog.resolveCanonicalId(stableId: ex.exerciseId, name: ex.name)
            var matchedLog = usesSnapshot ? snapshotIndices[idx].map { record.exerciseLogs[$0] }
                : (stableId.flatMap { logsById[$0] } ?? logsByName[nameKey] ?? logsByName[displayKey])
            if !usesSnapshot, matchedLog == nil, idx < record.exerciseLogs.count {
                let positionalLog = record.exerciseLogs[idx]
                let posKey = positionalLog.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                if posKey == nameKey || posKey == displayKey {
                    matchedLog = positionalLog
                }
            }
            if !usesSnapshot && matchedLog == nil {
                if let exId = ex.exerciseId ?? ExerciseCatalog.canonicalExercises.first(where: { $0.value.name.lowercased() == nameKey })?.key {
                    let enName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: ex.name, lang: "en").trimmingCharacters(in: .whitespaces).lowercased()
                    let trName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: ex.name, lang: "tr").trimmingCharacters(in: .whitespaces).lowercased()
                    matchedLog = logsByName[enName] ?? logsByName[trName]
                }
            }
            return matchedLog
        }
    }

    /// Effort ratings saved with a resumed record, keyed by the workout's exercise IDs.
    public static func restoreEffortFromHistory(workout: Workout, record: WorkoutSessionRecord) -> [String: String] {
        var ratings: [String: String] = [:]
        for (exercise, log) in zip(workout.exercises, historyLogs(workout: workout, record: record)) {
            if let effort = log?.effort.flatMap(ProgressionEffort.init(rawValue:)) { ratings[exercise.id] = effort.rawValue }
        }
        return ratings
    }

    /// Joint-stress ratings saved with a resumed record, keyed by the workout's exercise IDs.
    public static func restoreJointStressFromHistory(workout: Workout, record: WorkoutSessionRecord) -> [String: String] {
        var ratings: [String: String] = [:]
        for (exercise, log) in zip(workout.exercises, historyLogs(workout: workout, record: record)) {
            if let rating = log?.jointStress.flatMap(JointStress.init(rawValue:)) { ratings[exercise.id] = rating.rawValue }
        }
        return ratings
    }

    public static func restoreSetsFromHistory(workout: Workout, record: WorkoutSessionRecord, unit: WeightUnit = .kg) -> [String: [ExerciseSetLog]] {
        let logs = historyLogs(workout: workout, record: record)
        var result: [String: [ExerciseSetLog]] = [:]
        for (idx, ex) in workout.exercises.enumerated() {
            let targetCount = initialSetCount(exercise: ex)
            let matchedLog = logs[idx]

            let completedLogs = matchedLog?.sets ?? []
            let targetTotal = matchedLog?.targetSets ?? targetCount
            let safeTarget = max(1, targetTotal)
            if !completedLogs.isEmpty {
                var restored = completedLogs.map { s in
                    IntensitySets.restoringIntensity(s, into: ExerciseSetLog(
                        setNumber: s.setNumber,
                        weightInput: s.weightKg.map { formatWeightInput($0, unit: unit, barbell: usesBarbellPlates(ex)) } ?? "",
                        repsInput: (s.reps ?? 0) > 0 ? "\(s.reps!)" : "",
                        weightKg: s.weightKg,
                        completedReps: (s.reps ?? 0) > 0 ? s.reps : nil,
                        isCompleted: true,
                        isWarmup: s.isWarmup
                    ), unit: unit, barbell: usesBarbellPlates(ex))
                }
                let working = restored.filter { !$0.isWarmup }
                let needed = max(safeTarget, working.map { $0.setNumber }.max() ?? 0)
                let completedNumbers = Set(working.map(\.setNumber))
                for number in 1...needed where !completedNumbers.contains(number) {
                    restored.append(newSet(exercise: ex, number: number))
                }
                result[ex.id] = restored
            } else {
                result[ex.id] = (1...safeTarget).map { newSet(exercise: ex, number: $0) }
            }
        }
        return result
    }

    public static func firstIncompleteExerciseIndex(workout: Workout, setsByExercise: [String: [ExerciseSetLog]]) -> Int {
        if let idx = workout.exercises.firstIndex(where: { ex in
            let sets = setsByExercise[ex.id] ?? []
            return sets.isEmpty || sets.contains(where: { !$0.isCompleted })
        }) {
            return idx
        }
        return 0
    }

    public static func findExercisePr(history: [WorkoutSessionRecord], exerciseName: String, exerciseId: String? = nil, unit: WeightUnit = .kg) -> String? {
        findExercisePr(history: history, exercise: Exercise(name: exerciseName, exerciseId: exerciseId), unit: unit)
    }

    public static func findExercisePr(history: [WorkoutSessionRecord], exercise: Exercise, unit: WeightUnit = .kg) -> String? {
        let assisted = isAssisted(exercise)
        let candidates = history.flatMap { $0.exerciseLogs }.filter {
            ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.exerciseName)
        }.flatMap { $0.sets }.filter { !$0.isWarmup && validHistoricalSet($0, exercise: exercise) }
        let best = candidates.max { a, b in
            if a.weightKg != b.weightKg { return assisted ? a.weightKg! > b.weightKg! : a.weightKg! < b.weightKg! }
            return a.reps! < b.reps!
        }
        guard let best else { return nil }
        return formatSessionPr(weightKg: best.weightKg!, reps: best.reps!, unit: unit, isBodyweight: usesBodyweightResistance(exercise), isAssisted: assisted)
    }

    private static func validHistoricalSet(_ set: SessionSetLog, exercise: Exercise) -> Bool {
        guard let reps = set.reps, (1...999).contains(reps), let weight = set.weightKg, weight.isFinite, weight >= 0 else { return false }
        return allowsZeroWeight(exercise) || weight > 0
    }

    public static func formatWeight(_ value: Double, unit: WeightUnit = .kg) -> String { unit.formatWeight(value) }

    /// Editable set text shows a load logged in this unit exactly, and a converted load at its loadable
    /// weight ("225" for a 100 kg barbell load, not "220.46"). Unchanged text keeps the row's stored load.
    public static func formatWeightInput(_ value: Double, unit: WeightUnit = .kg, barbell: Bool = false) -> String {
        unit.formatLoadableWeight(value, barbell: barbell)
    }

    /// Barbell loads convert to the easiest plate setup nearby; dumbbells, machines and the rest round to the nearest step.
    public static func usesBarbellPlates(_ exercise: Exercise) -> Bool {
        let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) ?? ExerciseCatalog.key(exercise.name)
        return EquipmentCatalog.shared.categoryId(id) == "bar"
    }

    private static let allZerosRegex = try! NSRegularExpression(pattern: #"^0+$"#)
    private static let leadingZerosRegex = try! NSRegularExpression(pattern: #"^0+(?=[1-9]|0\.)"#)
    private static let weightInputRegex = try! NSRegularExpression(pattern: #"^\d{0,4}(\.\d{0,2})?$"#)
    private static let repsInputRegex = try! NSRegularExpression(pattern: #"^[1-9]\d{0,2}$"#)

    public static func sanitizedWeightInput(_ value: String, unit: WeightUnit = .kg) -> String? {
        var normalized = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty { return "" }
        if allZerosRegex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil { normalized = "0" }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        let leadingRange = NSRange(normalized.startIndex..., in: normalized)
        normalized = leadingZerosRegex.stringByReplacingMatches(in: normalized, range: leadingRange, withTemplate: "")
        guard normalized.count <= 7 else { return nil }
        let regex = weightInputRegex
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard regex.firstMatch(in: normalized, options: [], range: range) != nil else { return nil }
        guard let numeric = Double(normalized), numeric <= maxAllowedWeight(unit: unit) else { return nil }
        return normalized
    }

    public static func completedSetEditNeedsWeightConfirmation(
        _ set: ExerciseSetLog, weightInput: String, unit: WeightUnit, previousTopWeightKg: Double?
    ) -> Bool {
        guard set.isCompleted,
              let sanitized = sanitizedWeightInput(weightInput, unit: unit),
              let displayWeight = Double(sanitized) else { return false }
        let weightKg = unit.toCanonicalKg(displayWeight)
        let oldInput = set.weightInput.isEmpty ? set.weightKg.map { formatWeightInput($0, unit: unit) } ?? "" : set.weightInput
        if Double(oldInput.replacingOccurrences(of: ",", with: ".")) == displayWeight { return false }
        return isAnomalousWeight(weightKg: weightKg, previousTopWeightKg: previousTopWeightKg)
    }

    public static func isAnomalousWeight(weightKg: Double, previousTopWeightKg: Double?) -> Bool {
        guard weightKg.isFinite, weightKg > 0 else { return false }
        if weightKg > 500.0 { return true }
        if let prev = previousTopWeightKg, prev.isFinite, prev > 0 {
            let diff = weightKg - prev
            if weightKg > prev * 1.5 && diff >= 20.0 {
                return true
            }
        }
        return false
    }

    public static func sanitizedRepsInput(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty { return "" }
        guard normalized.count <= 3 else { return nil }
        // Must start with 1-9; rejects "0", "00", "05", etc.
        let regex = repsInputRegex
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard regex.firstMatch(in: normalized, options: [], range: range) != nil else { return nil }
        return normalized
    }

    public static func allowsZeroWeight(_ exercise: Exercise) -> Bool {
        let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name)
        return isAssisted(exercise) || !["bar", "dumbbell", "machine", "kettlebell", "weight-plate"].contains(EquipmentCatalog.shared.categoryId(id))
    }

    public static func setValidationError(_ set: ExerciseSetLog, allowsZeroWeight: Bool = false) -> String? {
        let weight = set.weightKg ?? Double(set.weightInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let reps = set.completedReps ?? Int(set.repsInput.trimmingCharacters(in: .whitespaces))
        guard let w = weight, w.isFinite, w >= 0, allowsZeroWeight || w > 0 else {
            return allowsZeroWeight ? "table.validation.weight_zero_allowed" : "table.validation.weight_positive"
        }
        guard let r = reps, (1...999).contains(r) else { return "table.validation.reps" }
        return nil
    }

    public static func canCompleteSet(_ set: ExerciseSetLog, allowsZeroWeight: Bool = false) -> Bool {
        setValidationError(set, allowsZeroWeight: allowsZeroWeight) == nil
    }

    public static func findPreviousSessionWorkingSets(
        history: [WorkoutSessionRecord],
        exercise: Exercise
    ) -> [SessionSetLog] {
        for record in history.sorted(by: { ($0.completedAt.isEmpty ? $0.startedAt : $0.completedAt) > ($1.completedAt.isEmpty ? $1.startedAt : $1.completedAt) }) {
            let logs = record.exerciseLogs.filter {
                ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.exerciseName)
            }
            let working = logs.flatMap { $0.sets }.filter { !$0.isWarmup }
            if working.isEmpty { continue }
            // Keep set positions and the latest baseline, including explicit zero loads.
            return logs.count == 1 && working.allSatisfy { validHistoricalSet($0, exercise: exercise) } && Set(working.map { $0.setNumber }).count == working.count
                ? working.sorted { $0.setNumber < $1.setNumber } : []
        }
        return []
    }

    public static func computeGhostTarget(
        previousSets: [SessionSetLog],
        workingSetIndex: Int,
        exercise: Exercise,
        unit: WeightUnit = .kg,
        steps: ProgressionLoadSteps = ProgressionLoadSteps()
    ) -> GhostTarget {
        if !previousSets.isEmpty {
            guard let prev = previousSets.first(where: { $0.setNumber == workingSetIndex + 1 })
                ?? (workingSetIndex + 1 > previousSets.last!.setNumber ? previousSets.last : nil) else {
                return computeGhostTarget(previousSets: [], workingSetIndex: workingSetIndex, exercise: exercise, unit: unit, steps: steps)
            }
            let prevWeightKg = prev.weightKg ?? 0.0
            let prevReps = prev.reps ?? 8
            // The logbook's heavier comparison uses the same loadable step as Smart Progression.
            let altWeightKg = ProgressionEngine.nextLoadKg(exercise: exercise, weightKg: prevWeightKg, unit: unit, steps: steps)
            let altReps: Int? = altWeightKg != nil ? max(1, prevReps - 1) : nil
            return GhostTarget(
                lastWeekWeightKg: prevWeightKg,
                lastWeekReps: prevReps,
                altWeightKg: altWeightKg,
                altReps: altReps,
                isFirstSession: false,
                prescription: exercise.displayPrescription,
                isAssisted: isAssisted(exercise)
            )
        } else {
            return GhostTarget(
                lastWeekWeightKg: nil,
                lastWeekReps: nil,
                altWeightKg: nil,
                altReps: nil,
                isFirstSession: true,
                prescription: exercise.displayPrescription,
                isAssisted: isAssisted(exercise)
            )
        }
    }

    public static func evaluateLogbookBeat(
        loggedWeightKg: Double,
        loggedReps: Int,
        target: GhostTarget
    ) -> LogbookBeatResult? {
        guard let prevW = target.lastWeekWeightKg, let prevR = target.lastWeekReps else { return nil }
        if target.isFirstSession || !prevW.isFinite || prevW < 0 || prevR <= 0 || !loggedWeightKg.isFinite || loggedWeightKg < 0 || !(1...999).contains(loggedReps) { return nil }
        if target.isAssisted {
            let improved = (abs(loggedWeightKg - prevW) <= 0.01 && loggedReps > prevR) || (loggedWeightKg < prevW - 0.01 && loggedReps >= prevR)
            return improved ? LogbookBeatResult(repDelta: loggedReps - prevR, weightDeltaKg: loggedWeightKg - prevW, currentWeightKg: loggedWeightKg, currentReps: loggedReps, previousWeightKg: prevW, previousReps: prevR, isAssisted: true) : nil
        }

        let isSameOrHigherWeightMoreReps = loggedWeightKg >= (prevW - 0.01) && loggedReps > prevR
        let isHigherWeightEqualOrMoreReps = loggedWeightKg > (prevW + 0.01) && loggedReps >= prevR
        let isAltLoadTargetMet = target.altWeightKg != nil && target.altReps != nil &&
            loggedWeightKg >= (target.altWeightKg! - 0.01) && loggedReps >= target.altReps!

        let current1RM = loggedWeightKg * (1.0 + Double(loggedReps) / 30.0)
        let prev1RM = prevW * (1.0 + Double(prevR) / 30.0)
        let isEstimated1RMHigher = prevW > 0 && target.altWeightKg != nil && current1RM > (prev1RM * 1.005) && loggedWeightKg >= (prevW * 0.95)

        if isSameOrHigherWeightMoreReps || isHigherWeightEqualOrMoreReps || isAltLoadTargetMet || isEstimated1RMHigher {
            return LogbookBeatResult(
                repDelta: loggedReps - prevR,
                weightDeltaKg: loggedWeightKg - prevW,
                currentWeightKg: loggedWeightKg,
                currentReps: loggedReps,
                previousWeightKg: prevW,
                previousReps: prevR
            )
        }
        return nil
    }

    public static func formatLogbookBeatBadge(result: LogbookBeatResult, unit: WeightUnit = .kg) -> String {
        if result.isAssisted && result.weightDeltaKg < -0.01 { return "−\(formatWeight(-result.weightDeltaKg, unit: unit)) \(unit.uppercaseLabel)" }
        if result.repDelta > 0 && result.weightDeltaKg <= 0.01 {
            return LanguageManager.t("session.logbook.badge_rep", ["count": result.repDelta])
        } else if result.weightDeltaKg > 0.01 {
            let deltaStr = "\(formatWeight(result.weightDeltaKg, unit: unit)) \(unit.uppercaseLabel)"
            return LanguageManager.t("session.logbook.badge_weight", ["weight": deltaStr])
        } else {
            return LanguageManager.t("session.logbook.badge_beat")
        }
    }

    public static func formatLogbookBeatNotice(result: LogbookBeatResult, unit: WeightUnit = .kg) -> String {
        func value(_ weight: Double, _ reps: Int) -> String {
            if result.isAssisted { return "\(formatWeight(weight, unit: unit)) \(unit.label) \(LanguageManager.t("table.assistance")) × \(reps)" }
            if weight == 0 { return "\(reps) \(LanguageManager.t("exercise.history.reps"))" }
            return "\(formatWeight(weight, unit: unit)) \(unit.label) × \(reps)"
        }
        let currStr = value(result.currentWeightKg, result.currentReps)
        let prevStr = value(result.previousWeightKg, result.previousReps)
        return LanguageManager.t("session.logbook.beat_notice", ["current": currStr, "previous": prevStr])
    }

    public struct GhostTarget: Equatable {
        public let lastWeekWeightKg: Double?
        public let lastWeekReps: Int?
        public let altWeightKg: Double?
        public let altReps: Int?
        public let isFirstSession: Bool
        public let prescription: String
        public let isAssisted: Bool

        public init(
            lastWeekWeightKg: Double?,
            lastWeekReps: Int?,
            altWeightKg: Double?,
            altReps: Int?,
            isFirstSession: Bool,
            prescription: String = "",
            isAssisted: Bool = false
        ) {
            self.lastWeekWeightKg = lastWeekWeightKg
            self.lastWeekReps = lastWeekReps
            self.altWeightKg = altWeightKg
            self.altReps = altReps
            self.isFirstSession = isFirstSession
            self.prescription = prescription
            self.isAssisted = isAssisted
        }
    }

    public struct LogbookBeatResult: Equatable {
        public let repDelta: Int
        public let weightDeltaKg: Double
        public let currentWeightKg: Double
        public let currentReps: Int
        public let previousWeightKg: Double
        public let previousReps: Int
        public let isAssisted: Bool

        public init(
            repDelta: Int,
            weightDeltaKg: Double,
            currentWeightKg: Double,
            currentReps: Int,
            previousWeightKg: Double,
            previousReps: Int,
            isAssisted: Bool = false
        ) {
            self.repDelta = repDelta
            self.weightDeltaKg = weightDeltaKg
            self.currentWeightKg = currentWeightKg
            self.currentReps = currentReps
            self.previousWeightKg = previousWeightKg
            self.previousReps = previousReps
            self.isAssisted = isAssisted
        }
    }
}

public typealias GhostTarget = WorkoutSessionUtils.GhostTarget
public typealias LogbookBeatResult = WorkoutSessionUtils.LogbookBeatResult


/// One UI-owned history snapshot. Clock ticks and set edits reuse historical work.
final class SessionHistoryInsightsCache {
    struct Insights {
        let previousWorkingSets: [SessionSetLog]
        let recommendation: ExerciseProgressionRecommendation?
        let prText: String
    }
    /// The live session these insights serve: its own record and its workout day.
    struct ActiveScope: Equatable {
        let sessionId: String
        let programId: String
        let workoutId: String
    }
    private struct Inputs: Equatable {
        let exercise: Exercise
        let history: [WorkoutSessionRecord]
        let unit: WeightUnit
        let scope: ActiveScope?
        let steps: ProgressionLoadSteps
        let language: String
    }
    private var entry: (Inputs, Insights)?
    private let compute: (Exercise, [WorkoutSessionRecord], WeightUnit, ActiveScope?, ProgressionLoadSteps) -> Insights

    init(compute: @escaping (Exercise, [WorkoutSessionRecord], WeightUnit, ActiveScope?, ProgressionLoadSteps) -> Insights = { exercise, history, unit, scope, steps in
        // A resumed session's own saved record is today's work, not the previous session.
        let baseline = scope.map { scope in history.filter { $0.id != scope.sessionId } } ?? history
        return Insights(previousWorkingSets: WorkoutSessionUtils.findPreviousSessionWorkingSets(history: baseline, exercise: exercise),
            recommendation: ProgressionEngine.computeProgression(exercise: exercise, history: history, weightUnit: unit, activeSessionId: scope?.sessionId,
                context: scope.map { ProgressionContext(programId: $0.programId, workoutId: $0.workoutId, now: Date()) }, steps: steps),
            prText: WorkoutSessionUtils.findExercisePr(history: history, exercise: exercise, unit: unit) ?? "-")
    }) { self.compute = compute }

    func get(exercise: Exercise, history: [WorkoutSessionRecord], unit: WeightUnit, scope: ActiveScope? = nil,
             steps: ProgressionLoadSteps = ProgressionLoadSteps()) -> Insights {
        dispatchPrecondition(condition: .onQueue(.main))
        let inputs = Inputs(exercise: exercise, history: history, unit: unit, scope: scope, steps: steps, language: LanguageManager.shared.currentLanguage)
        if let entry, entry.0 == inputs { return entry.1 }
        let result = compute(exercise, history, unit, scope, steps)
        entry = (inputs, result)
        return result
    }
}

/// Drop sets, rest-pause and partials (gym/docs/design/intensity-sets.md). Android `IntensitySets`
/// applies the same rules; gym/docs/intensity-fixtures.json checks both.
public enum IntensitySets {
    public static let maxExtensions = 6
    public static let partialRepsRange = 1...99
    private static let loadTolerance = 0.0001

    // MARK: Saved sets

    /// A set uses a technique only when it has both a known technique and extensions.
    public static func usesTechnique(_ set: SessionSetLog) -> Bool {
        set.setTechnique != nil && !set.setExtensions.isEmpty
    }

    /// Load volume of a working set: the main part plus each extension's load × full reps. Partials add nothing.
    public static func loadVolume(_ set: SessionSetLog) -> Double {
        let main = (set.weightKg ?? 0) * Double(set.reps ?? 0)
        guard usesTechnique(set) else { return main }
        return set.setExtensions.reduce(main) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    /// Why a saved set cannot be restored, or nil. Restore rejects anything the logger never writes.
    public static func restoreError(_ set: SessionSetLog, assisted: Bool) -> String? {
        if set.isWarmup {
            return set.technique == nil && set.extensions == nil && set.partialReps == nil ? nil : "warmup"
        }
        if let partial = set.partialReps, !partialRepsRange.contains(partial) { return "partials" }
        guard let code = set.technique else { return set.extensions == nil ? nil : "technique" }
        guard let technique = SetTechnique(rawValue: code) else { return "technique" }
        guard let extensions = set.extensions, (1...maxExtensions).contains(extensions.count) else { return "extensions" }
        guard let main = set.weightKg, main.isFinite, main >= 0 else { return "weight" }
        var previous = main
        for part in extensions {
            guard let weight = part.weightKg, weight.isFinite, (0...BackupSanitizer.maxSetWeightKg).contains(weight) else { return "weight" }
            guard let reps = part.reps, (1...999).contains(reps) else { return "reps" }
            if let partial = part.partialReps, !partialRepsRange.contains(partial) { return "partials" }
            switch technique {
            case .drop:
                let ordered = assisted ? weight > previous + loadTolerance : weight < previous - loadTolerance
                if !ordered { return "drop_order" }
            case .restPause:
                if abs(weight - main) > loadTolerance { return "rest_pause_load" }
            }
            previous = weight
        }
        return nil
    }

    /// "100 kg × 6 → 70 kg × 5", "100 kg × 8 + 3 + 2" or "100 kg × 8 (+4 partials)". Zero loads read as BW.
    public static func notation(_ set: SessionSetLog, unit: WeightUnit) -> String {
        func load(_ weightKg: Double?) -> String {
            guard let weightKg, weightKg > 0 else { return "BW" }
            return "\(unit.formatDisplayWeight(weightKg)) \(unit.label)"
        }
        func partials(_ count: Int?) -> String {
            guard let count, partialRepsRange.contains(count) else { return "" }
            return " (" + LanguageManager.shared.plural("intensity.partials", count) + ")"
        }
        var text = "\(load(set.weightKg)) × \(set.reps ?? 0)" + partials(set.partialReps)
        guard usesTechnique(set), let technique = set.setTechnique else { return text }
        for part in set.setExtensions {
            switch technique {
            case .drop: text += " → \(load(part.weightKg)) × \(part.reps ?? 0)"
            case .restPause: text += " + \(part.reps ?? 0)"
            }
            text += partials(part.partialReps)
        }
        return text
    }

    /// Whether a saved set shows more than its main part.
    public static func hasDetail(_ set: SessionSetLog) -> Bool {
        usesTechnique(set) || set.partialReps != nil
    }

    // MARK: Active-session draft

    public static func technique(of set: ExerciseSetLog) -> SetTechnique? {
        set.technique.flatMap(SetTechnique.init(rawValue:))
    }

    public static func partialCount(_ input: String?) -> Int? {
        guard let value = input.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), partialRepsRange.contains(value) else { return nil }
        return value
    }

    /// Accepts "" or 1–99 without leading zeros, like rep inputs.
    public static func sanitizedPartialInput(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        guard trimmed.count <= 2, trimmed.first != "0", let number = Int(trimmed), partialRepsRange.contains(number) else { return nil }
        return trimmed
    }

    public static func canAdd(_ technique: SetTechnique, to set: ExerciseSetLog) -> Bool {
        !set.isWarmup && (set.technique == nil || set.technique == technique.rawValue) && (set.extensions?.count ?? 0) < maxExtensions
    }

    /// Partials attach to the set's last part; one entry per part.
    public static func canAddPartials(to set: ExerciseSetLog) -> Bool {
        guard !set.isWarmup else { return false }
        if let last = set.extensions?.last { return last.partialRepsInput == nil }
        return set.partialRepsInput == nil
    }

    public static func hasRemovablePart(_ set: ExerciseSetLog) -> Bool {
        !(set.extensions ?? []).isEmpty || set.partialRepsInput != nil
    }

    /// Adds an empty drop or rest-pause effort. A drop may start from the previous occurrence's load.
    public static func addingExtension(_ technique: SetTechnique, to set: ExerciseSetLog, prefillWeightKg: Double? = nil,
                                       unit: WeightUnit, barbell: Bool = false) -> ExerciseSetLog {
        guard canAdd(technique, to: set) else { return set }
        var part = SetExtensionLog()
        if technique == .drop, let weight = prefillWeightKg, weight.isFinite, weight >= 0 {
            part.weightInput = WorkoutSessionUtils.formatWeightInput(weight, unit: unit, barbell: barbell)
            part.weightKg = unit.loadableKg(weight, barbell: barbell)
        }
        var copy = set
        copy.technique = technique.rawValue
        copy.extensions = (set.extensions ?? []) + [part]
        return copy
    }

    public static func addingPartials(to set: ExerciseSetLog) -> ExerciseSetLog {
        guard canAddPartials(to: set) else { return set }
        var copy = set
        if var parts = set.extensions, !parts.isEmpty {
            parts[parts.count - 1].partialRepsInput = ""
            copy.extensions = parts
        } else {
            copy.partialRepsInput = ""
        }
        return copy
    }

    /// Removes the last part's partials, else the last extension, else the main part's partials.
    public static func removingLastPart(_ set: ExerciseSetLog) -> ExerciseSetLog {
        var copy = set
        if var parts = set.extensions, let last = parts.last {
            if last.partialRepsInput != nil {
                parts[parts.count - 1].partialRepsInput = nil
            } else {
                parts.removeLast()
            }
            copy.extensions = parts.isEmpty ? nil : parts
            if parts.isEmpty { copy.technique = nil }
        } else {
            copy.partialRepsInput = nil
        }
        return copy
    }

    /// The load of extension `index` in kg: typed for a drop, the main load for rest-pause.
    public static func extensionWeightKg(_ set: ExerciseSetLog, at index: Int, unit: WeightUnit) -> Double? {
        guard let part = set.extensions?[safe: index] else { return nil }
        if technique(of: set) == .restPause { return mainWeightKg(set, unit: unit) }
        return part.weightKg ?? parsedWeightKg(part.weightInput, unit: unit)
    }

    public static func mainWeightKg(_ set: ExerciseSetLog, unit: WeightUnit) -> Double? {
        set.weightKg ?? parsedWeightKg(set.weightInput, unit: unit)
    }

    private static func parsedWeightKg(_ input: String, unit: WeightUnit) -> Double? {
        Double(input.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)).map { unit.toCanonicalKg($0) }
    }

    /// The localization key explaining why an extension cannot be ticked, or nil.
    public static func extensionValidationError(_ set: ExerciseSetLog, at index: Int, exercise: Exercise, unit: WeightUnit) -> String? {
        guard let part = set.extensions?[safe: index] else { return nil }
        let allowsZero = WorkoutSessionUtils.allowsZeroWeight(exercise)
        if let mainError = WorkoutSessionUtils.setValidationError(set, allowsZeroWeight: allowsZero) { return mainError }
        guard let weight = extensionWeightKg(set, at: index, unit: unit), weight.isFinite, weight >= 0, allowsZero || weight > 0 else {
            return allowsZero ? "table.validation.weight_zero_allowed" : "table.validation.weight_positive"
        }
        guard let reps = part.completedReps ?? Int(part.repsInput.trimmingCharacters(in: .whitespaces)), (1...999).contains(reps) else {
            return "table.validation.reps"
        }
        if technique(of: set) == .drop,
           let previous = index == 0 ? mainWeightKg(set, unit: unit) : extensionWeightKg(set, at: index - 1, unit: unit) {
            let assisted = WorkoutSessionUtils.isAssisted(exercise)
            let ordered = assisted ? weight > previous + loadTolerance : weight < previous - loadTolerance
            if !ordered { return assisted ? "intensity.validation.dropAssistance" : "intensity.validation.dropLighter" }
        }
        return nil
    }

    /// Edits one extension's text. A drop keeps its typed load; rest-pause always uses the main load.
    public static func editingExtension(_ set: ExerciseSetLog, at index: Int, weight: String, reps: String,
                                        exercise: Exercise, unit: WeightUnit) -> ExerciseSetLog {
        guard var parts = set.extensions, parts.indices.contains(index) else { return set }
        var part = parts[index]
        if technique(of: set) == .drop {
            let existing = ExerciseSetLog(setNumber: set.setNumber, weightInput: part.weightInput, weightKg: part.weightKg)
            part.weightKg = WorkoutSessionUtils.weightForEditedInput(weight, existing: existing, unit: unit)
            part.weightInput = weight
        }
        part.repsInput = reps
        part.completedReps = Int(reps)
        parts[index] = part
        var copy = set
        copy.extensions = parts
        return revokingInvalidExtensions(copy, exercise: exercise, unit: unit)
    }

    public static func editingPartials(_ set: ExerciseSetLog, extensionIndex: Int?, input: String) -> ExerciseSetLog {
        var copy = set
        if let extensionIndex {
            guard var parts = set.extensions, parts.indices.contains(extensionIndex), parts[extensionIndex].partialRepsInput != nil else { return set }
            parts[extensionIndex].partialRepsInput = input
            copy.extensions = parts
        } else {
            guard set.partialRepsInput != nil else { return set }
            copy.partialRepsInput = input
        }
        return copy
    }

    /// Ticks a valid extension or unticks a ticked one.
    public static func togglingExtension(_ set: ExerciseSetLog, at index: Int, exercise: Exercise, unit: WeightUnit) -> ExerciseSetLog {
        guard var parts = set.extensions, parts.indices.contains(index) else { return set }
        if parts[index].isCompleted {
            parts[index].isCompleted = false
        } else {
            guard extensionValidationError(set, at: index, exercise: exercise, unit: unit) == nil else { return set }
            parts[index].isCompleted = true
        }
        var copy = set
        copy.extensions = parts
        return copy
    }

    /// Unticks extensions that are no longer valid, and all of them once the main part is not completed.
    public static func revokingInvalidExtensions(_ set: ExerciseSetLog, exercise: Exercise, unit: WeightUnit) -> ExerciseSetLog {
        guard var parts = set.extensions else { return set }
        for index in parts.indices where parts[index].isCompleted {
            if !set.isCompleted || extensionValidationError(set, at: index, exercise: exercise, unit: unit) != nil {
                parts[index].isCompleted = false
            }
        }
        var copy = set
        copy.extensions = parts
        return copy
    }

    /// Converting a set to a warmup removes its technique and partials.
    public static func clearingIntensity(_ set: ExerciseSetLog) -> ExerciseSetLog {
        var copy = set
        copy.technique = nil
        copy.partialRepsInput = nil
        copy.extensions = nil
        return copy
    }

    /// The saved form of a completed draft set: ticked, valid extensions and valid partials only.
    public static func savedSet(_ set: ExerciseSetLog, exercise: Exercise, unit: WeightUnit) -> SessionSetLog {
        var saved = SessionSetLog(setNumber: set.setNumber, weightKg: set.weightKg, reps: set.completedReps, isWarmup: set.isWarmup)
        guard !set.isWarmup else { return saved }
        saved.partialReps = partialCount(set.partialRepsInput)
        guard let technique = technique(of: set) else { return saved }
        let parts: [SessionSetExtension] = (set.extensions ?? []).enumerated().compactMap { index, part in
            guard part.isCompleted, extensionValidationError(set, at: index, exercise: exercise, unit: unit) == nil,
                  let weight = extensionWeightKg(set, at: index, unit: unit) else { return nil }
            return SessionSetExtension(weightKg: weight, reps: part.completedReps ?? Int(part.repsInput), partialReps: partialCount(part.partialRepsInput))
        }
        if !parts.isEmpty {
            saved.technique = technique.rawValue
            saved.extensions = parts
        }
        return saved
    }

    /// Rebuilds a resumed session's ticked extensions and partials.
    public static func restoringIntensity(_ saved: SessionSetLog, into set: ExerciseSetLog, unit: WeightUnit, barbell: Bool) -> ExerciseSetLog {
        guard !saved.isWarmup else { return set }
        var copy = set
        copy.partialRepsInput = saved.partialReps.map(String.init)
        if usesTechnique(saved), let technique = saved.setTechnique {
            copy.technique = technique.rawValue
            copy.extensions = saved.setExtensions.map { part in
                SetExtensionLog(
                    weightInput: technique == .drop ? part.weightKg.map { WorkoutSessionUtils.formatWeightInput($0, unit: unit, barbell: barbell) } ?? "" : "",
                    repsInput: part.reps.map(String.init) ?? "",
                    weightKg: technique == .drop ? part.weightKg : nil,
                    completedReps: part.reps,
                    isCompleted: true,
                    partialRepsInput: part.partialReps.map(String.init)
                )
            }
        }
        return copy
    }

    /// Ticking an extension of the set that started the running rest restarts that rest at full length.
    public static func restAfterTickingExtension(in draft: ActiveSessionDraft, setId: String, exercise: Exercise, nowEpochMillis: Int64) -> RestTimerState? {
        guard let rest = draft.restTimer, rest.isRunning, rest.setId == setId, rest.secondsRemaining(nowEpochMillis: nowEpochMillis) > 0 else {
            return draft.restTimer
        }
        return RestTimerUtils.afterCompletingSet(in: draft, exercise: exercise, setId: setId, nowEpochMillis: nowEpochMillis) ?? rest
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Two exercises per group. Sets and records stay attached to their own exercise occurrence.
public enum Supersets {
    public static func normalized(_ exercises: [Exercise]) -> [Exercise] {
        let counts = Dictionary(grouping: exercises.compactMap(\.supersetId), by: { $0 }).mapValues(\.count)
        return exercises.map { exercise in
            var copy = exercise
            if let id = copy.supersetId,
               counts[id] != 2 || id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", options: .regularExpression) != (id.startIndex..<id.endIndex) {
                copy.supersetId = nil
            }
            return copy
        }
    }
    private static func blocks(_ workout: Workout) -> [[Int]] {
        let exercises = normalized(workout.exercises)
        var used = Set<Int>()
        var result: [[Int]] = []
        for index in exercises.indices where !used.contains(index) {
            let block = exercises[index].supersetId.map { group in exercises.indices.filter { exercises[$0].supersetId == group } } ?? [index]
            used.formUnion(block); result.append(block)
        }
        return result
    }
    public static func pair(_ workout: Workout, _ exerciseId: String) -> [Exercise]? {
        blocks(workout).first { $0.count == 2 && $0.contains { workout.exercises[$0].id == exerciseId } }?.map { workout.exercises[$0] }
    }
    public static func label(_ workout: Workout, _ exerciseId: String) -> String? {
        let pairs = blocks(workout).filter { $0.count == 2 }
        guard let group = pairs.firstIndex(where: { $0.contains { workout.exercises[$0].id == exerciseId } }),
              let member = pairs[group].firstIndex(where: { workout.exercises[$0].id == exerciseId }) else { return nil }
        var number = group + 1, letters = ""
        while number > 0 { number -= 1; letters = String(UnicodeScalar(65 + number % 26)!) + letters; number /= 26 }
        return "\(letters)\(member + 1)"
    }
    public static func canPair(_ workout: Workout, _ exerciseId: String) -> Bool {
        guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }), index + 1 < workout.exercises.count else { return false }
        return pair(workout, exerciseId) == nil && pair(workout, workout.exercises[index + 1].id) == nil
    }
    public static func toggled(_ workout: Workout, _ exerciseId: String, groupId: String = UUID().uuidString) -> Workout {
        let existing = pair(workout, exerciseId)
        let ids: Set<String>
        if let existing { ids = Set(existing.map(\.id)) }
        else {
            guard canPair(workout, exerciseId), let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }) else { return workout }
            ids = [exerciseId, workout.exercises[index + 1].id]
        }
        var copy = workout
        copy.exercises = normalized(workout.exercises).map { exercise in
            var copy = exercise
            if ids.contains(copy.id) { copy.supersetId = existing == nil ? groupId : nil }
            return copy
        }
        return copy
    }
    public static func nextIndex(_ draft: ActiveSessionDraft) -> Int? {
        let blocks = blocks(draft.workout)
        guard let position = blocks.firstIndex(where: { $0.contains(draft.currentExerciseIndex) }) else { return nil }
        let block = blocks[position]
        if block.count == 2, let partner = block.first(where: { $0 != draft.currentExerciseIndex }),
           (draft.setsByExercise[draft.workout.exercises[partner].id] ?? []).contains(where: { !$0.isCompleted && !$0.isWarmup }) { return partner }
        return position + 1 < blocks.count ? blocks[position + 1].first : nil
    }
    /// Warmups rest normally. A finished or skipped partner leaves solo rest for remaining work.
    public static func defersRest(_ draft: ActiveSessionDraft, exerciseId: String, setId: String?) -> Bool {
        guard let setId, (draft.setsByExercise[exerciseId] ?? []).first(where: { $0.id == setId })?.isWarmup == false,
              let pair = pair(draft.workout, exerciseId), pair.first?.id == exerciseId else { return false }
        let own = (draft.setsByExercise[exerciseId] ?? []).filter { !$0.isWarmup }
        let partner = (draft.setsByExercise[pair[1].id] ?? []).filter { !$0.isWarmup }
        return partner.contains { !$0.isCompleted } && own.filter(\.isCompleted).count <= partner.filter(\.isCompleted).count + 1
    }
}
