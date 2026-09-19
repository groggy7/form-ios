import Foundation

public enum RestTimerUtils {
    public static let restPresets: [Int] = [60, 90, 120, 180, 240]

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
        let completed = allSets.filter { $0.isCompleted }
        let completedWorking = completed.filter { !$0.isWarmup }
        let elapsed = Int((nowEpochMillis - draft.startedAtEpochMillis) / 1000)
        let duration = min(max(0, elapsed), 8 * 3600)
        
        var volume: Double = 0
        for s in completedWorking {
            let w = s.weightKg ?? 0
            let r = s.completedReps ?? 0
            volume += w * Double(r)
        }

        let logs = draft.workout.exercises.map { ex -> SessionExerciseLog in
            let configured = draft.setsByExercise[ex.id] ?? []
            let workingCount = configured.filter { !$0.isWarmup }.count
            let sets = configured.filter { $0.isCompleted }.map {
                SessionSetLog(setNumber: $0.setNumber, weightKg: $0.weightKg, reps: $0.completedReps, isWarmup: $0.isWarmup)
            }
            let target = workingCount > 0 ? workingCount : WorkoutSessionUtils.initialSetCount(exercise: ex)
            return SessionExerciseLog(exerciseName: ex.name, sets: sets, targetSets: target)
        }

        let hasProg = allSets.contains {
            $0.isCompleted || !$0.weightInput.trimmingCharacters(in: .whitespaces).isEmpty || !$0.repsInput.trimmingCharacters(in: .whitespaces).isEmpty
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
            isComplete: WorkoutSessionUtils.isComplete(draft: draft)
        )
    }
}

public enum WorkoutSessionUtils {
    public static func currentSetNumber(_ sets: [ExerciseSetLog]) -> Int {
        sets.firstIndex(where: { !$0.isCompleted }).map { $0 + 1 } ?? sets.count
    }

    public static func isSetEnabled(sets: [ExerciseSetLog], index: Int) -> Bool {
        guard index > 0 else { return true }
        return sets[..<index].allSatisfy { $0.isCompleted }
    }

    public static func adjustWeight(_ input: String, by delta: Int) -> String {
        let current = sanitizedWeightInput(input).flatMap { Double($0) } ?? 0
        let adjusted = (min(9999.99, max(0, current + Double(delta))) * 100).rounded() / 100
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
        guard target.inputTouched != true, !target.isCompleted, target.weightInput.isEmpty, target.repsInput.isEmpty,
              target.weightKg == nil, target.completedReps == nil, let previous, canCompleteSet(previous) else { return target }
        let weight = previous.weightInput.isEmpty ? previous.weightKg.map { formatWeight($0, unit: unit) } ?? "" : previous.weightInput
        let reps = previous.repsInput.isEmpty ? previous.completedReps.map { "\($0)" } ?? "" : previous.repsInput
        guard let weight = sanitizedWeightInput(weight), let reps = sanitizedRepsInput(reps) else { return target }
        var result = target
        result.weightInput = weight
        result.weightKg = Double(weight).map { unit.toCanonicalKg($0) }
        result.repsInput = reps
        result.completedReps = Int(reps)
        result.inputTouched = true
        return result
    }

