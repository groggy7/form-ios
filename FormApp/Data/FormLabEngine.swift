import Foundation

public struct FormLabEngine {

    public static let pushMuscles: Set<String> = ["chest", "front-delts", "triceps"]
    public static let pullMuscles: Set<String> = ["upper-back", "rear-delts", "lats", "biceps"]
    public static let quadMuscles: Set<String> = ["quads"]
    public static let hamstringMuscles: Set<String> = ["hamstrings"]
    public static let upperMuscles: Set<String> = pushMuscles.union(pullMuscles).union(["abs", "obliques"])
    public static let lowerMuscles: Set<String> = quadMuscles.union(hamstringMuscles).union(["glutes", "calves"])

    public static func calculateEstimated1RM(
        weightKg: Double,
        reps: Int,
        formula: RepMaxFormula = .brzycki
    ) -> Double {
        // Zero means unavailable, not a zero-capacity estimate. Logs are untouched.
        guard weightKg.isFinite, weightKg > 0, (1...10).contains(reps) else { return 0 }
        if reps == 1 { return weightKg }

        let estimate: Double
        switch formula {
        case .brzycki:
            estimate = weightKg * (36.0 / (37.0 - Double(reps)))
        case .epley:
            estimate = weightKg * (1.0 + Double(reps) / 30.0)
        }
        return estimate.isFinite ? estimate : 0
    }

    public static func calculateTargetNRM(
        oneRmKg: Double,
        targetReps: Int,
        formula: RepMaxFormula = .brzycki
    ) -> Double {
        guard oneRmKg.isFinite, oneRmKg > 0, (1...10).contains(targetReps) else { return 0 }
        if targetReps == 1 { return oneRmKg }

        switch formula {
        case .brzycki:
            return oneRmKg * ((37.0 - Double(targetReps)) / 36.0)
        case .epley:
            return oneRmKg / (1.0 + Double(targetReps) / 30.0)
        }
    }

    public static func computeRepMaxTargets(
        oneRmKg: Double,
        formula: RepMaxFormula = .brzycki
    ) -> [RepMaxTarget] {
        guard oneRmKg.isFinite, oneRmKg > 0 else { return [] }
        let repValues = [1, 3, 5, 8, 10]
        return repValues.map { r in
            let targetWeight = calculateTargetNRM(oneRmKg: oneRmKg, targetReps: r, formula: formula)
            let pct = oneRmKg > 0 ? (targetWeight / oneRmKg) * 100.0 : 0.0
            return RepMaxTarget(
                reps: r,
                estimatedWeightKg: targetWeight,
                percentageOf1RM: pct
            )
        }
    }

