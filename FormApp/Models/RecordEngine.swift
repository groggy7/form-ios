import Foundation

public enum RecordKind: Int { case weight, assistance, reps }

/// Only the observed main-part performance is exposed. Private ratings and notes never enter card data.
public struct ExerciseRecord {
    public let exerciseId: String?
    public let exerciseName: String
    public let kind: RecordKind
    public let set: SessionSetLog
    public let previous: SessionSetLog
    public let isAssisted: Bool
}

public enum RecordEngine {
    public static func sameExercise(_ a: SessionExerciseLog, _ b: SessionExerciseLog) -> Bool {
        if let left = a.exerciseId, hasText(left), let right = b.exerciseId, hasText(right) { return left == right }
        return PersonalRecordTracker.normalizeExerciseKey(a.exerciseName) == PersonalRecordTracker.normalizeExerciseKey(b.exerciseName)
    }
    private static let whitespace = CharacterSet.whitespacesAndNewlines
    /// Whether trimming whitespace would leave text, without the copy; this runs for every pair of logs compared.
    private static func hasText(_ value: String) -> Bool {
        !value.unicodeScalars.allSatisfy { whitespace.contains($0) }
    }
    private static func load(_ set: SessionSetLog) -> Double { WeightUnit.roundHalfAwayFromZero(set.weightKg ?? 0, decimals: 1) }
    public static func workingSets(_ log: SessionExerciseLog) -> [SessionSetLog] {
        log.sets.filter { (($0.weightKg ?? 0) > 0 || WorkoutSessionUtils.allowsZeroWeight(Exercise(name: log.exerciseName, exerciseId: log.exerciseId))) && !$0.isWarmup && $0.weightKg.map { $0.isFinite && (0...1500).contains($0) } == true && (1...999).contains($0.reps ?? 0) }
    }
    public static func forSession(history: [WorkoutSessionRecord], target: WorkoutSessionRecord, timeZone: TimeZone = .current) -> [ExerciseRecord] {
        let targetKey = PersonalRecordTracker.TrainingKey(target, timeZone: timeZone)
        return forPriorRecords(history.filter {
            $0.id != target.id && PersonalRecordTracker.TrainingKey($0, timeZone: timeZone).precedes(targetKey)
        }, target: target)
    }

    /// `forSession` with the records that precede `target` already chosen.
    static func forPriorRecords(_ priorRecords: [WorkoutSessionRecord], target: WorkoutSessionRecord) -> [ExerciseRecord] {
        let prior = priorRecords.flatMap(\.exerciseLogs)
        var seen: [SessionExerciseLog] = []
        var result: [(Int, ExerciseRecord)] = []
        for (index, log) in target.exerciseLogs.enumerated() {
            if seen.contains(where: { sameExercise($0, log) }) { continue }
            seen.append(log)
            let current = target.exerciseLogs.filter { sameExercise($0, log) }.flatMap(workingSets)
            let previous = prior.filter { sameExercise($0, log) }.flatMap(workingSets)
            guard !previous.isEmpty else { continue }
            let assisted = WorkoutSessionUtils.isAssisted(exerciseId: log.exerciseId, name: log.exerciseName)
            var candidates: [ExerciseRecord] = []
            for set in current {
                let w = load(set), reps = set.reps!
                let oldMax = previous.max { $0.weightKg == $1.weightKg ? ($0.reps ?? 0) < ($1.reps ?? 0) : $0.weightKg! < $1.weightKg! }!
                let kind: RecordKind
                let baseline: SessionSetLog
                if !assisted && w > 0 && w > load(oldMax) && set.weightKg! > oldMax.weightKg! + 0.010000001 {
                    kind = .weight; baseline = oldMax
                } else {
                    let comparable = previous.filter { abs($0.weightKg! - set.weightKg!) <= 0.010000001 || (assisted ? load($0) <= w : load($0) >= w) }
                    if comparable.contains(where: { $0.reps! >= reps }) { continue }
                    if assisted && comparable.isEmpty {
                        kind = .assistance
                        baseline = previous.min { $0.weightKg == $1.weightKg ? ($0.reps ?? 0) > ($1.reps ?? 0) : $0.weightKg! < $1.weightKg! }!
                    } else {
                        kind = .reps
                        guard let best = comparable.max(by: {
                            if $0.reps != $1.reps { return ($0.reps ?? 0) < ($1.reps ?? 0) }
                            return assisted ? load($0) > load($1) : load($0) < load($1)
                        }) else { continue }
                        baseline = best
                    }
                }
                candidates.append(ExerciseRecord(exerciseId: log.exerciseId, exerciseName: log.exerciseName, kind: kind, set: set, previous: baseline, isAssisted: assisted))
            }
            let chosen = candidates.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                if $0.kind == .weight && load($0.set) != load($1.set) { return load($0.set) > load($1.set) }
                if $0.set.reps != $1.set.reps { return ($0.set.reps ?? 0) > ($1.set.reps ?? 0) }
                return $0.set.setNumber < $1.set.setNumber
            }.first
            if let chosen { result.append((index, chosen)) }
        }
        return result.sorted { $0.1.kind == $1.1.kind ? $0.0 < $1.0 : $0.1.kind.rawValue < $1.1.kind.rawValue }.map { $0.1 }
    }
}