    public static func isComplete(draft: ActiveSessionDraft) -> Bool {
        guard !draft.workout.exercises.isEmpty else { return false }
        return draft.workout.exercises.allSatisfy { ex in
            let sets = draft.setsByExercise[ex.id] ?? []
            let workingSets = sets.filter { !$0.isWarmup }
            if !workingSets.isEmpty {
                return workingSets.allSatisfy { $0.isCompleted }
            } else {
                return !sets.isEmpty && sets.allSatisfy { $0.isCompleted }
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
            map[ex.id] = (1...count).map { ExerciseSetLog(setNumber: $0) }
        }
        return map
    }

    public static func restoreSetsFromHistory(workout: Workout, record: WorkoutSessionRecord, unit: WeightUnit = .kg) -> [String: [ExerciseSetLog]] {
        var logsByName: [String: SessionExerciseLog] = [:]
        for log in record.exerciseLogs {
            let key = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
            logsByName[key] = log
        }

        var result: [String: [ExerciseSetLog]] = [:]
        for (idx, ex) in workout.exercises.enumerated() {
            let targetCount = initialSetCount(exercise: ex)
            let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
            let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()

            var matchedLog = logsByName[nameKey] ?? logsByName[displayKey]
            if matchedLog == nil, idx < record.exerciseLogs.count {
                let positionalLog = record.exerciseLogs[idx]
                let posKey = positionalLog.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                if posKey == nameKey || posKey == displayKey {
                    matchedLog = positionalLog
                }
            }
            if matchedLog == nil {
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
                        isCompleted: true
                    )
                }
                let maxNum = restored.map { $0.setNumber }.max() ?? 0
                let needed = max(safeTarget, maxNum)
                if needed > restored.count {
                    for num in (restored.count + 1)...needed {
                        restored.append(ExerciseSetLog(setNumber: num))
                    }
                }
                result[ex.id] = restored
            } else {
                result[ex.id] = (1...safeTarget).map { ExerciseSetLog(setNumber: $0) }
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

    public static func findExercisePr(
        history: [WorkoutSessionRecord],
        exerciseName: String,
        exerciseId: String? = nil,
        unit: WeightUnit = .kg
    ) -> String? {
        let targetId = exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var bestWeight: Double = 0.0
        var bestReps: Int = 0

        for record in history {
            for log in record.exerciseLogs {
                let logName = log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                var matches = logName == targetName

                if !matches {
                    if let exId = targetId ?? ExerciseCatalog.canonicalExercises.first(where: { $0.value.name.lowercased() == targetName })?.key {
                        let enName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: exerciseName, lang: "en").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let trName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: exerciseName, lang: "tr").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if logName == enName || logName == trName {
                            matches = true
                        }
                    }
                }

                if !matches { continue }

                for set in log.sets {
                    if set.isWarmup { continue }
                    let weight = set.weightKg ?? 0.0
                    let reps = set.reps ?? 0
                    if weight > 0.0 && reps > 0 {
                        if weight > bestWeight || (weight == bestWeight && reps > bestReps) {
                            bestWeight = weight
                            bestReps = reps
                        }
                    }
                }
            }
        }

        if bestWeight > 0.0 && bestReps > 0 {
            return "\(formatWeight(bestWeight, unit: unit))x\(bestReps)"
        } else {
            return nil
        }
    }

    public static func findExercisePr(
        history: [WorkoutSessionRecord],
        exercise: Exercise,
        unit: WeightUnit = .kg
    ) -> String? {
        let targetId = exercise.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetDisplay = exercise.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var bestWeight: Double = 0.0
        var bestReps: Int = 0

        for record in history {
            for log in record.exerciseLogs {
                let logName = log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                var matches = logName == targetName || logName == targetDisplay

                if !matches {
                    if let exId = targetId ?? ExerciseCatalog.canonicalExercises.first(where: { $0.value.name.lowercased() == targetName })?.key {
                        let enName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: exercise.name, lang: "en").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let trName = ContentLocalizer.shared.exerciseName(exerciseId: exId, fallback: exercise.name, lang: "tr").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if logName == enName || logName == trName {
                            matches = true
                        }
                    }
                }

                if !matches { continue }

                for set in log.sets {
                    if set.isWarmup { continue }
                    let weight = set.weightKg ?? 0.0
                    let reps = set.reps ?? 0
                    if weight > 0.0 && reps > 0 {
                        if weight > bestWeight || (weight == bestWeight && reps > bestReps) {
                            bestWeight = weight
                            bestReps = reps
                        }
                    }
                }
            }
        }

        if bestWeight > 0.0 && bestReps > 0 {
            return "\(formatWeight(bestWeight, unit: unit))x\(bestReps)"
        } else {
            return nil
        }
    }

    public static func formatWeight(_ value: Double, unit: WeightUnit = .kg) -> String {
        return unit.formatWeight(value)
    }

    public static func sanitizedWeightInput(_ value: String) -> String? {
        var normalized = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if normalized.isEmpty { return "" }
        if normalized.range(of: #"^0+$"#, options: .regularExpression) != nil { return nil }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if let regex = try? NSRegularExpression(pattern: #"^0+(?=[1-9]|0\.)"#) {
            let range = NSRange(location: 0, length: normalized.utf16.count)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        guard normalized.count <= 7 else { return nil }
        let regex = try! NSRegularExpression(pattern: #"^\d{0,4}(\.\d{0,2})?$"#)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard regex.firstMatch(in: normalized, options: [], range: range) != nil else { return nil }
        return normalized
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

    public static func canCompleteSet(_ set: ExerciseSetLog) -> Bool {
        let weight = set.weightKg ?? Double(set.weightInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        let reps = set.completedReps ?? Int(set.repsInput.trimmingCharacters(in: .whitespaces))
        guard let w = weight, let r = reps else { return false }
        return w >= 1.0 && r >= 1
    }
}