    public static func normalizeExerciseName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: "  ", with: " ")
    }

    public static func computeExerciseRepMax(
        exerciseName: String,
        history: [WorkoutSessionRecord],
        formula: RepMaxFormula = .brzycki
    ) -> ExerciseRepMaxSummary? {
        let targetNorm = normalizeExerciseName(exerciseName)

        var bestWeight: Double = 0
        var bestReps: Int = 0
        var best1RM: Double = 0
        var bestDate: String? = nil

        let sortedRecords = history.sorted { ($0.startedAt.isEmpty ? $0.completedAt : $0.startedAt) > ($1.startedAt.isEmpty ? $1.completedAt : $1.startedAt) }

        for record in sortedRecords {
            for log in record.exerciseLogs {
                guard normalizeExerciseName(log.exerciseName) == targetNorm else { continue }

                for set in log.sets {
                    guard !set.isWarmup else { continue }
                    let w = set.weightKg ?? 0
                    let r = set.reps ?? 0
                    if w > 0 && r > 0 {
                        let est = calculateEstimated1RM(weightKg: w, reps: r, formula: formula)
                        if est > best1RM {
                            best1RM = est
                            bestWeight = w
                            bestReps = r
                            bestDate = record.startedAt.isEmpty ? record.completedAt : record.startedAt
                        }
                    }
                }
            }
        }

        guard best1RM > 0 else { return nil }

        return ExerciseRepMaxSummary(
            exerciseId: targetNorm,
            exerciseName: exerciseName,
            bestWeightKg: bestWeight,
            bestReps: bestReps,
            achievedDate: bestDate,
            estimated1rmKg: best1RM,
            formula: formula,
            targets: computeRepMaxTargets(oneRmKg: best1RM, formula: formula)
        )
    }

    public static func computeAllRepMaxSummaries(
        history: [WorkoutSessionRecord],
        formula: RepMaxFormula = .brzycki
    ) -> [ExerciseRepMaxSummary] {
        var names = Set<String>()
        for record in history {
            for log in record.exerciseLogs {
                if log.sets.contains(where: { !$0.isWarmup && ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }) {
                    names.insert(log.exerciseName)
                }
            }
        }

        return names.compactMap { name in
            computeExerciseRepMax(exerciseName: name, history: history, formula: formula)
        }.sorted { $0.estimated1rmKg > $1.estimated1rmKg }
    }

    public static func computeLongitudinalCurve(
        exerciseName: String,
        history: [WorkoutSessionRecord],
        timeframe: StrengthCurveTimeframe = .allTime,
        today: Date = Date(),
        formula: RepMaxFormula = .brzycki
    ) -> LongitudinalCurveReport {
        let targetNorm = normalizeExerciseName(exerciseName)
        let cutoffDate: Date? = timeframe.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }

        var points: [StrengthDataPoint] = []
        let sortedRecords = history.sorted { ($0.startedAt.isEmpty ? $0.completedAt : $0.startedAt) < ($1.startedAt.isEmpty ? $1.completedAt : $1.startedAt) }

        let isoFormatter = ISO8601DateFormatter()
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd"

        for record in sortedRecords {
            let dateStr = record.startedAt.isEmpty ? record.completedAt : record.startedAt
            guard let recordDate = isoFormatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr) else { continue }

            if let cutoff = cutoffDate, recordDate < cutoff { continue }

            for log in record.exerciseLogs {
                guard normalizeExerciseName(log.exerciseName) == targetNorm else { continue }

                var sessionPeak1RM: Double = 0
                var sessionTopWeight: Double = 0
                var sessionTopReps: Int = 0

                for set in log.sets {
                    guard !set.isWarmup else { continue }
                    let w = set.weightKg ?? 0
                    let r = set.reps ?? 0
                    if w > 0 && r > 0 {
                        let est = calculateEstimated1RM(weightKg: w, reps: r, formula: formula)
                        if est > sessionPeak1RM {
                            sessionPeak1RM = est
                            sessionTopWeight = w
                            sessionTopReps = r
                        }
                    }
                }

                if sessionPeak1RM > 0 {
                    let dateDisplay = String(dateStr.prefix(10))
                    points.append(
                        StrengthDataPoint(
                            date: recordDate,
                            dateString: dateDisplay,
                            topWeightKg: sessionTopWeight,
                            topReps: sessionTopReps,
                            estimated1rmKg: sessionPeak1RM,
                            workoutTitle: record.workoutTitle
                        )
                    )
                }
            }
        }

        let start1RM = points.first?.estimated1rmKg
        let current1RM = points.last?.estimated1rmKg
        let peak1RM = points.map { $0.estimated1rmKg }.max()
        let delta = (start1RM != nil && current1RM != nil) ? (current1RM! - start1RM!) : 0
        let pct = (start1RM != nil && start1RM! > 0 && current1RM != nil) ? ((current1RM! - start1RM!) / start1RM!) * 100.0 : 0.0

        return LongitudinalCurveReport(
            exerciseName: exerciseName,
            points: points,
            start1rmKg: start1RM,
            current1rmKg: current1RM,
            peak1rmKg: peak1RM,
            deltaKg: delta,
            percentageGain: pct
        )
    }

    public static func resolveExerciseMuscles(exerciseName: String) -> [String] {
        // Match canonical IDs/names, never broad substrings such as "curl".
        let key = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let catalog = ExerciseCatalog.canonicalExercises
        let exercise = catalog[key]
            ?? catalog.values.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
            ?? catalog[key.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")]
        return ExerciseMuscleCatalog.shared?.profile(exercise?.id)?.primary ?? []
    }

    public static func computeAntagonistBalance(
        history: [WorkoutSessionRecord],
        timeframe: StrengthCurveTimeframe = .allTime,
        today: Date = Date()
    ) -> AntagonistBalanceReport {
        let cutoffDate: Date? = timeframe.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }

        var pushSets = 0
        var pullSets = 0
        var quadSets = 0
        var hamSets = 0
        var upperSets = 0
        var lowerSets = 0
        var totalSets = 0
        var unclassifiedSets = 0

        let isoFormatter = ISO8601DateFormatter()
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd"

        for record in history {
            let dateStr = record.startedAt.isEmpty ? record.completedAt : record.startedAt
            if let cutoff = cutoffDate, let recordDate = isoFormatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr), recordDate < cutoff {
                continue
            }

            for log in record.exerciseLogs {
                let muscles = resolveExerciseMuscles(exerciseName: log.exerciseName)
                let workingSetsCount = log.sets.filter { !$0.isWarmup && (($0.reps ?? 0) > 0 || ($0.weightKg ?? 0) > 0) }.count
                guard workingSetsCount > 0 else { continue }

                totalSets += workingSetsCount
                if muscles.isEmpty { unclassifiedSets += workingSetsCount }

                if muscles.contains(where: { pushMuscles.contains($0) }) { pushSets += workingSetsCount }
                if muscles.contains(where: { pullMuscles.contains($0) }) { pullSets += workingSetsCount }
                if muscles.contains(where: { quadMuscles.contains($0) }) { quadSets += workingSetsCount }
                if muscles.contains(where: { hamstringMuscles.contains($0) }) { hamSets += workingSetsCount }
                if muscles.contains(where: { upperMuscles.contains($0) }) { upperSets += workingSetsCount }
                if muscles.contains(where: { lowerMuscles.contains($0) }) { lowerSets += workingSetsCount }
            }
        }

        // 1. Push vs Pull
        let pushPullStatus: AntagonistStatus
        if pushSets + pullSets < 3 {
            pushPullStatus = .insufficientData
        } else if pullSets == 0 {
            pushPullStatus = .primaryDominant
        } else if pushSets == 0 {
            pushPullStatus = .antagonistDominant
        } else {
            let r = Double(pushSets) / Double(pullSets)
            if r > 1.25 {
                pushPullStatus = .primaryDominant
            } else if r < 0.80 {
                pushPullStatus = .antagonistDominant
            } else {
                pushPullStatus = .optimal
            }
        }
        let pushPullRatio: Double? = (pushPullStatus != .insufficientData && pullSets > 0)
            ? (Double(pushSets) / Double(pullSets) * 100).rounded() / 100
            : nil
        let pushPullAlertKey: String
        switch pushPullStatus {
        case .primaryDominant: pushPullAlertKey = "form_lab.balance.push_dominant_alert"
        case .antagonistDominant: pushPullAlertKey = "form_lab.balance.pull_dominant_alert"
        case .optimal: pushPullAlertKey = "form_lab.balance.push_pull_optimal"
        case .insufficientData: pushPullAlertKey = "form_lab.balance.more_data_needed"
        }
        let pushPullRecKey: String
        switch pushPullStatus {
        case .primaryDominant: pushPullRecKey = "form_lab.balance.push_dominant_rec"
        case .antagonistDominant: pushPullRecKey = "form_lab.balance.pull_dominant_rec"
        case .optimal: pushPullRecKey = "form_lab.balance.push_pull_optimal_rec"
        case .insufficientData: pushPullRecKey = "form_lab.balance.log_more_workouts"
        }
        let pushPull = AntagonistRatio(
            id: "push_pull",
            titleKey: "form_lab.balance.push_pull_title",
            primaryLabelKey: "form_lab.balance.push_label",
            antagonistLabelKey: "form_lab.balance.pull_label",
            primarySets: pushSets,
            antagonistSets: pullSets,
            ratio: pushPullRatio,
            optimalMin: 0.80,
            optimalMax: 1.25,
            status: pushPullStatus,
            alertMessageKey: missingWorkKey(pushSets, pullSets, "push", "pull") ?? pushPullAlertKey,
            recommendationKey: pushPullRecKey
        )

        // 2. Quad vs Ham
        let quadHamStatus: AntagonistStatus
        if quadSets + hamSets < 3 {
            quadHamStatus = .insufficientData
        } else if hamSets == 0 {
            quadHamStatus = .primaryDominant
        } else if quadSets == 0 {
            quadHamStatus = .antagonistDominant
        } else {
            let r = Double(quadSets) / Double(hamSets)
            if r > 1.40 {
                quadHamStatus = .primaryDominant
            } else if r < 0.75 {
                quadHamStatus = .antagonistDominant
            } else {
                quadHamStatus = .optimal
            }
        }
        let quadHamRatio: Double? = (quadHamStatus != .insufficientData && hamSets > 0)
            ? (Double(quadSets) / Double(hamSets) * 100).rounded() / 100
            : nil
        let quadHamAlertKey: String
        switch quadHamStatus {
        case .primaryDominant: quadHamAlertKey = "form_lab.balance.quad_dominant_alert"
        case .antagonistDominant: quadHamAlertKey = "form_lab.balance.ham_dominant_alert"
        case .optimal: quadHamAlertKey = "form_lab.balance.quad_ham_optimal"
        case .insufficientData: quadHamAlertKey = "form_lab.balance.more_data_needed"
        }
        let quadHamRecKey: String
        switch quadHamStatus {
        case .primaryDominant: quadHamRecKey = "form_lab.balance.quad_dominant_rec"
        case .antagonistDominant: quadHamRecKey = "form_lab.balance.ham_dominant_rec"
        case .optimal: quadHamRecKey = "form_lab.balance.quad_ham_optimal_rec"
        case .insufficientData: quadHamRecKey = "form_lab.balance.log_more_workouts"
        }
        let quadHam = AntagonistRatio(
            id: "quad_hamstring",
            titleKey: "form_lab.balance.quad_ham_title",
            primaryLabelKey: "form_lab.balance.quad_label",
            antagonistLabelKey: "form_lab.balance.ham_label",
            primarySets: quadSets,
            antagonistSets: hamSets,
            ratio: quadHamRatio,
            optimalMin: 0.75,
            optimalMax: 1.40,
            status: quadHamStatus,
            alertMessageKey: missingWorkKey(quadSets, hamSets, "quads", "hamstrings") ?? quadHamAlertKey,
            recommendationKey: quadHamRecKey
        )

        // 3. Upper vs Lower
        let upperLowerStatus: AntagonistStatus
        if upperSets + lowerSets < 4 {
            upperLowerStatus = .insufficientData
        } else if lowerSets == 0 {
            upperLowerStatus = .primaryDominant
        } else if upperSets == 0 {
            upperLowerStatus = .antagonistDominant
        } else {
            let r = Double(upperSets) / Double(lowerSets)
            if r > 2.20 {
                upperLowerStatus = .primaryDominant
            } else if r < 0.85 {
                upperLowerStatus = .antagonistDominant
            } else {
                upperLowerStatus = .optimal
            }
        }
        let upperLowerRatio: Double? = (upperLowerStatus != .insufficientData && lowerSets > 0)
            ? (Double(upperSets) / Double(lowerSets) * 100).rounded() / 100
            : nil
        let upperLowerAlertKey: String
        switch upperLowerStatus {
        case .primaryDominant: upperLowerAlertKey = "form_lab.balance.upper_dominant_alert"
        case .antagonistDominant: upperLowerAlertKey = "form_lab.balance.lower_dominant_alert"
        case .optimal: upperLowerAlertKey = "form_lab.balance.upper_lower_optimal"
        case .insufficientData: upperLowerAlertKey = "form_lab.balance.more_data_needed"
        }
        let upperLowerRecKey: String
        switch upperLowerStatus {
        case .primaryDominant: upperLowerRecKey = "form_lab.balance.upper_dominant_rec"
        case .antagonistDominant: upperLowerRecKey = "form_lab.balance.lower_dominant_rec"
        case .optimal: upperLowerRecKey = "form_lab.balance.upper_lower_optimal_rec"
        case .insufficientData: upperLowerRecKey = "form_lab.balance.log_more_workouts"
        }
        let upperLower = AntagonistRatio(
            id: "upper_lower",
            titleKey: "form_lab.balance.upper_lower_title",
            primaryLabelKey: "form_lab.balance.upper_label",
            antagonistLabelKey: "form_lab.balance.lower_label",
            primarySets: upperSets,
            antagonistSets: lowerSets,
            ratio: upperLowerRatio,
            optimalMin: 0.85,
            optimalMax: 2.20,
            status: upperLowerStatus,
            alertMessageKey: missingWorkKey(upperSets, lowerSets, "upper", "lower") ?? upperLowerAlertKey,
            recommendationKey: upperLowerRecKey
        )

        return AntagonistBalanceReport(
            pushPull: pushPull,
            quadHamstring: quadHam,
            upperLower: upperLower,
            totalWorkingSets: totalSets,
            unclassifiedWorkingSets: unclassifiedSets
        )
    }

    private static func missingWorkKey(_ primary: Int, _ antagonist: Int, _ primaryName: String, _ antagonistName: String) -> String? {
        if primary > 0 && antagonist == 0 { return "form_lab.balance.no_\(antagonistName)" }
        if antagonist > 0 && primary == 0 { return "form_lab.balance.no_\(primaryName)" }
        return nil
    }
}
