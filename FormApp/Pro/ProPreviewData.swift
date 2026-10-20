import Foundation

public enum ProPreviewData {

    /// Rep Lab's locked Joints tab: two fixed exercises, ordered by the real rules.
    public static func jointJournalSample(today: String) -> [JointExerciseSummary] {
        func summary(_ name: String, _ ratings: [JointStress], _ loads: [Double]) -> JointExerciseSummary {
            let todayNumber = BodyDay.number(today) ?? 0
            let entries = zip(ratings, loads).enumerated().map { index, pair in
                JointRatingEntry(date: BodyDay.string(todayNumber - ((ratings.count - 1 - index) * 7 + 2)), rating: pair.0, topLoadKg: pair.1)
            }
            return JointExerciseSummary(exerciseName: name, recent: entries, total: entries.count,
                                        high: ratings.filter { $0 == .high }.count, mild: ratings.filter { $0 == .mild }.count,
                                        none: ratings.filter { $0 == .noStress }.count, latest: entries.last?.date ?? today)
        }
        return [
            summary("Barbell Back Squat", [.noStress, .mild, .high, .mild, .noStress, .noStress], [100, 105, 110, 107.5, 105, 105]),
            summary("Barbell Bench Press", [.noStress, .noStress, .mild, .noStress, .noStress, .noStress], [80, 80, 82.5, 82.5, 85, 85])
        ]
    }

    public static func hasWorkingHistory(_ history: [WorkoutSessionRecord]) -> Bool {
        return history.contains { session in
            session.exerciseLogs.contains { log in
                log.sets.contains { set in
                    !set.isWarmup && ((set.weightKg ?? 0.0) > 0.0 || (set.reps ?? 0) > 0)
                }
            }
        }
    }

    /// The sample week shown blurred behind the lock and sharp in the one-time preview
    /// (gym/docs/design/app-tour.md §5). Counts go through the real credit and zone rules, so
    /// every zone appears on both body views without typed totals.
    private static let sampleDirectSets: [String: Int] = [
        "chest": 12, "side-delts": 12, "biceps": 6, "abs": 4, "obliques": 2, "quads": 18,
        "upper-back": 10, "lats": 12, "triceps": 10, "rear-delts": 4, "glutes": 4,
        "hamstrings": 9, "calves": 6
    ]
    private static let sampleIndirectSets: [String: Int] = [
        "front-delts": 10, "biceps": 8, "forearms": 6, "quads": 6, "adductors": 8, "upper-back": 8,
        "lats": 2, "lower-back": 6, "triceps": 18, "rear-delts": 10, "glutes": 14
    ]
    private static let sampleChestWork = ["Barbell Bench Press", "Incline Dumbbell Press", "Cable Standing Fly"].map {
        MuscleVolumeContribution(exerciseName: $0, completedSets: 4, effectiveSets: 4, isPrimary: true, date: nil)
    }
    public static let sampleWorkingSets = 96

    public static func volumeMatrixPreviewReport(language: String = LanguageManager.shared.currentLanguage) -> VolumeMatrixReport {
        VolumeMatrixEngine.reportFromCounts(
            weekKey: "sample",
            directSets: sampleDirectSets,
            indirectSets: sampleIndirectSets,
            contributions: ["chest": sampleChestWork],
            language: language,
            workingSets: sampleWorkingSets
        )
    }

    public static let formLabRepMaxSummary: ExerciseRepMaxSummary = {
        let targets = [
            RepMaxTarget(reps: 1, estimatedWeightKg: 112.5, percentageOf1RM: 100.0),
            RepMaxTarget(reps: 2, estimatedWeightKg: 108.8, percentageOf1RM: 96.7),
            RepMaxTarget(reps: 3, estimatedWeightKg: 105.0, percentageOf1RM: 93.3),
            RepMaxTarget(reps: 4, estimatedWeightKg: 101.3, percentageOf1RM: 90.0),
            RepMaxTarget(reps: 5, estimatedWeightKg: 100.0, percentageOf1RM: 88.9),
            RepMaxTarget(reps: 6, estimatedWeightKg: 96.3, percentageOf1RM: 85.6),
            RepMaxTarget(reps: 8, estimatedWeightKg: 88.8, percentageOf1RM: 78.9),
            RepMaxTarget(reps: 10, estimatedWeightKg: 81.3, percentageOf1RM: 72.2),
            RepMaxTarget(reps: 12, estimatedWeightKg: 73.8, percentageOf1RM: 65.6)
        ]
        return ExerciseRepMaxSummary(
            exerciseId: "barbell_bench_press",
            exerciseName: "Barbell Bench Press",
            bestWeightKg: 100.0,
            bestReps: 5,
            achievedDate: "2026-09-15",
            estimated1rmKg: 112.5,
            formula: .brzycki,
            targets: targets
        )
    }()

