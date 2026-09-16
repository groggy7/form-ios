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

    public var formattedVolume: String {
        let rounded = Int(totalVolumeKg.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let lang = LanguageManager.shared.currentLanguage
        formatter.locale = Locale(identifier: lang == "tr" ? "tr_TR" : "en_US")
        return formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
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
}
