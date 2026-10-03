import Foundation

public enum ProgressionEngine {

    public static let variationSwaps: [String: (id: String, name: String)] = [
        "barbell-bench-press": ("incline-dumbbell-press", "Incline Dumbbell Press"),
        "incline-barbell-bench-press": ("dumbbell-bench-press", "Dumbbell Bench Press"),
        "dumbbell-bench-press": ("barbell-bench-press", "Barbell Bench Press"),
        "barbell-back-squat": ("leg-press", "Leg Press"),
        "barbell-front-squat": ("goblet-squat", "Goblet Squat"),
        "conventional-barbell-deadlift": ("trap-bar-deadlift", "Trap Bar Deadlift"),
        "barbell-romanian-deadlift": ("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift"),
        "barbell-row": ("chest-supported-dumbbell-row", "Chest-Supported Dumbbell Row"),
        "standing-barbell-overhead-press": ("dumbbell-seated-shoulder-press", "Dumbbell Seated Shoulder Press"),
        "pull-ups": ("lat-pulldown", "Lat Pulldown"),
        "lat-pulldown": ("pull-ups", "Pull-Ups"),
        "ez-bar-curl": ("incline-dumbbell-curl", "Incline Dumbbell Curl"),
        "rope-triceps-pressdown": ("overhead-cable-triceps-extension", "Overhead Cable Triceps Extension")
    ]

