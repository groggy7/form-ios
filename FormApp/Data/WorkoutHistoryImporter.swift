import Foundation

public enum WorkoutHistoryImporter {

    private static func extractDayKey(_ isoTimestamp: String) -> String {
        String(isoTimestamp.prefix(10))
    }

    private static func isDuplicate(candidate: WorkoutSessionRecord, existing: WorkoutSessionRecord) -> Bool {
        let candidateDay = extractDayKey(candidate.startedAt)
        let existingDay = extractDayKey(existing.startedAt)
        if candidateDay != existingDay { return false }

        // Match on title
        let candidateTitle = candidate.workoutTitle.trimmingCharacters(in: .whitespaces).lowercased()
        let existingTitle = existing.workoutTitle.trimmingCharacters(in: .whitespaces).lowercased()
        if candidateTitle == existingTitle { return true }

        // Match on sets and volume proximity
        if candidate.totalCompletedSets == existing.totalCompletedSets && candidate.totalCompletedSets > 0 {
            let volumeDiff = abs(candidate.totalVolumeKg - existing.totalVolumeKg)
            let maxVol = max(candidate.totalVolumeKg, existing.totalVolumeKg)
            if maxVol == 0.0 || volumeDiff / maxVol < 0.05 {
                return true
            }
        }

        // Match on identical exercise sequence
        let candidateExs = candidate.exerciseLogs.map { $0.exerciseName.trimmingCharacters(in: .whitespaces).lowercased() }
        let existingExs = existing.exerciseLogs.map { $0.exerciseName.trimmingCharacters(in: .whitespaces).lowercased() }
        if !candidateExs.isEmpty && candidateExs == existingExs {
            return true
        }

        return false
    }

    public static func preview(
        csvText: String,
        existingHistory: [WorkoutSessionRecord],
        canonicalNames: [String]
    ) throws -> HistoryImportPreview {
        let rows = CsvParser.parse(csvText)
        guard !rows.isEmpty else {
            throw NSError(domain: "FormApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected file is empty."])
        }

        let header = rows[0]
        let source: HistoryImportSource
        if StrongCsvParser.isStrongCsv(header) {
            source = .strong
        } else if HevyCsvParser.isHevyCsv(header) {
            source = .hevy
        } else {
            throw NSError(domain: "FormApp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unrecognized CSV format. Please provide a workout export from Strong or Hevy."])
        }

        let allParsedWorkouts: [WorkoutSessionRecord]
        switch source {
        case .strong:
            allParsedWorkouts = StrongCsvParser.parse(rows: rows, canonicalNames: canonicalNames)
        case .hevy:
            allParsedWorkouts = HevyCsvParser.parse(rows: rows, canonicalNames: canonicalNames)
        }

        guard !allParsedWorkouts.isEmpty else {
            throw NSError(domain: "FormApp", code: 3, userInfo: [NSLocalizedDescriptionKey: "No workout sessions found in this CSV."])
        }

        var newWorkouts: [WorkoutSessionRecord] = []
        var duplicateCount = 0

        for parsed in allParsedWorkouts {
            let isDup = existingHistory.contains(where: { isDuplicate(candidate: parsed, existing: $0) }) ||
                        newWorkouts.contains(where: { isDuplicate(candidate: parsed, existing: $0) })
            if isDup {
                duplicateCount += 1
            } else {
                newWorkouts.append(parsed)
            }
        }

        let allExercises = Array(Set(allParsedWorkouts.flatMap { $0.exerciseLogs }.map { $0.exerciseName }))
        let canonicalMatches = allExercises.filter { ex in
            canonicalNames.contains(where: { $0.caseInsensitiveCompare(ex) == .orderedSame })
        }.count
        let customExercises = allExercises.count - canonicalMatches

        let totalSets = allParsedWorkouts.reduce(0) { $0 + $1.totalCompletedSets }
        let sortedDates = allParsedWorkouts.map { extractDayKey($0.startedAt) }.sorted()
        let earliestDate = sortedDates.first
        let latestDate = sortedDates.last

        return HistoryImportPreview(
            source: source,
            totalWorkouts: allParsedWorkouts.count,
            newWorkoutsCount: newWorkouts.count,
            duplicateWorkoutsCount: duplicateCount,
            totalSetsCount: totalSets,
            earliestDate: earliestDate,
            latestDate: latestDate,
            canonicalMatchesCount: canonicalMatches,
            customExercisesCount: customExercises,
            workoutsToImport: newWorkouts
        )
    }
}
