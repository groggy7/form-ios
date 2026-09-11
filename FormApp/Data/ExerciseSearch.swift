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
