import Foundation

public struct ExerciseIssueReport: Codable, Identifiable, Equatable {
    public let id: String
    public let exerciseId: String?
    public let exerciseName: String
    public let category: String
    public let comment: String
    public let timestamp: String

    public init(
        id: String = UUID().uuidString,
        exerciseId: String? = nil,
        exerciseName: String,
        category: String,
        comment: String = "",
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.category = category
        self.comment = comment
        self.timestamp = timestamp
    }
}

public final class ExerciseReportStore {
    public static let shared = ExerciseReportStore()

    public static let categories: [String] = [
        "animation_form",
        "technique_cue",
        "what_to_avoid",
        "muscles_worked",
        "equipment_category",
        "other"
    ]

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.form.gym.ExerciseReportStore", attributes: .concurrent)

    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = docs.appendingPathComponent("exercise_issue_reports.json")
        }
    }

    public func loadReports() -> [ExerciseIssueReport] {
        return queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode([ExerciseIssueReport].self, from: data)
            } catch {
                return []
            }
        }
    }

    @discardableResult
    public func saveReport(_ report: ExerciseIssueReport) -> [ExerciseIssueReport] {
        return queue.sync(flags: .barrier) {
            var existing = [ExerciseIssueReport]()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let data = try? Data(contentsOf: fileURL) {
                    if let decoded = try? JSONDecoder().decode([ExerciseIssueReport].self, from: data) {
                        existing = decoded
                    } else {
                        let corruptURL = fileURL.appendingPathExtension("corrupt.\(Int(Date().timeIntervalSince1970))")
                        try? data.write(to: corruptURL, options: .atomic)
                    }
                }
            }
            existing.append(report)
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(existing)
                let dir = fileURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                try data.write(to: fileURL, options: .atomic)
            } catch {
            }
            return existing
        }
    }
}