    public static let formLabCurveReport: LongitudinalCurveReport = {
        let now = Date()
        let cal = Calendar.current
        let d1 = cal.date(byAdding: .day, value: -42, to: now) ?? now
        let d2 = cal.date(byAdding: .day, value: -28, to: now) ?? now
        let d3 = cal.date(byAdding: .day, value: -14, to: now) ?? now
        let points = [
            StrengthDataPoint(date: d1, dateString: "2026-08-10", topWeightKg: 85.0, topReps: 8, estimated1rmKg: 102.0, workoutTitle: "Upper Body"),
            StrengthDataPoint(date: d2, dateString: "2026-08-24", topWeightKg: 90.0, topReps: 6, estimated1rmKg: 105.0, workoutTitle: "Upper Body"),
            StrengthDataPoint(date: d3, dateString: "2026-09-07", topWeightKg: 95.0, topReps: 6, estimated1rmKg: 108.5, workoutTitle: "Upper Body"),
            StrengthDataPoint(date: now, dateString: "2026-09-20", topWeightKg: 100.0, topReps: 5, estimated1rmKg: 112.5, workoutTitle: "Upper Body")
        ]
        return LongitudinalCurveReport(
            exerciseName: "Barbell Bench Press",
            points: points,
            start1rmKg: 102.0,
            current1rmKg: 112.5,
            peak1rmKg: 112.5,
            deltaKg: 10.5,
            percentageGain: 10.3
        )
    }()

    public static let formLabBalanceReport: AntagonistBalanceReport = {
        let pushPull = AntagonistRatio(
            id: "push_pull",
            titleKey: "form_lab.balance.push_pull_title",
            primaryLabelKey: "form_lab.balance.push_label",
            antagonistLabelKey: "form_lab.balance.pull_label",
            primarySets: 18,
            antagonistSets: 16,
            ratio: 1.12,
            optimalMin: 0.80,
            optimalMax: 1.25,
            status: .optimal,
            alertMessageKey: "form_lab.balance.push_pull_optimal",
            recommendationKey: "form_lab.balance.push_pull_optimal_rec"
        )
        let quadHam = AntagonistRatio(
            id: "quad_hamstring",
            titleKey: "form_lab.balance.quad_ham_title",
            primaryLabelKey: "form_lab.balance.quad_label",
            antagonistLabelKey: "form_lab.balance.ham_label",
            primarySets: 16,
            antagonistSets: 12,
            ratio: 1.33,
            optimalMin: 0.75,
            optimalMax: 1.40,
            status: .optimal,
            alertMessageKey: "form_lab.balance.quad_ham_optimal",
            recommendationKey: "form_lab.balance.quad_ham_optimal_rec"
        )
        let upperLower = AntagonistRatio(
            id: "upper_lower",
            titleKey: "form_lab.balance.upper_lower_title",
            primaryLabelKey: "form_lab.balance.upper_label",
            antagonistLabelKey: "form_lab.balance.lower_label",
            primarySets: 34,
            antagonistSets: 28,
            ratio: 1.21,
            optimalMin: 0.85,
            optimalMax: 2.20,
            status: .optimal,
            alertMessageKey: "form_lab.balance.upper_lower_optimal",
            recommendationKey: "form_lab.balance.upper_lower_optimal_rec"
        )
        return AntagonistBalanceReport(
            pushPull: pushPull,
            quadHamstring: quadHam,
            upperLower: upperLower,
            totalWorkingSets: 90,
            unclassifiedWorkingSets: 0
        )
    }()
}