    private static let prescriptionRepsRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:\d+\s*[×x]\s*)?(\d+)(?:\s*[-–—]\s*(\d+))?\s*(?:reps?)?(?:\s*/\s*(?:side|leg|arm))?\s*$"#,
        options: .caseInsensitive
    )

    public static func parseRepRange(exercise: Exercise) -> (min: Int, max: Int)? {
        if let reps = exercise.reps {
            if reps.toFailure { return nil }
            guard let minR = reps.min ?? reps.max else { return nil }
            let maxR = reps.max ?? minR
            guard (1...999).contains(minR), (1...999).contains(maxR) else { return nil }
            return (min(minR, maxR), max(minR, maxR))
        }
        let presc = exercise.prescription
        let nsPresc = presc as NSString
        let fullRange = NSRange(location: 0, length: nsPresc.length)

        guard let match = prescriptionRepsRegex?.firstMatch(in: presc, range: fullRange),
              match.range(at: 1).location != NSNotFound,
              let minVal = Int(nsPresc.substring(with: match.range(at: 1))) else { return nil }
        let maxVal: Int
        if match.range(at: 2).location == NSNotFound {
            maxVal = minVal
        } else {
            guard let parsedMax = Int(nsPresc.substring(with: match.range(at: 2))) else { return nil }
            maxVal = parsedMax
        }
        guard (1...999).contains(minVal), (1...999).contains(maxVal) else { return nil }
        return (min(minVal, maxVal), max(minVal, maxVal))
    }

    private struct HistoricalSessionSets {
        let sets: [SessionSetLog]
        let targetSets: Int?
        let ambiguous: Bool
        var workingSets: [SessionSetLog] { sets.filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber } }
    }

    private static func findHistoricalSessions(exercise: Exercise, history: [WorkoutSessionRecord]) -> [HistoricalSessionSets] {
        var seen = Set<String>()
        return history.filter { seen.insert($0.id).inserted }.sorted {
            ($0.completedAt.isEmpty ? $0.startedAt : $0.completedAt) > ($1.completedAt.isEmpty ? $1.startedAt : $1.completedAt)
        }.compactMap { record in
            let logs = record.exerciseLogs.filter {
                ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.exerciseName)
            }
            guard logs.contains(where: { $0.sets.contains(where: { !$0.isWarmup }) }) else { return nil }
            return HistoricalSessionSets(sets: logs.flatMap { $0.sets }, targetSets: logs.count == 1 ? logs[0].targetSets : nil, ambiguous: logs.count != 1)
        }
    }

    public static func computeProgression(
        exercise: Exercise,
        history: [WorkoutSessionRecord],
        weightUnit: WeightUnit = .kg
    ) -> ExerciseProgressionRecommendation? {
        guard let (repMin, repMax) = parseRepRange(exercise: exercise) else { return nil }
        let exerciseId = exercise.exerciseId ?? ExerciseCatalog.key(exercise.name)
        let category = EquipmentCatalog.shared.categoryId(exerciseId)
        let expectedSets = WorkoutSessionUtils.initialSetCount(exercise: exercise)
        let sessions = findHistoricalSessions(exercise: exercise, history: history)

        func guidance(_ action: ProgressionAction, _ key: String, _ args: [String: String] = [:], plateau: Bool = false,
                      summary: String? = nil) -> ExerciseProgressionRecommendation {
            ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: action,
                suggestedWeightKg: nil, suggestedWeightDisplay: "--", suggestedRepsMin: repMin, suggestedRepsMax: repMax,
                rationaleKey: key, rationaleArgs: args, isPlateau: plateau, consecutiveStagnantSessions: plateau ? 3 : 0,
                lastSessionSummary: summary)
        }
        guard let last = sessions.first else {
            return guidance(.firstSession, "progression.rationale.first_session", ["reps": repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"])
        }
        func complete(_ session: HistoricalSessionSets) -> Bool {
            let sets = session.workingSets
            return !session.ambiguous && sets.count == expectedSets &&
                (session.targetSets == nil || session.targetSets == sets.count) &&
                Set(sets.map { $0.setNumber }).count == sets.count && sets.allSatisfy { set in
                    guard let reps = set.reps, let weight = set.weightKg else { return false }
                    return (1...999).contains(reps) && weight.isFinite && weight >= 0 && weightUnit.toDisplay(weight) <= 9999.99 &&
                        (WorkoutSessionUtils.allowsZeroWeight(exercise) || weight > 0)
                }
        }
        // Do not silently fall back to an older, easier or more complete workout.
        guard complete(last) else {
            return guidance(.insufficientData, "progression.rationale.insufficient_data", ["sets": "\(expectedSets)"])
        }
        let workingSets = last.workingSets
        let topWeight = workingSets.map { $0.weightKg! }.max()!
        let mixedLoads = workingSets.contains { abs($0.weightKg! - topWeight) > 0.01 }
        func comparable(_ session: HistoricalSessionSets) -> Bool {
            complete(session) && zip(session.workingSets, workingSets).allSatisfy { abs($0.weightKg! - $1.weightKg!) <= 0.01 }
        }
        let allHitCeiling = workingSets.allSatisfy { $0.reps! >= repMax }
        let recent = Array(sessions.prefix(3))
        let isPlateau = recent.count == 3 && recent.allSatisfy(comparable) && !allHitCeiling &&
            zip(recent, recent.dropFirst()).allSatisfy { newer, older in
                newer.workingSets.reduce(0) { $0 + $1.reps! } <= older.workingSets.reduce(0) { $0 + $1.reps! }
            }
        if isPlateau {
            return guidance(.deload, "progression.rationale.plateau", ["sessions": "3"], plateau: true,
                            summary: formatSessionSummary(workingSets, unit: weightUnit))
        }
        // A second full session at the same set-by-set loads confirms the ceiling.
        let confirmedCeiling = allHitCeiling && sessions.dropFirst().first.map { previous in
            comparable(previous) && previous.workingSets.allSatisfy { $0.reps! >= repMax }
        } == true
        let incrementKg: Double
        switch category {
        case "bar", "machine": incrementKg = weightUnit == .lbs ? weightUnit.toCanonicalKg(5) : 2.5
        case "dumbbell": incrementKg = weightUnit == .lbs ? weightUnit.toCanonicalKg(5) : 2
        default: incrementKg = 0 // Unknown equipment, bands and bodyweight have no inferred load step.
        }
        let canIncrease = confirmedCeiling && incrementKg > 0 && workingSets.allSatisfy {
            $0.weightKg! > 0 && incrementKg <= $0.weightKg! * 0.10 && weightUnit.toDisplay($0.weightKg! + incrementKg) <= 9999.99
        }
        let missedFloor = workingSets.contains { $0.reps! < repMin }
        let action: ProgressionAction = canIncrease ? .increaseLoad : (allHitCeiling || missedFloor ? .holdLoad : .addReps)
        let targets = workingSets.map { set in
            ProgressionSetTarget(weightKg: canIncrease ? set.weightKg! + incrementKg : set.weightKg,
                reps: canIncrease ? repMin : (allHitCeiling ? repMax : min(set.reps! + 1, repMax)))
        }
        let key: String
        if canIncrease { key = mixedLoads ? "progression.rationale.increase_load_mixed" : "progression.rationale.increase_load" }
        else if allHitCeiling { key = confirmedCeiling ? "progression.rationale.load_step_unavailable" : "progression.rationale.repeat_ceiling" }
        else if missedFloor { key = mixedLoads ? "progression.rationale.hold_load_mixed" : "progression.rationale.hold_load" }
        else { key = mixedLoads ? "progression.rationale.add_reps_mixed" : "progression.rationale.add_reps" }
        let weights = Set(targets.compactMap { $0.weightKg })
        let uniformWeight = weights.count == 1 ? weights.first : nil
        return ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: action,
            suggestedWeightKg: uniformWeight, suggestedWeightDisplay: formatWeight(uniformWeight ?? topWeight, unit: weightUnit),
            suggestedRepsMin: targets.map { $0.reps }.min()!, suggestedRepsMax: targets.map { $0.reps }.max()!,
            weightDeltaDisplay: canIncrease ? "+\(formatWeight(incrementKg, unit: weightUnit)) \(weightUnit.label)" : nil,
            rationaleKey: key, rationaleArgs: ["ceiling": "\(repMax)", "floor": "\(repMin)", "targetReps": "\(repMin)"],
            lastSessionSummary: formatSessionSummary(workingSets, unit: weightUnit), setTargets: targets)
    }

    public static func evaluateMesocycleFatigue(
        history: [WorkoutSessionRecord],
        activeProgram: Program?
    ) -> MesocycleDeloadRecommendation {
        if history.isEmpty {
            return MesocycleDeloadRecommendation(
                isRecommended: false,
                consecutiveWeeksTrained: 0,
                stagnantExercisesCount: 0,
                headlineKey: "progression.deload.none_headline",
                explanationKey: "progression.deload.none_desc"
            )
        }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let trainingWeeks = Set(history.compactMap { record -> Date? in
            guard record.exerciseLogs.contains(where: { log in
                log.sets.contains(where: { ($0.reps ?? 0) > 0 && !$0.isWarmup })
            }) else { return nil }
            let dateStr = record.completedAt.isEmpty ? record.startedAt : record.completedAt
            guard dateStr.count >= 10 else { return nil }
            let dayStr = String(dateStr.prefix(10))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            guard let date = formatter.date(from: dayStr) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
        })

        var consecutiveWeeks = 0
        var week = trainingWeeks.max()
        while let currentWeek = week, trainingWeeks.contains(currentWeek), consecutiveWeeks < 12 {
            consecutiveWeeks += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek)
        }

        let exercises = Array(Dictionary(
            (activeProgram?.workouts.flatMap { $0.exercises } ?? []).map {
                ($0.exerciseId ?? ExerciseCatalog.key($0.name), $0)
            }, uniquingKeysWith: { first, _ in first }
        ).values)
        let stagnantCount = exercises.filter { ex in
            computeProgression(exercise: ex, history: history)?.isPlateau == true
        }.count

        let isRecommended = stagnantCount >= 3 || consecutiveWeeks >= 6

        let headlineKey: String = {
            if stagnantCount >= 3 { return "progression.deload.stagnant_headline" }
            if consecutiveWeeks >= 6 { return "progression.deload.weeks_headline" }
            return "progression.deload.none_headline"
        }()

        let explanationKey: String = {
            if stagnantCount >= 3 { return "progression.deload.stagnant_desc" }
            if consecutiveWeeks >= 6 { return "progression.deload.weeks_desc" }
            return "progression.deload.none_desc"
        }()

        return MesocycleDeloadRecommendation(
            isRecommended: isRecommended,
            consecutiveWeeksTrained: consecutiveWeeks,
            stagnantExercisesCount: stagnantCount,
            headlineKey: headlineKey,
            explanationKey: explanationKey
        )
    }

    private static func formatWeight(_ kg: Double, unit: WeightUnit) -> String {
        kg <= 0.0 ? "BW" : unit.formatWeight(kg)
    }

    private static func formatSessionSummary(_ sets: [SessionSetLog], unit: WeightUnit) -> String {
        sets.map { set in
            let w = (set.weightKg != nil && set.weightKg! > 0.0) ? formatWeight(set.weightKg!, unit: unit) : "BW"
            let r = set.reps ?? 0
            return "\(w)×\(r)"
        }.joined(separator: ", ")
    }
}
