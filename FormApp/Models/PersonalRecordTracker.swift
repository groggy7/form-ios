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
        unit.formatVolume(totalVolumeKg)
    }

    public var formattedVolume: String {
        return formattedVolume(unit: .kg)
    }

    public var formattedActiveTime: String {
        let hours = activeDurationSeconds / 3600
        let minutes = (activeDurationSeconds % 3600) / 60
        return LanguageManager.t(hours > 0 ? "duration.short" : "duration.minutes", ["hours":hours,"minutes":minutes])
    }
}

public enum PersonalRecordTracker {

    /// A resumed draft replaces its saved partial record; both contain the same completed sets.
    private static func recordsWithActiveSession(
        history: [WorkoutSessionRecord], activeSession: ActiveSessionDraft?, now: Date, timeZone: TimeZone
    ) -> [WorkoutSessionRecord] {
        guard let active = activeSession else { return history }
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        var record = SessionProgress.from(draft: active, nowEpochMillis: nowMillis)
            .record(draft: active, completedAtEpochMillis: nowMillis)
        // Live totals belong to the assigned training day, including sessions spanning Monday.
        record.performedDate = active.assignedCalendarDate ?? WorkoutCalendar.localDate(from: active.startedAt, timeZone: timeZone)
        return history.filter { $0.id != active.id } + [record]
    }

    public static func normalizeExerciseKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func recordDate(_ timestamp: String?, timeZone: TimeZone = .current) -> Date? {
        guard let ts = timestamp, !ts.isEmpty else { return nil }
        return WorkoutCalendar.parseIsoTimestamp(ts) ?? WorkoutCalendar.parseDate(ts, timeZone: timeZone)
    }

    private struct CalendarKey: Hashable {
        let identifier: Calendar.Identifier
        let timeZone: TimeZone
    }
    private static let calendarLock = NSLock()
    private static var calendars: [CalendarKey: Calendar] = [:]

    /// Creating a calendar per record dominated weekly totals over long histories.
    private static func cachedCalendar(_ identifier: Calendar.Identifier, _ timeZone: TimeZone) -> Calendar {
        let key = CalendarKey(identifier: identifier, timeZone: timeZone)
        calendarLock.lock()
        defer { calendarLock.unlock() }
        if let cached = calendars[key] { return cached }
        var calendar = Calendar(identifier: identifier); calendar.timeZone = timeZone
        calendars[key] = calendar
        return calendar
    }

    public static func trainingDate(_ record: WorkoutSessionRecord, timeZone: TimeZone = .current) -> Date? {
        if let day = record.performedDate, let date = WorkoutCalendar.parseDate(day, timeZone: timeZone) { return date }
        guard let date = recordDate(record.startedAt.isEmpty ? record.completedAt : record.startedAt, timeZone: timeZone) else { return nil }
        return cachedCalendar(.gregorian, timeZone).startOfDay(for: date)
    }

    /// A record's place in training order: its training day, then when it started.
    struct TrainingKey {
        let day: Date?
        let started: Date?

        init(_ record: WorkoutSessionRecord, timeZone: TimeZone) {
            day = trainingDate(record, timeZone: timeZone)
            started = recordDate(record.startedAt.isEmpty ? record.completedAt : record.startedAt, timeZone: timeZone)
        }

        func precedes(_ other: TrainingKey) -> Bool {
            let left = day ?? .distantPast, right = other.day ?? .distantPast
            if left != right { return left < right }
            return (started ?? .distantPast) < (other.started ?? .distantPast)
        }
    }

    public static func precedes(_ a: WorkoutSessionRecord, _ b: WorkoutSessionRecord, timeZone: TimeZone = .current) -> Bool {
        TrainingKey(a, timeZone: timeZone).precedes(TrainingKey(b, timeZone: timeZone))
    }

    public static func isRecordInWeek(
        _ record: WorkoutSessionRecord,
        targetWeekKey: String,
        timeZone: TimeZone = .current
    ) -> Bool {
        guard !targetWeekKey.isEmpty else { return false }
        guard let date = trainingDate(record, timeZone: timeZone) else {
            return false
        }
        return isoWeekKey(date, timeZone: timeZone) == targetWeekKey
    }

