import Foundation

public struct WeeklyGoalProgressMetrics: Equatable {
    public let completedWorkouts: Int
    public let totalWorkouts: Int
    public let totalVolumeKg: Double
    public let activeDurationSeconds: Int
    public let prsHitCount: Int
    public let hasUnfinishedProgress: Bool

    public init(
        completedWorkouts: Int,
        totalWorkouts: Int,
        totalVolumeKg: Double,
        activeDurationSeconds: Int,
        prsHitCount: Int,
        hasUnfinishedProgress: Bool = false
    ) {
        self.completedWorkouts = completedWorkouts
        self.totalWorkouts = totalWorkouts
        self.totalVolumeKg = totalVolumeKg
        self.activeDurationSeconds = activeDurationSeconds
        self.prsHitCount = prsHitCount
        self.hasUnfinishedProgress = hasUnfinishedProgress
    }

    public var progressFraction: Double {
        if totalWorkouts <= 0 { return 0.0 }
        return min(1.0, max(0.0, Double(completedWorkouts) / Double(totalWorkouts)))
    }

    public func formattedVolume(unit: WeightUnit = .kg) -> String {
        let display = unit.toDisplay(totalVolumeKg)
        let rounded = Int(display.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let lang = LanguageManager.shared.currentLanguage
        formatter.locale = Locale(identifier: lang == "tr" ? "tr_TR" : "en_US")
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    }

    public var formattedVolume: String {
        return formattedVolume(unit: .kg)
    }

    public var formattedActiveTime: String {
        let hours = activeDurationSeconds / 3600
        let minutes = (activeDurationSeconds % 3600) / 60
        let isTr = LanguageManager.shared.currentLanguage == "tr"
        if hours > 0 {
            return isTr ? "\(hours) sa \(minutes) dk" : "\(hours)h \(minutes)m"
        } else {
            return isTr ? "\(minutes) dk" : "\(minutes)m"
        }
    }
}

public enum PersonalRecordTracker {

    public static func normalizeExerciseKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func recordDate(_ timestamp: String?, timeZone: TimeZone = .current) -> Date? {
        guard let ts = timestamp, !ts.isEmpty else { return nil }
        return WorkoutCalendar.parseIsoTimestamp(ts) ?? WorkoutCalendar.parseDate(ts, timeZone: timeZone)
    }

