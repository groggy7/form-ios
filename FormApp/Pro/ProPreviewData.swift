import Foundation

public enum ProPreviewData {

    public static func hasWorkingHistory(_ history: [WorkoutSessionRecord]) -> Bool {
        return history.contains { session in
            session.exerciseLogs.contains { log in
                log.sets.contains { set in
                    !set.isWarmup && ((set.weightKg ?? 0.0) > 0.0 || (set.reps ?? 0) > 0)
                }
            }
        }
    }

    private static func summary(
        muscle: String,
        name: String,
        effective: Float,
        direct: Int,
        indirect: Int,
        zone: VolumeZone,
        view: String
    ) -> MuscleVolumeSummary {
        MuscleVolumeSummary(
            muscleKey: muscle,
            localizedName: name,
            totalEffectiveSets: effective,
            directSets: direct,
            indirectSets: indirect,
            landmarks: VolumeLandmark.forMuscle(muscle),
            zone: zone,
            contributions: [],
            defaultView: view
        )
    }

    public static let volumeMatrixPreviewReport: VolumeMatrixReport = {
        let map: [String: MuscleVolumeSummary] = [
            // Front view
            "chest": summary(muscle: "chest", name: "Chest", effective: 14, direct: 14, indirect: 0, zone: .optimalMav, view: "front"),
            "front-delts": summary(muscle: "front-delts", name: "Front shoulders", effective: 8, direct: 4, indirect: 8, zone: .progressive, view: "front"),
            "side-delts": summary(muscle: "side-delts", name: "Side shoulders", effective: 22, direct: 22, indirect: 0, zone: .highFatigue, view: "front"),
            "biceps": summary(muscle: "biceps", name: "Biceps", effective: 14, direct: 12, indirect: 4, zone: .optimalMav, view: "front"),
            "abs": summary(muscle: "abs", name: "Abs", effective: 10, direct: 10, indirect: 0, zone: .progressive, view: "front"),
            "obliques": summary(muscle: "obliques", name: "Obliques", effective: 0, direct: 0, indirect: 0, zone: .underMev, view: "front"),
            "quads": summary(muscle: "quads", name: "Quads", effective: 16, direct: 16, indirect: 0, zone: .optimalMav, view: "front"),
            // Back view
            "upper-back": summary(muscle: "upper-back", name: "Upper back", effective: 22, direct: 18, indirect: 8, zone: .highFatigue, view: "back"),
            "lats": summary(muscle: "lats", name: "Lats", effective: 16, direct: 16, indirect: 0, zone: .optimalMav, view: "back"),
            "triceps": summary(muscle: "triceps", name: "Triceps", effective: 24, direct: 16, indirect: 16, zone: .overMrv, view: "back"),
            "rear-delts": summary(muscle: "rear-delts", name: "Rear shoulders", effective: 10, direct: 8, indirect: 4, zone: .progressive, view: "back"),
            "glutes": summary(muscle: "glutes", name: "Glutes", effective: 12, direct: 12, indirect: 0, zone: .optimalMav, view: "back"),
            "hamstrings": summary(muscle: "hamstrings", name: "Hamstrings", effective: 8, direct: 8, indirect: 0, zone: .progressive, view: "back"),
            "calves": summary(muscle: "calves", name: "Calves", effective: 4, direct: 4, indirect: 0, zone: .underMev, view: "back")
        ]

        return VolumeMatrixReport(
            weekKey: "2026-W38",
            isPlannedRoutine: false,
            muscleSummaries: map,
            totalEffectiveSets: 170,
            optimalMuscleCount: 5,
            underTrainedCount: 2,
            highFatigueCount: 3,
            totalWorkingSets: 140,
            unmappedExercises: [:]
        )
    }()

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
            titleKey: "form_lab.balance.push_pull",
            primaryLabelKey: "form_lab.balance.push",
            antagonistLabelKey: "form_lab.balance.pull",
            primarySets: 18,
            antagonistSets: 16,
            ratio: 1.12,
            optimalMin: 0.85,
            optimalMax: 1.25,
            status: .optimal,
            alertMessageKey: "",
            recommendationKey: "form_lab.balance.rec_optimal"
        )
        let quadHam = AntagonistRatio(
            id: "quad_hamstring",
            titleKey: "form_lab.balance.quad_ham",
            primaryLabelKey: "form_lab.balance.quad",
            antagonistLabelKey: "form_lab.balance.ham",
            primarySets: 16,
            antagonistSets: 12,
            ratio: 1.33,
            optimalMin: 1.0,
            optimalMax: 1.5,
            status: .optimal,
            alertMessageKey: "",
            recommendationKey: "form_lab.balance.rec_optimal"
        )
        let upperLower = AntagonistRatio(
            id: "upper_lower",
            titleKey: "form_lab.balance.upper_lower",
            primaryLabelKey: "form_lab.balance.upper",
            antagonistLabelKey: "form_lab.balance.lower",
            primarySets: 34,
            antagonistSets: 28,
            ratio: 1.21,
            optimalMin: 0.8,
            optimalMax: 1.4,
            status: .optimal,
            alertMessageKey: "",
            recommendationKey: "form_lab.balance.rec_optimal"
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
