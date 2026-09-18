import Foundation

struct VolumeMatrixEngine {

    static let canonicalMuscles: [String] = [
        "chest", "front-delts", "biceps", "abs", "obliques", "quads",
        "upper-back", "lats", "triceps", "rear-delts", "glutes", "hamstrings", "calves"
    ]

    static func resolveExerciseId(exerciseName: String) -> String? {
        let raw = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let slug = raw.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        return slug
    }

    static func computeLoggedVolume(
        targetWeekKey: String,
        history: [WorkoutSessionRecord],
        catalog: ExerciseMuscleCatalog,
        language: String = "en"
    ) -> VolumeMatrixReport {
        var directSetsMap: [String: Int] = [:]
        var indirectSetsMap: [String: Int] = [:]
        var contributionsMap: [String: [MuscleVolumeContribution]] = [:]

        for muscle in canonicalMuscles {
            directSetsMap[muscle] = 0
            indirectSetsMap[muscle] = 0
            contributionsMap[muscle] = []
        }

        let weekRecords = history.filter { record in
            isRecordInWeek(record: record, targetWeekKey: targetWeekKey)
        }

        for record in weekRecords {
            let dateStr = recordDateString(record)
            for log in record.exerciseLogs {
                let completedSets = log.sets.filter { ($0.weightKg ?? 0) > 0 || ($0.reps ?? 0) > 0 }.count
                guard completedSets > 0 else { continue }

                let exerciseId = resolveExerciseId(exerciseName: log.exerciseName)
                guard let profile = catalog.profile(exerciseId) else { continue }

                for primary in profile.primary {
                    if canonicalMuscles.contains(primary) {
                        directSetsMap[primary, default: 0] += completedSets
                        contributionsMap[primary, default: []].append(
                            MuscleVolumeContribution(
                                exerciseName: log.exerciseName,
                                completedSets: completedSets,
                                effectiveSets: Float(completedSets) * 1.0,
                                isPrimary: true,
                                date: dateStr
                            )
                        )
                    }
                }

                for secondary in profile.secondary {
                    if canonicalMuscles.contains(secondary) {
                        indirectSetsMap[secondary, default: 0] += completedSets
                        contributionsMap[secondary, default: []].append(
                            MuscleVolumeContribution(
                                exerciseName: log.exerciseName,
                                completedSets: completedSets,
                                effectiveSets: Float(completedSets) * 0.5,
                                isPrimary: false,
                                date: dateStr
                            )
                        )
                    }
                }
            }
        }

        return buildReport(
            weekKey: targetWeekKey,
            isPlannedRoutine: false,
            directSetsMap: directSetsMap,
            indirectSetsMap: indirectSetsMap,
            contributionsMap: contributionsMap,
            catalog: catalog,
            language: language
        )
    }

    static func computePlannedRoutineVolume(
        program: Program,
        catalog: ExerciseMuscleCatalog,
        language: String = "en"
    ) -> VolumeMatrixReport {
        var directSetsMap: [String: Int] = [:]
        var indirectSetsMap: [String: Int] = [:]
        var contributionsMap: [String: [MuscleVolumeContribution]] = [:]

        for muscle in canonicalMuscles {
            directSetsMap[muscle] = 0
            indirectSetsMap[muscle] = 0
            contributionsMap[muscle] = []
        }

        for workout in program.workouts {
            let workoutTitle = workout.title.isEmpty ? "Day \(workout.day)" : workout.title
            for exercise in workout.exercises {
                let targetSets = exercise.sets ?? 3
                guard targetSets > 0 else { continue }

                let exerciseId = exercise.exerciseId ?? resolveExerciseId(exerciseName: exercise.name)
                guard let profile = catalog.profile(exerciseId) else { continue }

                for primary in profile.primary {
                    if canonicalMuscles.contains(primary) {
                        directSetsMap[primary, default: 0] += targetSets
                        contributionsMap[primary, default: []].append(
                            MuscleVolumeContribution(
                                exerciseName: exercise.name,
                                completedSets: targetSets,
                                effectiveSets: Float(targetSets) * 1.0,
                                isPrimary: true,
                                date: workoutTitle
                            )
                        )
                    }
                }

                for secondary in profile.secondary {
                    if canonicalMuscles.contains(secondary) {
                        indirectSetsMap[secondary, default: 0] += targetSets
                        contributionsMap[secondary, default: []].append(
                            MuscleVolumeContribution(
                                exerciseName: exercise.name,
                                completedSets: targetSets,
                                effectiveSets: Float(targetSets) * 0.5,
                                isPrimary: false,
                                date: workoutTitle
                            )
                        )
                    }
                }
            }
        }

        return buildReport(
            weekKey: "Planned Routine",
            isPlannedRoutine: true,
            directSetsMap: directSetsMap,
            indirectSetsMap: indirectSetsMap,
            contributionsMap: contributionsMap,
            catalog: catalog,
            language: language
        )
    }

