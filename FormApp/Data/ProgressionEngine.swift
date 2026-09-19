import Foundation

public enum ProgressionEngine {

    public static let variationSwaps: [String: (id: String, name: String)] = [
        "barbell-bench-press": ("incline-dumbbell-press", "Incline Dumbbell Press"),
        "incline-barbell-bench-press": ("dumbbell-bench-press", "Dumbbell Bench Press"),
        "dumbbell-bench-press": ("barbell-bench-press", "Barbell Bench Press"),
        "barbell-back-squat": ("leg-press-45-degree", "45° Leg Press"),
        "barbell-front-squat": ("kettlebell-goblet-squat", "Kettlebell Goblet Squat"),
        "conventional-barbell-deadlift": ("trap-bar-deadlift", "Trap Bar Deadlift"),
        "barbell-romanian-deadlift": ("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift"),
        "barbell-row": ("chest-supported-dumbbell-row", "Chest-Supported Dumbbell Row"),
        "standing-barbell-overhead-press": ("dumbbell-overhead-press", "Dumbbell Overhead Press"),
        "pull-up": ("lat-pulldown", "Lat Pulldown"),
        "lat-pulldown": ("pull-up", "Pull-Up"),
        "ez-bar-curl": ("incline-dumbbell-curl", "Incline Dumbbell Curl"),
        "rope-triceps-pressdown": ("overhead-cable-triceps-extension", "Overhead Cable Triceps Extension")
    ]

    private static let prescriptionRangeRegex = try? NSRegularExpression(pattern: #"(\d+)\s*[-–—]\s*(\d+)"#)
    private static let prescriptionFixedRegex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:reps|rep)?"#, options: .caseInsensitive)

    public static func parseRepRange(exercise: Exercise) -> (min: Int, max: Int) {
        if let reps = exercise.reps {
            let minR = reps.min ?? 8
            let maxR = reps.max ?? minR
            return (minR, maxR)
        }
        let presc = exercise.prescription
        let nsPresc = presc as NSString
        let fullRange = NSRange(location: 0, length: nsPresc.length)

        if let rangeMatch = prescriptionRangeRegex?.firstMatch(in: presc, range: fullRange),
           rangeMatch.numberOfRanges >= 3 {
            let minStr = nsPresc.substring(with: rangeMatch.range(at: 1))
            let maxStr = nsPresc.substring(with: rangeMatch.range(at: 2))
            let minVal = Int(minStr) ?? 8
            let maxVal = Int(maxStr) ?? minVal
            return (minVal, maxVal)
        }

        if let fixedMatch = prescriptionFixedRegex?.firstMatch(in: presc, range: fullRange),
           fixedMatch.numberOfRanges >= 2 {
            let fixedStr = nsPresc.substring(with: fixedMatch.range(at: 1))
            let fixedVal = Int(fixedStr) ?? 10
            return (fixedVal, fixedVal)
        }

        return (8, 12)
    }

    private struct HistoricalSessionSets {
        let dateString: String
        let sets: [SessionSetLog]

        var workingSets: [SessionSetLog] {
            sets.filter { ($0.reps ?? 0) > 0 && ($0.weightKg ?? 0.0) > 0.0 }
        }

        var topWeightKg: Double {
            workingSets.map { $0.weightKg ?? 0.0 }.max() ?? 0.0
        }

        var totalRepsAtTopWeight: Int {
            let top = topWeightKg
            return workingSets.filter { ($0.weightKg ?? 0.0) >= (top * 0.95) }
                .reduce(0) { $0 + ($1.reps ?? 0) }
        }
    }

