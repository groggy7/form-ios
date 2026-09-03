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
        let elapsed = Int((nowEpochMillis - draft.startedAtEpochMillis) / 1000)
        let duration = min(max(0, elapsed), 8 * 3600)
        
        var volume: Double = 0
        for s in completed {
            let w = s.weightKg ?? 0
            let r = s.completedReps ?? 0
            volume += w * Double(r)
        }

        let logs = draft.workout.exercises.map { ex -> SessionExerciseLog in
            let sets = draft.setsByExercise[ex.id]?.filter { $0.isCompleted }.map {
                SessionSetLog(setNumber: $0.setNumber, weightKg: $0.weightKg, reps: $0.completedReps)
            } ?? []
            return SessionExerciseLog(exerciseName: ex.name, sets: sets)
        }

        let hasProg = allSets.contains {
            $0.isCompleted || !$0.weightInput.trimmingCharacters(in: .whitespaces).isEmpty || !$0.repsInput.trimmingCharacters(in: .whitespaces).isEmpty
        }

        return SessionProgress(
            durationSeconds: duration,
            completedSets: completed.count,
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
    public static func isComplete(draft: ActiveSessionDraft) -> Bool {
        guard !draft.workout.exercises.isEmpty else { return false }
        return draft.workout.exercises.allSatisfy { ex in
            let sets = draft.setsByExercise[ex.id] ?? []
            return !sets.isEmpty && sets.allSatisfy { $0.isCompleted }
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

    public static func restoreSetsFromHistory(workout: Workout, record: WorkoutSessionRecord) -> [String: [ExerciseSetLog]] {
        var logsByName: [String: SessionExerciseLog] = [:]
        for log in record.exerciseLogs {
            logsByName[log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()] = log
        }

        var result: [String: [ExerciseSetLog]] = [:]
        for ex in workout.exercises {
            let targetCount = initialSetCount(exercise: ex)
            let log = logsByName[ex.name.trimmingCharacters(in: .whitespaces).lowercased()]
            let completedLogs = log?.sets ?? []

            if !completedLogs.isEmpty {
                var restored = completedLogs.map { s in
                    ExerciseSetLog(
                        setNumber: s.setNumber,
                        weightInput: s.weightKg.map { formatWeight($0) } ?? "",
                        repsInput: (s.reps ?? 0) > 0 ? "\(s.reps!)" : "",
                        weightKg: s.weightKg,
                        completedReps: (s.reps ?? 0) > 0 ? s.reps : nil,
                        isCompleted: true
                    )
                }
                let maxNum = restored.map { $0.setNumber }.max() ?? 0
                let needed = max(targetCount, maxNum)
                if needed > restored.count {
                    for num in (restored.count + 1)...needed {
                        restored.append(ExerciseSetLog(setNumber: num))
                    }
                }
                result[ex.id] = restored
            } else {
                result[ex.id] = (1...targetCount).map { ExerciseSetLog(setNumber: $0) }
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

    public static func formatWeight(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(value))"
        }
        return "\(value)"
    }

    public static func sanitizedWeightInput(_ value: String) -> String? {
        let normalized = value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
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
}
