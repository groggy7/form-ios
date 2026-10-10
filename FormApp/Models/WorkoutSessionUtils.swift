import Foundation

public enum RestTimerUtils {
    public static let restPresets: [Int] = [60, 90, 120, 180, 240]

    /// Evaluate the latest draft after logging the set, independent of exercise order.
    public static func afterCompletingSet(in draft: ActiveSessionDraft, exercise: Exercise, nowEpochMillis: Int64) -> RestTimerState? {
        guard !WorkoutSessionUtils.isComplete(draft: draft) else { return nil }
        let seconds = restSeconds(for: exercise)
        guard seconds > 0 else { return nil }
        return RestTimerState(
            exerciseName: exercise.name,
            totalSeconds: seconds,
            isRunning: true,
            endsAtEpochMillis: nowEpochMillis + Int64(seconds) * 1000,
            pausedSecondsRemaining: seconds
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
        
        let volume = draft.workout.exercises.filter { !WorkoutSessionUtils.isAssisted($0) }.reduce(0.0) { total, ex in
            total + (draft.setsByExercise[ex.id] ?? []).filter { completedWorking.contains($0) }.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.completedReps ?? 0) }
        }

        let logs = draft.workout.exercises.map { ex -> SessionExerciseLog in
            let configured = draft.setsByExercise[ex.id] ?? []
            let workingCount = configured.filter { !$0.isWarmup }.count
            let sets = configured.filter { completed.contains($0) }.map {
                SessionSetLog(setNumber: $0.setNumber, weightKg: $0.weightKg, reps: $0.completedReps, isWarmup: $0.isWarmup)
            }
            let target = workingCount > 0 ? workingCount : WorkoutSessionUtils.initialSetCount(exercise: ex)
            return SessionExerciseLog(
                exerciseName: ex.name,
                sets: sets,
                targetSets: target,
                exerciseId: ExerciseCatalog.resolveCanonicalId(stableId: ex.exerciseId, name: ex.name)
            )
        }

        let hasProg = allSets.contains {
            $0.isCompleted || (!$0.weightInput.trimmingCharacters(in: .whitespaces).isEmpty && ($0.inputTouched == true || $0.weightInput != "0")) || !$0.repsInput.trimmingCharacters(in: .whitespaces).isEmpty
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
            workoutSnapshot: draft.workout
        )
    }
}

public enum WorkoutSessionUtils {
    public static func isAssisted(exerciseId: String?, name: String) -> Bool {
        let id = ExerciseCatalog.resolveCanonicalId(stableId: exerciseId, name: name)
        return id == "assisted-pull-up" || id == "assisted-dip-machine"
    }

    public static func isAssisted(_ exercise: Exercise) -> Bool { isAssisted(exerciseId: exercise.exerciseId, name: exercise.name) }