    public static func isoWeekKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let calendar = cachedCalendar(.iso8601, timeZone)
        return String(format: "%04d-W%02d", calendar.component(.yearForWeekOfYear, from: date), calendar.component(.weekOfYear, from: date))
    }

    /**
     * Counts one observed weight, assistance or rep record per exercise per workout.
     * The first session establishes its baseline; see RecordEngine and the shared fixtures.
     */
    public static func countPrsForWeek(
        history: [WorkoutSessionRecord], currentWeekKey: String,
        activeSession: ActiveSessionDraft? = nil, now: Date = Date(), timeZone: TimeZone = .current
    ) -> Int {
        var seen = Set<String>()
        let records = recordsWithActiveSession(history: history, activeSession: activeSession, now: now, timeZone: timeZone).filter { seen.insert($0.id).inserted }
        // Resolve each record's training position once; comparing parsed dates per pair made Home redraws scale with history.
        let keys = records.map { TrainingKey($0, timeZone: timeZone) }
        return records.indices.reduce(0) { total, index in
            guard !currentWeekKey.isEmpty, let day = keys[index].day, isoWeekKey(day, timeZone: timeZone) == currentWeekKey else { return total }
            let target = records[index]
            let prior = records.indices.filter { records[$0].id != target.id && keys[$0].precedes(keys[index]) }.map { records[$0] }
            return total + RecordEngine.forPriorRecords(prior, target: target).count
        }
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

        let currentWeekRecords = recordsWithActiveSession(history: history, activeSession: activeSession, now: now, timeZone: timeZone)
            .filter { isRecordInWeek($0, targetWeekKey: currentWeekKey, timeZone: timeZone) }
        let volume = currentWeekRecords.reduce(0.0) { $0 + WorkoutSessionUtils.resistanceVolume($1) }
        let duration = currentWeekRecords.reduce(0) { $0 + $1.durationSeconds }

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
        history: [WorkoutSessionRecord], targetRecord: WorkoutSessionRecord
    ) -> Set<String> {
        Set(RecordEngine.forSession(history: history, target: targetRecord).map { normalizeExerciseKey($0.exerciseName) })
    }

    public static func calculateEstimated1RM(weightKg: Double, reps: Int) -> Double {
        FormLabEngine.calculateEstimated1RM(weightKg: weightKg, reps: reps)
    }

    public static func computeExerciseHistoryStats(
        history: [WorkoutSessionRecord],
        exerciseName: String,
        exerciseDisplayName: String? = nil
    ) -> ExerciseHistoryStats {
        let assisted = WorkoutSessionUtils.isAssisted(exerciseId: nil, name: exerciseName)
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
                        sets: validSets, isAssisted: assisted
                    )
                )
                for s in validSets {
                    allValidSets.append(s)
                    let w = s.weightKg ?? 0.0
                    let r = Double(s.reps ?? 0)
                    if !assisted && w > 0.0 && r > 0 {
                        totalVolume += IntensitySets.loadVolume(s)
                    }
                }
            }
        }

        if allValidSets.isEmpty {
            return ExerciseHistoryStats()
        }

        let workingSets = allValidSets.filter { !$0.isWarmup }
        let weightedSets = workingSets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
        let prSet: SessionSetLog?
        if assisted {
            prSet = workingSets.filter { ($0.reps ?? 0) > 0 && $0.weightKg.map { $0.isFinite && $0 >= 0 } == true }.max { a, b in
                if a.weightKg != b.weightKg { return a.weightKg! > b.weightKg! }
                return (a.reps ?? 0) < (b.reps ?? 0)
            }
        } else if !weightedSets.isEmpty {
            prSet = weightedSets.max { s1, s2 in
                if let w1 = s1.weightKg, let w2 = s2.weightKg, abs(w1 - w2) > 0.001 {
                    return w1 < w2
                }
                return (s1.reps ?? 0) < (s2.reps ?? 0)
            }
        } else {
            prSet = workingSets.max { ($0.reps ?? 0) < ($1.reps ?? 0) }
        }

        var est1rm: Double? = nil
        var estimateSourceSet: SessionSetLog? = nil
        var estimateSourceDate: String? = nil
        for session in matchingSessions {
            for set in session.sets where !set.isWarmup && !assisted {
                let estimate = calculateEstimated1RM(weightKg: set.weightKg ?? 0, reps: set.reps ?? 0)
                if estimate > (est1rm ?? 0) {
                    est1rm = estimate
                    estimateSourceSet = set
                    estimateSourceDate = session.date
                }
            }
        }

        return ExerciseHistoryStats(
            prWeightKg: prSet?.weightKg,
            prReps: prSet?.reps,
            estimated1rmKg: est1rm,
            estimateSourceSet: estimateSourceSet,
            estimateSourceDate: estimateSourceDate,
            totalVolumeKg: totalVolume,
            lifetimeSets: allValidSets.count,
            recentSessions: matchingSessions, isAssisted: assisted
        )
    }
}

