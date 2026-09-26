import Foundation

/// Search tolerance must never change canonical IDs or merge catalogue entries.
enum ExerciseSearch {
    static func normalize(_ text: String) -> String {
        text.decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\\p{M}+", with: "", options: .regularExpression)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    struct Query {
        let phrase: String
        let tokens: [String]
        init(_ text: String) {
            phrase = ExerciseSearch.normalize(text)
            tokens = Array(Set(phrase.split(separator: " ").map(String.init)))
        }
    }

    private static let keywords: [String: Set<String>] = ExerciseCatalog.canonicalExercises.mapValues {
        Set($0.searchKeywords.flatMap { normalize($0).split(separator: " ").map(String.init) })
    }

    /// Exact/name matches precede helper keywords. Every query word must match.
    static func score(_ query: Query, exercise: Exercise, localizedName: String? = nil, category: String = "") -> Int? {
        if query.tokens.isEmpty { return 0 }
        let names = [exercise.name, localizedName ?? exercise.name].map(normalize)
        func matches(_ words: [String]) -> Bool {
            query.tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        }
        if names.contains(query.phrase) { return 0 }
        if names.contains(where: { $0.hasPrefix(query.phrase) }) { return 1 }
        if names.contains(where: { (" " + $0).contains(" " + query.phrase) }) { return 2 }
        if names.contains(where: { matches($0.split(separator: " ").map(String.init)) }) { return 3 }
        let words = names.flatMap { $0.split(separator: " ").map(String.init) }
            + Array(exercise.exerciseId.flatMap { keywords[$0] } ?? [])
            + normalize(category).split(separator: " ").map(String.init)
        return matches(words) ? 4 : nil
    }
}

/// UI-thread cache retained by AppStore across Library tab mounts. Keeps one filter result.
final class LibraryExerciseResults {
    private var source: [ExerciseCatalogEntry]?
    private var language: String?
    private var ordered: [ExerciseCatalogEntry] = []
    private struct Filter: Equatable {
        let query: String
        let equipment: String?
        let muscle: String?
    }
    private var lastFilter: Filter?
    private var lastResult: [ExerciseCatalogEntry] = []

    func entries(catalogue: [ExerciseCatalogEntry], query: String = "",
                 equipmentKey: String? = nil, muscleKey: String? = nil) -> [ExerciseCatalogEntry] {
        let currentLanguage = LanguageManager.shared.currentLanguage
        if source != catalogue || language != currentLanguage {
            source = catalogue
            language = currentLanguage
            // Custom exercise ties must follow the current localized names.
            ordered = catalogue.sorted { ExercisePriority.compare($0.exercise, $1.exercise) }
            lastFilter = nil
        }
        let filter = Filter(query: query, equipment: equipmentKey, muscle: muscleKey)
        if lastFilter == filter { return lastResult }
        let search = ExerciseSearch.Query(query)
        let matching = equipmentKey == nil && muscleKey == nil ? ordered : ordered.filter {
            (equipmentKey == nil || EquipmentCatalog.shared.matches($0.exercise.exerciseId, selected: equipmentKey)) &&
                ExerciseMetadata.matchesMuscle(exercise: $0.exercise, muscleKey: muscleKey)
        }
        if search.tokens.isEmpty {
            lastResult = matching
        } else {
            lastResult = matching.compactMap { entry -> (ExerciseCatalogEntry, Int)? in
                guard let score = ExerciseSearch.score(search, exercise: entry.exercise,
                    localizedName: entry.exercise.displayName,
                    category: "\(LanguageManager.t("category.\(entry.exercise.resolvedMovement.rawValue)")) \(entry.exercise.metadataSubtitle)") else { return nil }
                return (entry, score)
            // Swift's stable sort retains the cached priority order for equal scores.
            }.sorted { $0.1 < $1.1 }.map { $0.0 }
        }
        lastFilter = filter
        return lastResult
    }
}
