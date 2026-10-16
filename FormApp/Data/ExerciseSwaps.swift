import Foundation

struct ExerciseSwapCatalog: Decodable {
    struct Pattern: Decodable { let family: String; let related: [String] }
    struct Station: Decodable { let kind: String }
    struct Row: Decodable {
        let pattern: String
        let station: String
        let needs: [String]
        let mechanics: String
        let unilateral: Bool
        let ballistic: Bool
        let skill: Int
        let axialLoad: Int
    }
    struct Curated: Decodable { let samePattern: [String]; let relatedPattern: [String] }

    let version: Int
    let patterns: [String: Pattern]
    let stations: [String: Station]
    let exercises: [String: Row]
    let alternatives: [String: Curated]

    static let shared: ExerciseSwapCatalog = {
        guard let url = Bundle.main.url(forResource: "exercise_swaps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(ExerciseSwapCatalog.self, from: data) else {
            assertionFailure("Missing exercise swap catalogue")
            return ExerciseSwapCatalog(version: 0, patterns: [:], stations: [:], exercises: [:], alternatives: [:])
        }
        return catalog
    }()
}

/// A substitute offered for a busy or missing station, best first within its group.
struct ExerciseSwapSuggestion: Hashable {
    let exerciseId: String
    let samePattern: Bool
}

/// "Machine taken?" substitutes from the shared exercise_swaps.json (see gym/docs/design/exercise-swaps.md).
/// Curated lists come first; other canonical exercises use the documented runtime ranker.
enum ExerciseSwaps {
    static let maxSuggestions = 6

    static func suggestions(
        for exerciseId: String?,
        excluding exclude: Set<String> = [],
        catalog: ExerciseSwapCatalog = .shared,
        primaryMuscles: (String) -> [String] = { ExerciseMuscleCatalog.shared?.exercises[$0]?.primary ?? [] }
    ) -> [ExerciseSwapSuggestion] {
        guard let id = exerciseId, let source = catalog.exercises[id] else { return [] }
        if let curated = catalog.alternatives[id] {
            return (curated.samePattern.map { ExerciseSwapSuggestion(exerciseId: $0, samePattern: true) }
                + curated.relatedPattern.map { ExerciseSwapSuggestion(exerciseId: $0, samePattern: false) })
                .filter { !exclude.contains($0.exerciseId) }
        }
        let primary = Set(primaryMuscles(id))
        let related = catalog.patterns[source.pattern]?.related ?? []
        let candidates = catalog.exercises.filter { other, row in
            other != id && !exclude.contains(other) && row.station != source.station &&
                (row.pattern == source.pattern || related.contains(row.pattern)) &&
                primaryMuscles(other).contains(where: primary.contains) &&
                row.skill <= source.skill + 1 && row.axialLoad <= source.axialLoad + 1 &&
                (source.ballistic || !row.ballistic)
        }
        func rank(_ row: ExerciseSwapCatalog.Row) -> [Int] {
            [row.pattern == source.pattern ? 0 : 1, abs(row.skill - source.skill), abs(row.axialLoad - source.axialLoad),
             row.unilateral == source.unilateral ? 0 : 1, row.mechanics == source.mechanics ? 0 : 1]
        }
        // Ties fall back to the ID, as on Android.
        return candidates.sorted { a, b in
            let (ra, rb) = (rank(a.value), rank(b.value))
            return ra == rb ? a.key < b.key : ra.lexicographicallyPrecedes(rb)
        }
        .prefix(maxSuggestions)
        .map { ExerciseSwapSuggestion(exerciseId: $0.key, samePattern: $0.value.pattern == source.pattern) }
    }

    /// The substitute for this session only: same sets, rep range and rest; the per-side flag follows the
    /// substitute's laterality. Logs go under the substitute's canonical ID, so no load carries over.
    static func replacement(
        for original: Exercise,
        substituteId: String,
        takenIds: Set<String>,
        catalog: ExerciseSwapCatalog = .shared
    ) -> Exercise? {
        guard let definition = ExerciseCatalog.canonicalExercises[substituteId] else { return nil }
        var reps = original.reps
        if let unilateral = catalog.exercises[substituteId]?.unilateral, reps?.toFailure == false {
            reps?.perSide = unilateral
        }
        let base = String("\(original.id)-swap-\(substituteId)".prefix(96))
        var id = base
        while takenIds.contains(id) { id = "\(base)-\(id.count)" }
        var exercise = definition.toExercise()
        exercise.id = id
        exercise.sets = original.sets ?? WorkoutSessionUtils.initialSetCount(exercise: original)
        exercise.reps = reps
        exercise.prescription = reps == nil ? original.prescription : ""
        exercise.restSeconds = original.restSeconds
        return exercise
    }
}

extension ActiveSessionDraft {
    /// Session-only "Machine taken?" substitute; unchanged once a working set of the original is completed.
    func replacingExercise(_ exerciseId: String, with replacement: Exercise) -> ActiveSessionDraft {
        guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }),
              !workout.exercises.contains(where: { $0.id == replacement.id }),
              !(setsByExercise[exerciseId] ?? []).contains(where: { $0.isCompleted && !$0.isWarmup }) else { return self }
        var copy = self
        copy.workout.exercises[index] = replacement
        copy.setsByExercise[exerciseId] = nil
        copy.setsByExercise[replacement.id] = (1...WorkoutSessionUtils.initialSetCount(exercise: replacement))
            .map { WorkoutSessionUtils.newSet(exercise: replacement, number: $0) }
        return copy
    }
}