public struct ExerciseSessionHistoryEntry: Identifiable, Hashable {
    public var id: String { sessionId }
    public var sessionId: String
    public var date: String
    public var workoutTitle: String
    public var sets: [SessionSetLog]
    public var isAssisted: Bool = false

    public init(sessionId: String, date: String, workoutTitle: String, sets: [SessionSetLog], isAssisted: Bool = false) {
        self.sessionId = sessionId
        self.date = date
        self.workoutTitle = workoutTitle
        self.sets = sets
        self.isAssisted = isAssisted
    }

    public func bestSet(weightUnit: WeightUnit) -> String? {
        let nonWarmup = sets.filter { !$0.isWarmup && (($0.weightKg ?? 0) > 0 || ($0.reps ?? 0) > 0) }
        let candidates = nonWarmup.isEmpty ? sets.filter { ($0.weightKg ?? 0) > 0 || ($0.reps ?? 0) > 0 } : nonWarmup
        guard !candidates.isEmpty else { return nil }

        if isAssisted {
            let eligible = candidates.filter { ($0.reps ?? 0) > 0 && $0.weightKg.map { $0.isFinite && $0 >= 0 } == true }
            guard let best = eligible.max(by: { a, b in
                if a.weightKg != b.weightKg { return a.weightKg! > b.weightKg! }
                return (a.reps ?? 0) < (b.reps ?? 0)
            }) else { return nil }
            return "\(weightUnit.formatWeight(best.weightKg!)) \(weightUnit.label) \(LanguageManager.t("table.assistance")) × \(best.reps!)"
        }
        let weighted = candidates.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
        if let bestWeighted = weighted.max(by: { s1, s2 in
            let w1 = s1.weightKg ?? 0
            let w2 = s2.weightKg ?? 0
            if abs(w1 - w2) > 0.001 { return w1 < w2 }
            return (s1.reps ?? 0) < (s2.reps ?? 0)
        }) {
            return "\(weightUnit.formatWeight(bestWeighted.weightKg ?? 0)) \(weightUnit.label) × \(bestWeighted.reps ?? 0)"
        }

        if let bestReps = candidates.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }) {
            return "\(bestReps.reps ?? 0) reps"
        }
        return nil
    }
}

public struct ExerciseHistoryStats: Hashable {
    public var prWeightKg: Double?
    public var prReps: Int?
    public var estimated1rmKg: Double?
    public var estimateSourceSet: SessionSetLog?
    public var estimateSourceDate: String?
    public var totalVolumeKg: Double
    public var lifetimeSets: Int
    public var recentSessions: [ExerciseSessionHistoryEntry]
    public var isAssisted: Bool

    public init(
        prWeightKg: Double? = nil,
        prReps: Int? = nil,
        estimated1rmKg: Double? = nil,
        estimateSourceSet: SessionSetLog? = nil,
        estimateSourceDate: String? = nil,
        totalVolumeKg: Double = 0.0,
        lifetimeSets: Int = 0,
        recentSessions: [ExerciseSessionHistoryEntry] = [],
        isAssisted: Bool = false
    ) {
        self.prWeightKg = prWeightKg
        self.prReps = prReps
        self.estimated1rmKg = estimated1rmKg
        self.estimateSourceSet = estimateSourceSet
        self.estimateSourceDate = estimateSourceDate
        self.totalVolumeKg = totalVolumeKg
        self.lifetimeSets = lifetimeSets
        self.recentSessions = recentSessions
        self.isAssisted = isAssisted
    }
}