    private static func findHistoricalSessions(
        exercise: Exercise,
        history: [WorkoutSessionRecord]
    ) -> [HistoricalSessionSets] {
        let targetId = exercise.exerciseId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetCanonical = ExerciseCatalog.key(exercise.name)

        var results: [HistoricalSessionSets] = []

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

                let validSets = log.sets.filter { ($0.reps ?? 0) > 0 && ($0.weightKg ?? 0.0) > 0.0 }
                if !validSets.isEmpty {
                    results.append(
                        HistoricalSessionSets(
                            dateString: record.completedAt.isEmpty ? record.startedAt : record.completedAt,
                            sets: validSets
                        )
                    )
                }
            }
        }
        return results
    }

    public static func computeProgression(
        exercise: Exercise,
        history: [WorkoutSessionRecord],
        weightUnit: WeightUnit = .kg
    ) -> ExerciseProgressionRecommendation {
        let (repMin, repMax) = parseRepRange(exercise: exercise)
        let exerciseId = exercise.exerciseId ?? ExerciseCatalog.key(exercise.name)
        let category = EquipmentCatalog.shared.categoryId(exerciseId)

        let sessions = findHistoricalSessions(exercise: exercise, history: history)
        if sessions.isEmpty {
            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .firstSession,
                suggestedWeightKg: nil,
                suggestedWeightDisplay: "--",
                suggestedRepsMin: repMin,
                suggestedRepsMax: repMax,
                weightDeltaDisplay: nil,
                rationaleKey: "progression.rationale.first_session",
                rationaleArgs: ["reps": repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"],
                isPlateau: false,
                consecutiveStagnantSessions: 0
            )
        }

        let lastSession = sessions[0]
        let lastTopWeightKg = lastSession.topWeightKg
        let lastWorkingSets = lastSession.workingSets

        let incrementKg: Double = {
            switch category {
            case "bar": return weightUnit == .lbs ? 2.268 : 2.5
            case "dumbbell": return weightUnit == .lbs ? 2.268 : 2.0
            case "machine": return weightUnit == .lbs ? 2.268 : 2.5
            default: return weightUnit == .lbs ? 1.134 : 1.25
            }
        }()

        let thresholdSets = lastWorkingSets.filter { ($0.weightKg ?? 0.0) >= (lastTopWeightKg * 0.95) }
        let allHitCeiling = !thresholdSets.isEmpty && thresholdSets.allSatisfy { ($0.reps ?? 0) >= repMax }
        let anyMissedFloor = thresholdSets.contains { ($0.reps ?? 0) < repMin }

        // Plateau evaluation across up to 3 sessions
        var isPlateau = false
        var consecutiveStagnant = 1
        if sessions.count >= 3 {
            let s1 = sessions[0]
            let s2 = sessions[1]
            let s3 = sessions[2]

            let w1 = s1.topWeightKg
            let w2 = s2.topWeightKg
            let w3 = s3.topWeightKg

            let weightStagnant = abs(w1 - w2) <= (w1 * 0.025) && abs(w2 - w3) <= (w2 * 0.025)
            let r1 = s1.totalRepsAtTopWeight
            let r2 = s2.totalRepsAtTopWeight
            let r3 = s3.totalRepsAtTopWeight

            let repsStagnant = r1 <= (r2 + 1) && r2 <= (r3 + 1)

            if weightStagnant && repsStagnant {
                isPlateau = true
                consecutiveStagnant = 3
            }
        }

        // 1. Plateau
        if isPlateau {
            let deloadWeightKg: Double = {
                if weightUnit == .lbs {
                    let lbs = weightUnit.toDisplay(lastTopWeightKg) * 0.9
                    let roundedLbs = (lbs / 2.5).rounded() * 2.5
                    return weightUnit.toCanonicalKg(roundedLbs)
                } else {
                    let roundedKg = (lastTopWeightKg * 0.9 * 2.0).rounded() / 2.0
                    return roundedKg
                }
            }()

            let swap = variationSwaps[exerciseId]
            let deltaKg = deloadWeightKg - lastTopWeightKg
            let deltaInUnit = weightUnit.toDisplay(deltaKg)
            let roundedDelta = (deltaInUnit * 10).rounded() / 10.0
            let formattedDelta = roundedDelta.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(roundedDelta))" : String(format: "%.1f", roundedDelta)

            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .deload,
                suggestedWeightKg: deloadWeightKg,
                suggestedWeightDisplay: formatWeight(deloadWeightKg, unit: weightUnit),
                suggestedRepsMin: repMin,
                suggestedRepsMax: repMax,
                weightDeltaDisplay: "\(formattedDelta) \(weightUnit.label)",
                rationaleKey: "progression.rationale.plateau",
                rationaleArgs: [
                    "weight": formatWeight(lastTopWeightKg, unit: weightUnit),
                    "unit": weightUnit.label,
                    "sessions": "\(consecutiveStagnant)",
                    "variation": swap?.name ?? exercise.name
                ],
                isPlateau: true,
                consecutiveStagnantSessions: consecutiveStagnant,
                suggestedVariationId: swap?.id,
                suggestedVariationName: swap?.name,
                lastSessionSummary: formatSessionSummary(lastWorkingSets, unit: weightUnit)
            )
        }

        // 2. Rep ceiling achieved -> INCREASE_LOAD
        if allHitCeiling {
            let newWeightKg: Double = {
                if weightUnit == .lbs {
                    let currentLbs = weightUnit.toDisplay(lastTopWeightKg)
                    let newLbs = (currentLbs + 5.0).rounded()
                    return weightUnit.toCanonicalKg(newLbs)
                } else {
                    return lastTopWeightKg + incrementKg
                }
            }()

            let deltaKg = newWeightKg - lastTopWeightKg
            let deltaInUnit = weightUnit.toDisplay(deltaKg)
            let roundedDelta = (deltaInUnit * 10).rounded() / 10.0
            let formattedDelta = roundedDelta.truncatingRemainder(dividingBy: 1.0) == 0 ? "\(Int(roundedDelta))" : String(format: "%.1f", roundedDelta)

            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .increaseLoad,
                suggestedWeightKg: newWeightKg,
                suggestedWeightDisplay: formatWeight(newWeightKg, unit: weightUnit),
                suggestedRepsMin: repMin,
                suggestedRepsMax: repMax,
                weightDeltaDisplay: "+\(formattedDelta) \(weightUnit.label)",
                rationaleKey: "progression.rationale.increase_load",
                rationaleArgs: [
                    "ceiling": "\(repMax)",
                    "lastWeight": formatWeight(lastTopWeightKg, unit: weightUnit),
                    "newWeight": formatWeight(newWeightKg, unit: weightUnit),
                    "unit": weightUnit.label,
                    "targetReps": "\(repMin)"
                ],
                isPlateau: false,
                consecutiveStagnantSessions: 0,
                lastSessionSummary: formatSessionSummary(lastWorkingSets, unit: weightUnit)
            )
        }

        // 3. Within rep bracket -> ADD_REPS
        if !anyMissedFloor {
            let highestRepsAchieved = thresholdSets.map { $0.reps ?? 0 }.max() ?? repMin
            let nextRepTarget = min(highestRepsAchieved + 1, repMax)

            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .addReps,
                suggestedWeightKg: lastTopWeightKg,
                suggestedWeightDisplay: formatWeight(lastTopWeightKg, unit: weightUnit),
                suggestedRepsMin: nextRepTarget,
                suggestedRepsMax: repMax,
                weightDeltaDisplay: nil,
                rationaleKey: "progression.rationale.add_reps",
                rationaleArgs: [
                    "weight": formatWeight(lastTopWeightKg, unit: weightUnit),
                    "unit": weightUnit.label,
                    "ceiling": "\(repMax)"
                ],
                isPlateau: false,
                consecutiveStagnantSessions: 0,
                lastSessionSummary: formatSessionSummary(lastWorkingSets, unit: weightUnit)
            )
        }

        // 4. Failed to hit floor -> HOLD_LOAD
        return ExerciseProgressionRecommendation(
            exerciseId: exerciseId,
            exerciseName: exercise.name,
            action: .holdLoad,
            suggestedWeightKg: lastTopWeightKg,
            suggestedWeightDisplay: formatWeight(lastTopWeightKg, unit: weightUnit),
            suggestedRepsMin: repMin,
            suggestedRepsMax: repMax,
            weightDeltaDisplay: nil,
            rationaleKey: "progression.rationale.hold_load",
            rationaleArgs: [
                "weight": formatWeight(lastTopWeightKg, unit: weightUnit),
                "unit": weightUnit.label,
                "floor": "\(repMin)"
            ],
            isPlateau: false,
            consecutiveStagnantSessions: 0,
            lastSessionSummary: formatSessionSummary(lastWorkingSets, unit: weightUnit)
        )
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

        let weekKeys = Set(history.compactMap { record -> String? in
            let dateStr = record.completedAt.isEmpty ? record.startedAt : record.completedAt
            return dateStr.count >= 10 ? String(dateStr.prefix(10)) : nil
        })

        let consecutiveWeeks = min(max(weekKeys.count / 3, 0), 12)

        let exercises = activeProgram?.workouts.flatMap { $0.exercises } ?? []
        let stagnantCount = exercises.filter { ex in
            computeProgression(exercise: ex, history: history).isPlateau
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
        unit.formatWeight(kg)
    }

    private static func formatSessionSummary(_ sets: [SessionSetLog], unit: WeightUnit) -> String {
        sets.map { set in
            let w = set.weightKg != nil ? formatWeight(set.weightKg!, unit: unit) : "?"
            let r = set.reps ?? 0
            return "\(w)×\(r)"
        }.joined(separator: ", ")
    }
}
