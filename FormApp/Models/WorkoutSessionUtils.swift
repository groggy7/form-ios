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
        let duration = min(max(0, elapsed), 6 * 3600)
        
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
            return SessionExerciseLog(
                exerciseName: ex.name,
                sets: sets,
                targetSets: target,
                exerciseId: ExerciseCatalog.resolveCanonicalId(stableId: ex.exerciseId, name: ex.name)
            )
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
        var logsById: [String: SessionExerciseLog] = [:]
        for log in record.exerciseLogs {
            let key = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
            logsByName[key] = log
            if let id = log.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                logsById[id] = log
            }
        }

        var result: [String: [ExerciseSetLog]] = [:]
        for (idx, ex) in workout.exercises.enumerated() {
            let targetCount = initialSetCount(exercise: ex)
            let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
            let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()

            let stableId = ExerciseCatalog.resolveCanonicalId(stableId: ex.exerciseId, name: ex.name)
            var matchedLog = stableId.flatMap { logsById[$0] } ?? logsByName[nameKey] ?? logsByName[displayKey]
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

    public static func findPreviousSessionWorkingSets(
        history: [WorkoutSessionRecord],
        exercise: Exercise
    ) -> [SessionSetLog] {
        let targetId = exercise.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetCanonical = ExerciseCatalog.key(exercise.name)

        let sortedRecords = history.sorted { a, b in
            let dateA = a.completedAt.isEmpty ? a.startedAt : a.completedAt
            let dateB = b.completedAt.isEmpty ? b.startedAt : b.completedAt
            return dateA > dateB
        }

        for record in sortedRecords {
            for log in record.exerciseLogs {
                let logName = log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let logCanonical = ExerciseCatalog.key(log.exerciseName)

                let matches = (targetId != nil && (targetId == logName || targetId == logCanonical)) ||
                    logName == targetName ||
                    logCanonical == targetCanonical

                if !matches { continue }

                let validSets = log.sets.filter { !$0.isWarmup && ($0.reps ?? 0) > 0 && ($0.weightKg ?? 0.0) > 0.0 }
                if !validSets.isEmpty {
                    return validSets
                }
            }
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
            let prev = (workingSetIndex < previousSets.count) ? previousSets[workingSetIndex] : previousSets.last!
            let prevWeightKg = prev.weightKg ?? 0.0
            let prevReps = prev.reps ?? 8
            let targetWeightKg = prevWeightKg
            let targetReps = prevReps + 1
            let deltaKg = (unit == .lbs) ? WeightUnit.toCanonicalKg(5.0, unit: .lbs) : 2.5
            let altWeightKg = prevWeightKg + deltaKg
            let altReps = max(1, prevReps - 1)
            return GhostTarget(
                lastWeekWeightKg: prevWeightKg,
                lastWeekReps: prevReps,
                targetWeightKg: targetWeightKg,
                targetReps: targetReps,
                altWeightKg: altWeightKg,
                altReps: altReps,
                isFirstSession: false,
                prescription: exercise.displayPrescription
            )
        } else {
            let (minReps, _) = ProgressionEngine.parseRepRange(exercise: exercise)
            return GhostTarget(
                lastWeekWeightKg: nil,
                lastWeekReps: nil,
                targetWeightKg: 0.0,
                targetReps: minReps,
                altWeightKg: nil,
                altReps: nil,
                isFirstSession: true,
                prescription: exercise.displayPrescription
            )
        }
    }

    public static func evaluateLogbookBeat(
        loggedWeightKg: Double,
        loggedReps: Int,
        target: GhostTarget
    ) -> LogbookBeatResult? {
        guard let prevW = target.lastWeekWeightKg, let prevR = target.lastWeekReps else { return nil }
        if target.isFirstSession || prevW <= 0.0 || prevR <= 0 { return nil }

        let isSameOrHigherWeightMoreReps = loggedWeightKg >= (prevW - 0.01) && loggedReps > prevR
        let isHigherWeightEqualOrMoreReps = loggedWeightKg > (prevW + 0.01) && loggedReps >= prevR
        let isAltLoadTargetMet = target.altWeightKg != nil && target.altReps != nil &&
            loggedWeightKg >= (target.altWeightKg! - 0.01) && loggedReps >= target.altReps!

        let current1RM = loggedWeightKg * (1.0 + Double(loggedReps) / 30.0)
        let prev1RM = prevW * (1.0 + Double(prevR) / 30.0)
        let isEstimated1RMHigher = current1RM > (prev1RM * 1.005) && loggedWeightKg >= (prevW * 0.95)

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
        let repsLabel = (LanguageManager.shared.currentLanguage == "tr") ? "tekrar" : "reps"
        let lastWeekStr = LanguageManager.t(
            "session.ghost.last_week",
            ["weight": "\(prevW) \(unit.label)", "reps": "\(prevR) \(repsLabel)"]
        )

        let repW = formatWeight(target.targetWeightKg, unit: unit)
        let repR = target.targetReps
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
        let currStr = "\(formatWeight(result.currentWeightKg, unit: unit)) \(unit.label) × \(result.currentReps)"
        let prevStr = "\(formatWeight(result.previousWeightKg, unit: unit)) \(unit.label) × \(result.previousReps)"
        return LanguageManager.t("session.logbook.beat_notice", ["current": currStr, "previous": prevStr])
    }

    public struct GhostTarget: Equatable {
        public let lastWeekWeightKg: Double?
        public let lastWeekReps: Int?
        public let targetWeightKg: Double
        public let targetReps: Int
        public let altWeightKg: Double?
        public let altReps: Int?
        public let isFirstSession: Bool
        public let prescription: String

        public init(
            lastWeekWeightKg: Double?,
            lastWeekReps: Int?,
            targetWeightKg: Double,
            targetReps: Int,
            altWeightKg: Double?,
            altReps: Int?,
            isFirstSession: Bool,
            prescription: String = ""
        ) {
            self.lastWeekWeightKg = lastWeekWeightKg
            self.lastWeekReps = lastWeekReps
            self.targetWeightKg = targetWeightKg
            self.targetReps = targetReps
            self.altWeightKg = altWeightKg
            self.altReps = altReps
            self.isFirstSession = isFirstSession
            self.prescription = prescription
        }
    }

    public struct LogbookBeatResult: Equatable {
        public let repDelta: Int
        public let weightDeltaKg: Double
        public let currentWeightKg: Double
        public let currentReps: Int
        public let previousWeightKg: Double
        public let previousReps: Int

        public init(
            repDelta: Int,
            weightDeltaKg: Double,
            currentWeightKg: Double,
            currentReps: Int,
            previousWeightKg: Double,
            previousReps: Int
        ) {
            self.repDelta = repDelta
            self.weightDeltaKg = weightDeltaKg
            self.currentWeightKg = currentWeightKg
            self.currentReps = currentReps
            self.previousWeightKg = previousWeightKg
            self.previousReps = previousReps
        }
    }
}

public typealias GhostTarget = WorkoutSessionUtils.GhostTarget
public typealias LogbookBeatResult = WorkoutSessionUtils.LogbookBeatResult
