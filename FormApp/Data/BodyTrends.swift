import Foundation

// Pro analysis of the body log and the joint-stress journal (docs/design/body-and-joint-journal.md).
// Both describe the user's own entries; neither sets a goal or draws a conclusion.

public struct BodyTrendPoint: Hashable {
    public let date: String
    public let weightKg: Double
    public let trendKg: Double
}

public struct MeasurementChange: Hashable {
    public let metric: BodyMetric
    public let latestCm: Double
    public let changeCm: Double
    public let since: String
}

public struct RelativeStrengthRow: Hashable {
    public let exerciseName: String
    public let estimated1RmKg: Double
    public let ratio: Double
}

public enum RelativeStrengthReport: Equatable {
    /// No bodyweight entry in the last `BodyTrends.recentWeighInDays` days.
    case needsWeighIn
    case noLifts
    case rows(bodyweightKg: Double, rows: [RelativeStrengthRow])
}

public struct BodyTrendReport {
    public let points: [BodyTrendPoint]
    /// Nil until there are enough weigh-ins over a long enough span.
    public let weeklyChangeKg: Double?
    public let measurements: [MeasurementChange]
    public let relativeStrength: RelativeStrengthReport
    public var latest: BodyTrendPoint? { points.last }
}

/// A record's training day, as Rep Lab counts it: the performed date, else the start (or completion) date.
func trainingDay(_ record: WorkoutSessionRecord) -> String? {
    record.performedDate ?? WorkoutCalendar.localDate(from: record.startedAt.isEmpty ? record.completedAt : record.startedAt)
}

public enum BodyTrends {
    public static let retentionPerDay = 0.9
    public static let weeklyWindowDays = 28
    public static let weeklyMinEntries = 3
    public static let weeklyMinSpanDays = 14
    public static let chartDays = 90
    public static let recentWeighInDays = 30
    public static let strengthDays = 90
    public static let strengthRows = 5

    /// Lifts whose bodyweight ratio is a common strength reference: barbell squat, bench press, deadlift, overhead
    /// press and row variations. Machines, dumbbells, isolation and hip-thrust-style lifts are left out: their ratios
    /// are not comparable, and a leg press would otherwise top the list. Android `BodyTrends.REFERENCE_LIFTS` matches.
    public static let referenceLifts: Set<String> = [
        "barbell-back-squat", "barbell-low-bar-squat", "barbell-front-squat", "barbell-pause-full-squat",
        "barbell-bench-press", "incline-barbell-bench-press", "barbell-close-grip-bench-press",
        "conventional-barbell-deadlift", "barbell-sumo-deadlift", "trap-bar-deadlift",
        "standing-barbell-overhead-press", "barbell-seated-overhead-press",
        "barbell-row", "barbell-pendlay-row"
    ]

    public static func report(entries: [BodyEntry], history: [WorkoutSessionRecord], today: String) -> BodyTrendReport {
        let points = trend(entries)
        return BodyTrendReport(points: points, weeklyChangeKg: weeklyChange(points),
                               measurements: measurementChanges(entries, today: today),
                               relativeStrength: relativeStrength(points: points, history: history, today: today))
    }

    /// Exponential moving average; each day since the previous weigh-in keeps 90% of the trend.
    public static func trend(_ entries: [BodyEntry]) -> [BodyTrendPoint] {
        let weighIns = entries.compactMap { entry -> (Int, String, Double)? in
            guard let day = BodyDay.number(entry.date), let weight = entry.bodyweightKg else { return nil }
            return (day, entry.date, weight)
        }.sorted { $0.0 < $1.0 }
        var points: [BodyTrendPoint] = []
        var previousDay: Int?
        for (day, date, weight) in weighIns {
            let trend: Double
            if let previous = points.last, let previousDay {
                let days = max(1, day - previousDay)
                trend = previous.trendKg + (1 - pow(retentionPerDay, Double(days))) * (weight - previous.trendKg)
            } else {
                trend = weight
            }
            points.append(BodyTrendPoint(date: date, weightKg: weight, trendKg: trend))
            previousDay = day
        }
        return points
    }

    /// Least-squares slope of raw weights over the 28 days ending at the latest weigh-in, per week.
    public static func weeklyChange(_ points: [BodyTrendPoint]) -> Double? {
        guard let latest = points.last.flatMap({ BodyDay.number($0.date) }) else { return nil }
        let window = points.compactMap { point -> (Double, Double)? in
            guard let day = BodyDay.number(point.date), latest - day < weeklyWindowDays else { return nil }
            return (Double(day - latest), point.weightKg)
        }
        guard window.count >= weeklyMinEntries, let first = window.first, -first.0 >= Double(weeklyMinSpanDays) else { return nil }
        let meanX = window.map(\.0).reduce(0, +) / Double(window.count)
        let meanY = window.map(\.1).reduce(0, +) / Double(window.count)
        let denominator = window.reduce(0) { $0 + pow($1.0 - meanX, 2) }
        guard denominator > 0 else { return nil }
        let slope = window.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / denominator
        return slope * 7
    }

    /// Latest value and its change from the earliest entry of the last 90 days, for measurements logged twice.
    public static func measurementChanges(_ entries: [BodyEntry], today: String) -> [MeasurementChange] {
        guard let todayNumber = BodyDay.number(today) else { return [] }
        let cutoff = todayNumber - (chartDays - 1)
        return BodyMetric.measurements.compactMap { metric in
            let values = entries.compactMap { entry -> (Int, String, Double)? in
                guard let day = BodyDay.number(entry.date), day >= cutoff, let value = entry.value(metric) else { return nil }
                return (day, entry.date, value)
            }.sorted { $0.0 < $1.0 }
            guard values.count >= 2, let first = values.first, let last = values.last else { return nil }
            return MeasurementChange(metric: metric, latestCm: last.2, changeCm: last.2 - first.2, since: first.1)
        }
    }