    public static func isRecordInWeek(
        _ record: WorkoutSessionRecord,
        targetWeekKey: String,
        timeZone: TimeZone = .current
    ) -> Bool {
        guard !targetWeekKey.isEmpty else { return false }
        guard let date = recordDate(record.completedAt, timeZone: timeZone)
                ?? recordDate(record.startedAt, timeZone: timeZone) else {
            return false
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        let weekKey = String(format: "%04d-W%02d", year, week)
        return weekKey == targetWeekKey
    }

    /**
     * Calculates weekly PRs hit according to the rule:
     * - The first recorded weight for an exercise establishes its initial weight (not a PR).
     * - When that weight is passed (weight > previous max recorded weight), a PR is hit.
     */
    public static func countPrsForWeek(
        history: [WorkoutSessionRecord],
        currentWeekKey: String,
        activeSession: ActiveSessionDraft? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Int {
        var records = history

        if let active = activeSession {
            let activeSets = active.setsByExercise.values.flatMap { $0 }
            if activeSets.contains(where: { $0.isCompleted && ($0.weightKg ?? 0.0) > 0.0 }) {
                let nowMillis = Int64(now.timeIntervalSince1970 * 1000.0)
                let activeRecord = SessionProgress.from(draft: active, nowEpochMillis: nowMillis)
                    .record(draft: active, completedAtEpochMillis: nowMillis)
                records.append(activeRecord)
            }
        }

        let sortedRecords = records.sorted { (r1, r2) -> Bool in
            let d1 = r1.startedAt.isEmpty ? r1.completedAt : r1.startedAt
            let d2 = r2.startedAt.isEmpty ? r2.completedAt : r2.startedAt
            return d1 < d2
        }

        var maxWeightByExercise: [String: Double] = [:]
        var prsInCurrentWeek = 0

        for record in sortedRecords {
            let isThisWeek = isRecordInWeek(record, targetWeekKey: currentWeekKey, timeZone: timeZone)
            for exerciseLog in record.exerciseLogs {
                let key = normalizeExerciseKey(exerciseLog.exerciseName)
                let validSets = exerciseLog.sets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                guard let maxSessionWeight = validSets.compactMap({ $0.weightKg }).max() else {
                    continue
                }

                if let previousMax = maxWeightByExercise[key] {
                    if maxSessionWeight > previousMax {
                        maxWeightByExercise[key] = maxSessionWeight
                        if isThisWeek {
                            prsInCurrentWeek += 1
                        }
                    }
                } else {
                    // First recorded weight for this exercise; baseline, not a PR
                    maxWeightByExercise[key] = maxSessionWeight
                }
            }
        }

        return prsInCurrentWeek
    }

    public static func computeWeeklyMetrics(
        program: Program?,
        completedKeys: [String],
        history: [WorkoutSessionRecord],
        currentWeekKey: String,
        activeSession: ActiveSessionDraft? = nil,
        unfinishedKeys: Set<String> = [],
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> WeeklyGoalProgressMetrics {
        let totalWorkouts = program?.workouts.count ?? 0
        let completedCount = program?.workouts.filter { workout in
            let key = "\(program?.id ?? ""):\(workout.id)"
            return completedKeys.contains(key)
        }.count ?? 0

        let currentWeekRecords = history.filter { isRecordInWeek($0, targetWeekKey: currentWeekKey, timeZone: timeZone) }

        var volume: Double = currentWeekRecords.reduce(0.0) { $0 + $1.totalVolumeKg }
        var duration: Int = currentWeekRecords.reduce(0) { $0 + $1.durationSeconds }

        if let active = activeSession {
            let activeSets = active.setsByExercise.values.flatMap { $0 }
            let completedActive = activeSets.filter { $0.isCompleted }
            for s in completedActive {
                let w = s.weightKg ?? 0.0
                let r = Double(s.completedReps ?? 0)
                volume += w * r
            }
            let nowMillis = Int64(now.timeIntervalSince1970 * 1000.0)
            let elapsed = Int(max(0, (nowMillis - active.startedAtEpochMillis) / 1000))
            duration += elapsed
        }

        let prsCount = countPrsForWeek(
            history: history,
            currentWeekKey: currentWeekKey,
            activeSession: activeSession,
            now: now,
            timeZone: timeZone
        )

        let hasUnfinished = !unfinishedKeys.isEmpty || (activeSession != nil && activeSession?.programId == program?.id)

        return WeeklyGoalProgressMetrics(
            completedWorkouts: completedCount,
            totalWorkouts: totalWorkouts,
            totalVolumeKg: volume,
            activeDurationSeconds: duration,
            prsHitCount: prsCount,
            hasUnfinishedProgress: hasUnfinished
        )
    }

    public static func findSessionPrExercises(
        history: [WorkoutSessionRecord],
        targetRecord: WorkoutSessionRecord
    ) -> Set<String> {
        let sortedRecords = history
            .filter { $0.id != targetRecord.id }
            .sorted { (r1, r2) -> Bool in
                let d1 = r1.startedAt.isEmpty ? r1.completedAt : r1.startedAt
                let d2 = r2.startedAt.isEmpty ? r2.completedAt : r2.startedAt
                return d1 < d2
            }

        let targetTimestamp = targetRecord.startedAt.isEmpty ? targetRecord.completedAt : targetRecord.startedAt
        let priorRecords = sortedRecords.filter { r in
            let ts = r.startedAt.isEmpty ? r.completedAt : r.startedAt
            return ts.isEmpty || targetTimestamp.isEmpty || ts < targetTimestamp
        }

        var maxWeightByExercise: [String: Double] = [:]
        for record in priorRecords {
            for exerciseLog in record.exerciseLogs {
                let key = normalizeExerciseKey(exerciseLog.exerciseName)
                let maxSessionWeight = exerciseLog.sets
                    .filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                    .compactMap { $0.weightKg }
                    .max()
                guard let maxWeight = maxSessionWeight else { continue }

                if let prev = maxWeightByExercise[key] {
                    if maxWeight > prev {
                        maxWeightByExercise[key] = maxWeight
                    }
                } else {
                    maxWeightByExercise[key] = maxWeight
                }
            }
        }

        var prExercises = Set<String>()
        for exerciseLog in targetRecord.exerciseLogs {
            let key = normalizeExerciseKey(exerciseLog.exerciseName)
            let maxSessionWeight = exerciseLog.sets
                .filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                .compactMap { $0.weightKg }
                .max()
            guard let maxWeight = maxSessionWeight else { continue }

            if let prev = maxWeightByExercise[key], maxWeight > prev {
                prExercises.insert(key)
            }
        }

        return prExercises
    }

    public static func calculateEstimated1RM(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0.0, reps > 0 else { return 0.0 }
        if reps == 1 { return weightKg }
        let clampedReps = min(reps, 36)
        return weightKg * (36.0 / (37.0 - Double(clampedReps)))
    }

    public static func computeExerciseHistoryStats(
        history: [WorkoutSessionRecord],
        exerciseName: String,
        exerciseDisplayName: String? = nil
    ) -> ExerciseHistoryStats {
        let targetKey = normalizeExerciseKey(exerciseName)
        let targetDisplayKey = exerciseDisplayName.map { normalizeExerciseKey($0) }

        var matchingSessions: [ExerciseSessionHistoryEntry] = []
        var allValidSets: [SessionSetLog] = []
        var totalVolume: Double = 0.0

        let sortedRecords = history.sorted { r1, r2 in
            let d1 = r1.startedAt.isEmpty ? r1.completedAt : r1.startedAt
            let d2 = r2.startedAt.isEmpty ? r2.completedAt : r2.startedAt
            return d1 > d2
        }

        for record in sortedRecords {
            guard let matchingLog = record.exerciseLogs.first(where: { log in
                let logKey = normalizeExerciseKey(log.exerciseName)
                return logKey == targetKey || (targetDisplayKey != nil && logKey == targetDisplayKey)
            }) else { continue }

            let validSets = matchingLog.sets.filter { ($0.weightKg ?? 0.0) > 0.0 || ($0.reps ?? 0) > 0 }
            if !validSets.isEmpty {
                let dateStr = record.startedAt.isEmpty ? record.completedAt : record.startedAt
                matchingSessions.append(
                    ExerciseSessionHistoryEntry(
                        sessionId: record.id,
                        date: dateStr,
                        workoutTitle: record.workoutTitle,
                        sets: validSets
                    )
                )
                for s in validSets {
                    allValidSets.append(s)
                    let w = s.weightKg ?? 0.0
                    let r = Double(s.reps ?? 0)
                    if w > 0.0 && r > 0 {
                        totalVolume += w * r
                    }
                }
            }
        }

        if allValidSets.isEmpty {
            return ExerciseHistoryStats()
        }

        let weightedSets = allValidSets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
        let prSet: SessionSetLog?
        if !weightedSets.isEmpty {
            prSet = weightedSets.max { s1, s2 in
                let rm1 = calculateEstimated1RM(weightKg: s1.weightKg ?? 0.0, reps: s1.reps ?? 0)
                let rm2 = calculateEstimated1RM(weightKg: s2.weightKg ?? 0.0, reps: s2.reps ?? 0)
                if abs(rm1 - rm2) > 0.001 {
                    return rm1 < rm2
                }
                if let w1 = s1.weightKg, let w2 = s2.weightKg, abs(w1 - w2) > 0.001 {
                    return w1 < w2
                }
                return (s1.reps ?? 0) < (s2.reps ?? 0)
            }
        } else {
            prSet = allValidSets.max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        }

        var est1rm: Double? = nil
        if let pr = prSet, let w = pr.weightKg, let r = pr.reps, w > 0.0, r > 0 {
            est1rm = calculateEstimated1RM(weightKg: w, reps: r)
        }

        return ExerciseHistoryStats(
            prWeightKg: prSet?.weightKg,
            prReps: prSet?.reps,
            estimated1rmKg: est1rm,
            totalVolumeKg: totalVolume,
            lifetimeSets: allValidSets.count,
            recentSessions: matchingSessions
        )
    }
}

public struct ExerciseSessionHistoryEntry: Identifiable, Hashable {
    public var id: String { sessionId }
    public var sessionId: String
    public var date: String
    public var workoutTitle: String
    public var sets: [SessionSetLog]

    public init(sessionId: String, date: String, workoutTitle: String, sets: [SessionSetLog]) {
        self.sessionId = sessionId
        self.date = date
        self.workoutTitle = workoutTitle
        self.sets = sets
    }
}

public struct ExerciseHistoryStats: Hashable {
    public var prWeightKg: Double?
    public var prReps: Int?
    public var estimated1rmKg: Double?
    public var totalVolumeKg: Double
    public var lifetimeSets: Int
    public var recentSessions: [ExerciseSessionHistoryEntry]

    public init(
        prWeightKg: Double? = nil,
        prReps: Int? = nil,
        estimated1rmKg: Double? = nil,
        totalVolumeKg: Double = 0.0,
        lifetimeSets: Int = 0,
        recentSessions: [ExerciseSessionHistoryEntry] = []
    ) {
        self.prWeightKg = prWeightKg
        self.prReps = prReps
        self.estimated1rmKg = estimated1rmKg
        self.totalVolumeKg = totalVolumeKg
        self.lifetimeSets = lifetimeSets
        self.recentSessions = recentSessions
    }
}
