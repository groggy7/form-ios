import Foundation

public enum HistoryImportSource: String, Codable {
    case strong = "Strong"
    case hevy = "Hevy"

    public var displayName: String { rawValue }
}

public struct HistoryImportPreview: Codable, Identifiable {
    public var id: String { "\(source.rawValue)_\(totalWorkouts)_\(totalSetsCount)_\(earliestDate ?? "")" }
    public let source: HistoryImportSource
    public let totalWorkouts: Int
    public let newWorkoutsCount: Int
    public let duplicateWorkoutsCount: Int
    public let totalSetsCount: Int
    public let earliestDate: String?
    public let latestDate: String?
    public let canonicalMatchesCount: Int
    public let customExercisesCount: Int
    public let workoutsToImport: [WorkoutSessionRecord]

    public init(
        source: HistoryImportSource,
        totalWorkouts: Int,
        newWorkoutsCount: Int,
        duplicateWorkoutsCount: Int,
        totalSetsCount: Int,
        earliestDate: String?,
        latestDate: String?,
        canonicalMatchesCount: Int,
        customExercisesCount: Int,
        workoutsToImport: [WorkoutSessionRecord]
    ) {
        self.source = source
        self.totalWorkouts = totalWorkouts
        self.newWorkoutsCount = newWorkoutsCount
        self.duplicateWorkoutsCount = duplicateWorkoutsCount
        self.totalSetsCount = totalSetsCount
        self.earliestDate = earliestDate
        self.latestDate = latestDate
        self.canonicalMatchesCount = canonicalMatchesCount
        self.customExercisesCount = customExercisesCount
        self.workoutsToImport = workoutsToImport
    }
}

public struct HistoryImportResult: Codable {
    public let importedCount: Int
    public let skippedCount: Int
    public let backupFilePath: String?

    public init(importedCount: Int, skippedCount: Int, backupFilePath: String?) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.backupFilePath = backupFilePath
    }
}
