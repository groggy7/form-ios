import Foundation

public enum SocialCardKind { case summary, record, week }
public struct SocialMetric { public let key: String; public let value: String }
/// Export allowlist: cannot carry sessions, ratings, notes, body metrics or Health data.
public struct SocialCardContent: Identifiable {
    public let id: String
    public let kind: SocialCardKind
    public let title: String
    public let result: String
    public let detail: String
    public var previous: String? = nil
    public var date: String? = nil
    public var metrics: [SocialMetric] = []
    public var primary: Set<String> = []
    public var secondary: Set<String> = []
}
public struct SocialShareRequest: Identifiable {
    public let id = UUID()
    public let cards: [SocialCardContent]
    public var suggested = false
}

public enum SocialCards {
    private static func t(_ key: String, _ values: [String: Any] = [:]) -> String { LanguageManager.t("social." + key, values) }
    private static func number(_ value: Double, _ unit: WeightUnit) -> String {
        let formatter = NumberFormatter(); formatter.locale = LanguageManager.numberLocale
        formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false; formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: unit.toDisplay(value))) ?? ""
    }
    private static func setText(_ set: SessionSetLog, _ unit: WeightUnit, _ assisted: Bool, _ bodyweight: Bool = false) -> String {
        if !assisted && set.weightKg == 0 { return t("reps", ["count": set.reps ?? 0]) }
        return "\(bodyweight && !assisted ? "BW +" : "")\(number(set.weightKg ?? 0, unit)) \(unit.label)\(assisted ? " " + t("assistance") : "") × \(set.reps ?? 0)"
    }
    private static func date(_ record: WorkoutSessionRecord) -> String? {
        guard let date = PersonalRecordTracker.trainingDate(record) else { return nil }
        return formatDate(date)
    }
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = LanguageManager.locale; formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    public static func workout(history: [WorkoutSessionRecord], record: WorkoutSessionRecord, unit: WeightUnit) -> [SocialCardContent] {
        let logs = record.exerciseLogs.filter { !RecordEngine.workingSets($0).isEmpty }
        let sets = logs.reduce(0) { $0 + RecordEngine.workingSets($1).count }
        guard sets > 0 else { return [] }
        let records = RecordEngine.forSession(history: history, target: record)
        let targets = record.exerciseLogs.reduce(0) { $0 + max(0, $1.targetSets ?? RecordEngine.workingSets($1).count) }
        let complete = record.isComplete ?? (targets > 0 && sets >= targets)
        let profiles = logs.compactMap { ExerciseMuscleCatalog.shared?.profile(ExerciseCatalog.resolveCanonicalId(stableId: $0.exerciseId, name: $0.exerciseName)) }
        let primary = Set(profiles.flatMap(\.primary))
        let secondary = Set(profiles.flatMap(\.secondary)).subtracting(primary)
        let volume = logs.filter { !WorkoutSessionUtils.isAssisted(exerciseId: $0.exerciseId, name: $0.exerciseName) }
            .reduce(0.0) { total, log in total + RecordEngine.workingSets(log).reduce(0.0) { $0 + IntensitySets.loadVolume($1) } }
        var metrics: [SocialMetric] = []
        if record.durationSeconds > 0 { metrics.append(SocialMetric(key: "duration", value: RestTimerUtils.formatSecondsToTime(record.durationSeconds))) }
        metrics.append(SocialMetric(key: "exercises", value: "\(logs.count)"))
        if volume > 0 { metrics.append(SocialMetric(key: "volume", value: "\(unit.formatVolume(volume)) \(unit.label)")) }
        let summary = SocialCardContent(id: record.id, kind: .summary,
            title: ContentLocalizer.shared.workoutTitle(programId: record.programId, workoutId: record.workoutId, fallback: record.workoutTitle),
            result: complete ? "\(sets)" : "\(sets) / \(max(sets, targets))", detail: t("sets"),
            previous: records.isEmpty ? nil : t("recordsCount", ["count": records.count]), date: date(record), metrics: metrics, primary: primary, secondary: secondary)
        let cards = records.enumerated().map { index, pr in
            let bodyweight = WorkoutSessionUtils.usesBodyweightResistance(Exercise(name: pr.exerciseName, exerciseId: pr.exerciseId))
            let delta: String
            switch pr.kind {
            case .weight: delta = "+\(number(pr.set.weightKg! - pr.previous.weightKg!, unit)) \(unit.label)"
            case .assistance: delta = t("lessAssistance", ["weight": "\(number(pr.previous.weightKg! - pr.set.weightKg!, unit)) \(unit.label)"])
            case .reps: delta = t("repDelta", ["count": pr.set.reps! - pr.previous.reps!])
            }
            let previous = pr.kind == .reps
                ? "\(t(pr.isAssisted ? "assistedRepBest" : "repBest")): \(t("reps", ["count": pr.previous.reps!]))"
                : "\(t("previous")): \(setText(pr.previous, unit, pr.isAssisted, bodyweight))"
            return SocialCardContent(id: "\(record.id):pr:\(index)", kind: .record,
                title: ContentLocalizer.shared.exerciseName(exerciseId: pr.exerciseId, fallback: pr.exerciseName),
                result: setText(pr.set, unit, pr.isAssisted, bodyweight), detail: "\(t("record")) · \(delta)", previous: previous, date: date(record))
        }
        return [summary] + cards
    }

    public static func week(program: Program?, completed: [String], history: [WorkoutSessionRecord], weekKey: String, unit: WeightUnit, today: Date = Date()) -> SocialCardContent? {
        guard let program, !program.workouts.isEmpty,
              PersonalRecordTracker.isoWeekKey(today) == weekKey,
              program.workouts.allSatisfy({ completed.contains("\(program.id):\($0.id)") }) else { return nil }
        var seen = Set<String>()
        let logs = history.filter { seen.insert($0.id).inserted && PersonalRecordTracker.isRecordInWeek($0, targetWeekKey: weekKey) }
        let sets = logs.reduce(0) { $0 + $1.exerciseLogs.reduce(0) { $0 + RecordEngine.workingSets($1).count } }
        let duration = logs.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let prs = PersonalRecordTracker.countPrsForWeek(history: history, currentWeekKey: weekKey)
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = .current
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        return SocialCardContent(id: "week:\(weekKey):\(program.id)", kind: .week, title: t("week"),
            result: "\(program.workouts.count) / \(program.workouts.count)", detail: t("workouts"),
            date: "\(formatDate(monday)) – \(formatDate(sunday))",
            metrics: [SocialMetric(key: "sets", value: "\(sets)"), SocialMetric(key: "duration", value: RestTimerUtils.formatSecondsToTime(duration)), SocialMetric(key: "records", value: "\(prs)")])
    }

    public static func suggested(cards: [SocialCardContent], week: SocialCardContent?, justCompletedWeek: Bool) -> SocialShareRequest? {
        let prs = cards.filter { $0.kind == .record }
        guard !prs.isEmpty || justCompletedWeek else { return nil }
        return SocialShareRequest(cards: prs + [week].compactMap { $0 } + cards.filter { $0.kind != .record }, suggested: true)
    }
}