    /// Best Brzycki estimate per reference lift (`referenceLifts`) from the last 90 days (Rep Lab's eligibility),
    /// divided by the latest trend.
    public static func relativeStrength(points: [BodyTrendPoint], history: [WorkoutSessionRecord], today: String) -> RelativeStrengthReport {
        guard let latest = points.last, let latestDay = BodyDay.number(latest.date), let todayNumber = BodyDay.number(today),
              todayNumber - latestDay <= recentWeighInDays else { return .needsWeighIn }
        let cutoff = todayNumber - (strengthDays - 1)
        var order: [String] = []
        var best: [String: (name: String, estimate: Double)] = [:]
        for record in history {
            guard let day = BodyDay.number(trainingDay(record)), day >= cutoff, day <= todayNumber else { continue }
            for log in record.exerciseLogs {
                let name = log.exerciseName
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      let key = ExerciseCatalog.resolveCanonicalId(stableId: log.exerciseId, name: name),
                      referenceLifts.contains(key) else { continue }
                let estimate = log.sets.filter { !$0.isWarmup }
                    .map { FormLabEngine.calculateEstimated1RM(weightKg: $0.weightKg ?? 0, reps: $0.reps ?? 0, formula: .brzycki) }
                    .max() ?? 0
                guard estimate > 0 else { continue }
                let displayName = ExerciseCatalog.canonicalExercises[key]?.name ?? name
                if best[key] == nil { order.append(key) }
                if estimate > (best[key]?.estimate ?? 0) { best[key] = (displayName, estimate) }
            }
        }
        guard !best.isEmpty else { return .noLifts }
        let rows = order.compactMap { best[$0] }
            .enumerated().sorted { $0.element.estimate != $1.element.estimate ? $0.element.estimate > $1.element.estimate : $0.offset < $1.offset }
            .prefix(strengthRows)
            .map { RelativeStrengthRow(exerciseName: $0.element.name, estimated1RmKg: $0.element.estimate, ratio: $0.element.estimate / latest.trendKg) }
        return .rows(bodyweightKg: latest.trendKg, rows: Array(rows))
    }
}

/// One rated session: its date, the user's rating and the heaviest working load (nil when none was logged).
public struct JointRatingEntry: Hashable {
    public let date: String
    public let rating: JointStress
    public let topLoadKg: Double?
}

public struct JointExerciseSummary: Hashable, Identifiable {
    public let exerciseName: String
    /// Oldest first, at most `JointJournal.maxShown`.
    public let recent: [JointRatingEntry]
    public let total: Int
    public let high: Int
    public let mild: Int
    public let none: Int
    public let latest: String
    public var id: String { exerciseName }
}

/// Rep Lab's Joints tab: the user's own ratings next to the load lifted. It interprets nothing.
public enum JointJournal {
    public static let windowDays = 56
    public static let maxShown = 12

    /// `record` with exercise `logIndex` rated `rating` (nil clears it), or nil when that exercise has no working set
    /// to rate. History can rate an exercise after the workout because joint discomfort often shows up later; nothing
    /// else in the record changes. Android `JointJournal.rated` matches.
    public static func rated(_ record: WorkoutSessionRecord, logIndex: Int, rating: JointStress?) -> WorkoutSessionRecord? {
        guard record.exerciseLogs.indices.contains(logIndex),
              record.exerciseLogs[logIndex].sets.contains(where: { !$0.isWarmup }) else { return nil }
        var updated = record
        updated.exerciseLogs[logIndex].jointStress = rating?.rawValue
        return updated
    }

    public static func summaries(history: [WorkoutSessionRecord], today: String) -> [JointExerciseSummary] {
        guard let todayNumber = BodyDay.number(today) else { return [] }
        let cutoff = todayNumber - (windowDays - 1)
        var names: [String: String] = [:]
        var ratings: [String: [(Int, JointRatingEntry)]] = [:]
        for record in history {
            guard let dayString = trainingDay(record), let day = BodyDay.number(dayString), day >= cutoff, day <= todayNumber else { continue }
            for log in record.exerciseLogs {
                guard let rating = log.jointStress.flatMap(JointStress.init(rawValue:)) else { continue }
                let name = log.exerciseName
                guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let canonicalId = ExerciseCatalog.resolveCanonicalId(stableId: log.exerciseId, name: name)
                let key = canonicalId ?? "name:\(ExerciseCatalog.key(name))"
                if names[key] == nil { names[key] = canonicalId.flatMap { ExerciseCatalog.canonicalExercises[$0]?.name } ?? name }
                let topLoad = log.sets.filter { !$0.isWarmup }.compactMap(\.weightKg).filter { $0 > 0 }.max()
                ratings[key, default: []].append((day, JointRatingEntry(date: dayString, rating: rating, topLoadKg: topLoad)))
            }
        }
        return ratings.compactMap { key, entries -> JointExerciseSummary? in
            let sorted = entries.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 < $1.element.0 : $0.offset < $1.offset }.map(\.element.1)
            guard let last = sorted.last, let name = names[key] else { return nil }
            return JointExerciseSummary(
                exerciseName: name, recent: Array(sorted.suffix(maxShown)), total: sorted.count,
                high: sorted.filter { $0.rating == .high }.count, mild: sorted.filter { $0.rating == .mild }.count,
                none: sorted.filter { $0.rating == .noStress }.count, latest: last.date)
        }.sorted {
            if $0.high != $1.high { return $0.high > $1.high }
            if $0.mild != $1.mild { return $0.mild > $1.mild }
            if $0.latest != $1.latest { return $0.latest > $1.latest }
            return $0.exerciseName < $1.exerciseName
        }
    }
}