    public static func defaultsToZeroAddedWeight(_ exercise: Exercise) -> Bool {
        guard let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) else { return false }
        return ExerciseCatalog.canonicalExercises[id]?.searchKeywords.contains { $0.lowercased() == "bodyweight" } == true
    }

    public static func usesBodyweightResistance(_ exercise: Exercise) -> Bool {
        defaultsToZeroAddedWeight(exercise) || ["weighted-pull-ups", "weighted-push-up-with-vest"].contains(
            ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) ?? "")
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
        return edited
    }

    public static func resistanceVolume(_ log: SessionExerciseLog) -> Double {
        guard !isAssisted(exerciseId: log.exerciseId, name: log.exerciseName) else { return 0 }
        return log.sets.filter { !$0.isWarmup }.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
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

    public static func prefillSet(_ target: ExerciseSetLog, from previous: ExerciseSetLog?, unit: WeightUnit = .kg) -> ExerciseSetLog {
        guard target.inputTouched != true, !target.isCompleted, (target.weightInput.isEmpty || target.weightInput == "0"), target.repsInput.isEmpty,
              (target.weightKg == nil || (target.weightKg == 0 && target.weightInput == "0")), target.completedReps == nil, let previous, canCompleteSet(previous, allowsZeroWeight: true) else { return target }
        let canonicalWeight = previous.weightKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let weight = canonicalWeight.map { formatWeight($0, unit: unit) } ?? previous.weightInput
        let reps = previous.repsInput.isEmpty ? previous.completedReps.map { "\($0)" } ?? "" : previous.repsInput
        guard let weight = sanitizedWeightInput(weight, unit: unit), let reps = sanitizedRepsInput(reps) else { return target }
        var result = target
        result.weightInput = weight
        // Formatting a kg value as rounded pounds must not round-trip back into
        // storage. Only legacy input-only rows need a one-time interpretation.
        result.weightKg = canonicalWeight ?? Double(weight).map { unit.toCanonicalKg($0) }
        result.repsInput = reps
        result.completedReps = Int(reps)
        result.inputTouched = true
        return result
    }

    public static func rebaseWeightInputs(_ draft: ActiveSessionDraft, from oldUnit: WeightUnit, to newUnit: WeightUnit) -> ActiveSessionDraft {
        var result = draft
        result.setsByExercise = draft.setsByExercise.mapValues { sets in
            sets.map { set in
                var copy = set
                let inputHasDigits = set.weightInput.rangeOfCharacter(from: .decimalDigits) != nil
                let canonical = set.weightKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
                    ?? (inputHasDigits ? sanitizedWeightInput(set.weightInput, unit: oldUnit).flatMap(Double.init).map { oldUnit.toCanonicalKg($0) } : nil)
                if let canonical {
                    copy.weightKg = canonical
                    copy.weightInput = formatWeight(canonical, unit: newUnit)
                }
                return copy
            }
        }
        result.weightInputUnit = newUnit
        return result
    }

    public static func weightForEditedInput(_ input: String, existing set: ExerciseSetLog, unit: WeightUnit) -> Double? {
        guard let normalized = sanitizedWeightInput(input, unit: unit), let display = Double(normalized) else { return nil }
        if let canonical = set.weightKg, canonical.isFinite, canonical >= 0 {
            let previousInput = set.weightInput.isEmpty ? formatWeight(canonical, unit: unit) : set.weightInput
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

    public static func restoreSetsFromHistory(workout: Workout, record: WorkoutSessionRecord, unit: WeightUnit = .kg) -> [String: [ExerciseSetLog]] {
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
        var result: [String: [ExerciseSetLog]] = [:]
        for (idx, ex) in workout.exercises.enumerated() {
            let targetCount = initialSetCount(exercise: ex)
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

            let completedLogs = matchedLog?.sets ?? []
            let targetTotal = matchedLog?.targetSets ?? targetCount
            let safeTarget = max(1, targetTotal)
            if !completedLogs.isEmpty {
                var restored = completedLogs.map { s in
                    ExerciseSetLog(
                        setNumber: s.setNumber,
                        weightInput: s.weightKg.map { formatWeight($0, unit: unit) } ?? "",
                        repsInput: (s.reps ?? 0) > 0 ? "\(s.reps!)" : "",
                        weightKg: s.weightKg,
                        completedReps: (s.reps ?? 0) > 0 ? s.reps : nil,
                        isCompleted: true,
                        isWarmup: s.isWarmup
                    )
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

    public static func sanitizedWeightInput(_ value: String, unit: WeightUnit = .kg) -> String? {
        var normalized = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty { return "" }
        if normalized.range(of: #"^0+$"#, options: .regularExpression) != nil { normalized = "0" }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if let regex = try? NSRegularExpression(pattern: #"^0+(?=[1-9]|0\.)"#) {
            let range = NSRange(location: 0, length: normalized.utf16.count)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        guard normalized.count <= 7 else { return nil }
        let regex = try! NSRegularExpression(pattern: #"^\d{0,4}(\.\d{0,2})?$"#)
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
        let oldInput = set.weightInput.isEmpty ? set.weightKg.map { formatWeight($0, unit: unit) } ?? "" : set.weightInput
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
        let regex = try! NSRegularExpression(pattern: #"^[1-9]\d{0,2}$"#)
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
        unit: WeightUnit = .kg
    ) -> GhostTarget {
        if !previousSets.isEmpty {
            guard let prev = previousSets.first(where: { $0.setNumber == workingSetIndex + 1 })
                ?? (workingSetIndex + 1 > previousSets.last!.setNumber ? previousSets.last : nil) else {
                return computeGhostTarget(previousSets: [], workingSetIndex: workingSetIndex, exercise: exercise, unit: unit)
            }
            let prevWeightKg = prev.weightKg ?? 0.0
            let prevReps = prev.reps ?? 8
            let targetWeightKg = prevWeightKg
            let targetReps = prevReps + 1
            let deltaKg = (unit == .lbs) ? WeightUnit.toCanonicalKg(5.0, unit: .lbs) : 2.5
            let supportsLoadStep = prevWeightKg > 0 && !isAssisted(exercise) && ["bar", "dumbbell", "machine"].contains(EquipmentCatalog.shared.categoryId(ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name)))
            let altWeightKg: Double? = supportsLoadStep ? prevWeightKg + deltaKg : nil
            let altReps: Int? = supportsLoadStep ? max(1, prevReps - 1) : nil
            return GhostTarget(
                lastWeekWeightKg: prevWeightKg,
                lastWeekReps: prevReps,
                targetWeightKg: targetWeightKg,
                targetReps: targetReps,
                altWeightKg: altWeightKg,
                altReps: altReps,
                isFirstSession: false,
                prescription: exercise.displayPrescription,
                isAssisted: isAssisted(exercise)
            )
        } else {
            let minReps = ProgressionEngine.parseRepRange(exercise: exercise)?.min
            return GhostTarget(
                lastWeekWeightKg: nil,
                lastWeekReps: nil,
                targetWeightKg: 0.0,
                targetReps: minReps,
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

    public static func formatGhostTargetText(target: GhostTarget, unit: WeightUnit = .kg) -> String {
        if target.isFirstSession {
            let presc = target.prescription.isEmpty ? "8–12 reps" : target.prescription
            return LanguageManager.t("session.ghost.first_session", ["prescription": presc])
        }
        let prevW = formatWeight(target.lastWeekWeightKg ?? 0.0, unit: unit)
        let prevR = target.lastWeekReps ?? 0
        let repsLabel = LanguageManager.t("units.reps")
        let lastWeekStr = LanguageManager.t(
            "session.ghost.last_week",
            ["weight": "\(prevW) \(unit.label)", "reps": "\(prevR) \(repsLabel)"]
        )

        let repW = formatWeight(target.targetWeightKg, unit: unit)
        guard let repR = target.targetReps else { return lastWeekStr }
        let repTargetStr = "\(repW) \(unit.label) × \(repR) \(repsLabel)"

        let targetToBeatStr: String
        if let altWKg = target.altWeightKg, let altR = target.altReps {
            let altW = formatWeight(altWKg, unit: unit)
            let loadTargetStr = "\(altW) \(unit.label) × \(altR)"
            targetToBeatStr = LanguageManager.t(
                "session.ghost.target_to_beat",
                ["repTarget": repTargetStr, "loadTarget": loadTargetStr]
            )
        } else {
            targetToBeatStr = LanguageManager.t(
                "session.ghost.target_to_beat_reps_only",
                ["repTarget": repTargetStr]
            )
        }
        return "\(lastWeekStr) · \(targetToBeatStr)"
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
        public let targetWeightKg: Double
        public let targetReps: Int?
        public let altWeightKg: Double?
        public let altReps: Int?
        public let isFirstSession: Bool
        public let prescription: String
        public let isAssisted: Bool

        public init(
            lastWeekWeightKg: Double?,
            lastWeekReps: Int?,
            targetWeightKg: Double,
            targetReps: Int?,
            altWeightKg: Double?,
            altReps: Int?,
            isFirstSession: Bool,
            prescription: String = "",
            isAssisted: Bool = false
        ) {
            self.lastWeekWeightKg = lastWeekWeightKg
            self.lastWeekReps = lastWeekReps
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
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
