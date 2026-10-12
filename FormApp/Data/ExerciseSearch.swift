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

    struct Candidate {
        let names: [String]
        let nameWords: [[String]]
        let words: [String]
        init(exercise: Exercise, localizedName: String? = nil, category: String = "") {
            names = [exercise.name, localizedName ?? exercise.name].map(ExerciseSearch.normalize)
            nameWords = names.map { $0.split(separator: " ").map(String.init) }
            words = nameWords.flatMap { $0 }
                + Array(exercise.exerciseId.flatMap { ExerciseSearch.keywords[$0] } ?? [])
                + ExerciseSearch.normalize(category).split(separator: " ").map(String.init)
        }
    }

    /// Exact/name matches precede helper keywords. Every query word must match.
    static func score(_ query: Query, exercise: Exercise, localizedName: String? = nil, category: String = "") -> Int? {
        if query.tokens.isEmpty { return 0 }
        return score(query, candidate: Candidate(exercise: exercise, localizedName: localizedName, category: category))
    }

    static func score(_ query: Query, candidate: Candidate) -> Int? {
        if query.tokens.isEmpty { return 0 }
        func matches(_ words: [String]) -> Bool {
            query.tokens.allSatisfy { token in words.contains { $0.hasPrefix(token) } }
        }
        if candidate.names.contains(query.phrase) { return 0 }
        if candidate.names.contains(where: { $0.hasPrefix(query.phrase) }) { return 1 }
        if candidate.names.contains(where: { (" " + $0).contains(" " + query.phrase) }) { return 2 }
        if candidate.nameWords.contains(where: matches) { return 3 }
        return matches(candidate.words) ? 4 : nil
    }

}

/// UI-thread cache retained by AppStore across Library tab mounts. Keeps one filter result.
final class LibraryExerciseResults {
    private var source: [ExerciseCatalogEntry]?
    private var language: String?
    private var ordered: [ExerciseCatalogEntry] = []
    private var prepared: [(entry: ExerciseCatalogEntry, candidate: ExerciseSearch.Candidate)]?
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
            prepared = nil
        }
        let filter = Filter(query: query, equipment: equipmentKey, muscle: muscleKey)
        if lastFilter == filter { return lastResult }
        let search = ExerciseSearch.Query(query)
        func matchesFilters(_ entry: ExerciseCatalogEntry) -> Bool {
            (equipmentKey == nil || EquipmentCatalog.shared.matches(entry.exercise.exerciseId, selected: equipmentKey)) &&
                ExerciseMetadata.matchesMuscle(exercise: entry.exercise, muscleKey: muscleKey)
        }
        if search.tokens.isEmpty {
            lastResult = equipmentKey == nil && muscleKey == nil ? ordered : ordered.filter(matchesFilters)
        } else {
            // Build once on first search, preserving the empty-library launch path.
            let candidates = prepared ?? ordered.map { entry in
                (entry: entry, candidate: ExerciseSearch.Candidate(exercise: entry.exercise,
                    localizedName: entry.exercise.displayName,
                    category: "\(LanguageManager.t("category.\(entry.exercise.resolvedMovement.rawValue)")) \(entry.exercise.metadataSubtitle)"))
            }
            prepared = candidates
            lastResult = candidates.compactMap { item -> (ExerciseCatalogEntry, Int)? in
                guard matchesFilters(item.entry), let score = ExerciseSearch.score(search, candidate: item.candidate) else { return nil }
                return (item.entry, score)
            // Swift's stable sort retains the cached priority order for equal scores.
            }.sorted { $0.1 < $1.1 }.map { $0.0 }
        }
        lastFilter = filter
        return lastResult
    }
}