    private static func buildReport(
        weekKey: String,
        isPlannedRoutine: Bool,
        directSetsMap: [String: Int],
        indirectSetsMap: [String: Int],
        contributionsMap: [String: [MuscleVolumeContribution]],
        catalog: ExerciseMuscleCatalog,
        language: String
    ) -> VolumeMatrixReport {
        var summaries: [String: MuscleVolumeSummary] = [:]
        var totalSets: Float = 0
        var optimalCount = 0
        var underTrainedCount = 0
        var highFatigueCount = 0

        let frontRegions = Set(catalog.views["front"]?.regions.keys.map { $0 } ?? [])

        for muscle in canonicalMuscles {
            let direct = directSetsMap[muscle] ?? 0
            let indirect = indirectSetsMap[muscle] ?? 0
            let effective = Float(direct) * 1.0 + Float(indirect) * 0.5
            totalSets += effective

            let landmarks = VolumeLandmark.forMuscle(muscle)
            let zone = landmarks.zone(for: effective)

            switch zone {
            case .optimalMav: optimalCount += 1
            case .underMev: underTrainedCount += 1
            case .highFatigue, .overMrv: highFatigueCount += 1
            default: break
            }

            let localized = catalog.muscles[muscle]?[language]
                ?? catalog.muscles[muscle]?["en"]
                ?? muscle

            let defaultView = frontRegions.contains(muscle) ? "front" : "back"
            let sortedContribs = (contributionsMap[muscle] ?? [])
                .sorted { $0.effectiveSets > $1.effectiveSets }

            summaries[muscle] = MuscleVolumeSummary(
                muscleKey: muscle,
                localizedName: localized,
                totalEffectiveSets: effective,
                directSets: direct,
                indirectSets: indirect,
                landmarks: landmarks,
                zone: zone,
                contributions: sortedContribs,
                defaultView: defaultView
            )
        }

        return VolumeMatrixReport(
            weekKey: weekKey,
            isPlannedRoutine: isPlannedRoutine,
            muscleSummaries: summaries,
            totalEffectiveSets: totalSets,
            optimalMuscleCount: optimalCount,
            underTrainedCount: underTrainedCount,
            highFatigueCount: highFatigueCount
        )
    }

    private static func isRecordInWeek(record: WorkoutSessionRecord, targetWeekKey: String) -> Bool {
        guard !targetWeekKey.isEmpty else { return false }
        let dateString = record.completedAt.isEmpty ? record.startedAt : record.completedAt
        guard let date = parseDate(dateString) else { return false }
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2 // Monday
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        let weekKey = String(format: "%04d-W%02d", year, week)
        return weekKey == targetWeekKey
    }

    private static func recordDateString(_ record: WorkoutSessionRecord) -> String? {
        let dateString = record.completedAt.isEmpty ? record.startedAt : record.completedAt
        guard let date = parseDate(dateString) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: string) { return d }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: string) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: string)
    }
}
