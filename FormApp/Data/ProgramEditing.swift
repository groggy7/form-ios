import Foundation

/// Rules shared by the visual editor, program management and public file transfer.
enum ProgramEditing {
    static let movementAssets: Set<String> = ["jump-rope", "weighted-pull-up", "pull-up", "chest-supported-dumbbell-row", "push-up", "barbell-front-squat", "trap-bar-deadlift", "seated-leg-curl", "ab-wheel-rollout", "cable-lateral-raise", "overhead-cable-triceps-extension", "side-plank", "dead-bug", "hollow-body-hold", "reverse-crunch", "sliding-hamstring-curl", "pike-push-up", "band-face-pull", "incline-dumbbell-press", "dumbbell-step-up", "barbell-romanian-deadlift", "kettlebell-goblet-squat", "barbell-bench-press", "dumbbell-lateral-raise", "rope-triceps-pressdown", "single-leg-calf-raise", "standing-machine-calf-raise", "hanging-knee-raise", "barbell-back-squat", "conventional-barbell-deadlift", "dumbbell-romanian-deadlift", "standing-barbell-overhead-press", "dumbbell-floor-press", "dumbbell-hammer-curl", "straight-bar-cable-triceps-pressdown", "seated-machine-calf-raise", "kneeling-cable-crunch", "dumbbell-bench-press", "one-arm-dumbbell-row", "lat-pulldown", "rear-foot-elevated-split-squat", "leg-extension", "leg-press-45-degree", "lying-leg-curl", "pec-deck-fly", "ez-bar-curl", "barbell-hip-thrust", "barbell-row", "incline-barbell-bench-press", "incline-dumbbell-curl", "kettlebell-swing", "farmer-carry", "pallof-press", "push-press"]
    static let maxPrograms = 100
    static let maxExercises = 100
    static let coverIDs: Set<String> = ["hypertrophy", "powerbuilding", "push_pull_legs", "full_body", "home_dumbbells", "strength_power", "upper_lower", "machines"]

    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func require(_ condition: Bool, _ key: String) throws {
        if !condition { throw ValidationError(message: LanguageManager.t(key)) }
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", options: .regularExpression) == (value.startIndex..<value.endIndex)
    }

    static func validate(_ program: Program, original: Program? = nil, editingTitles: Bool = false) throws {
        try require(program.coverId.map { validID($0) } ?? true, "builder.invalidDetails")
        try require(validID(program.id), "builder.invalidIdentity")
        try require(!program.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && program.name.utf16.count <= 100, "builder.nameError")
        try require(program.description.utf16.count <= 500, "builder.descriptionError")
        try require(program.guidelines.count <= 50 && program.guidelines.allSatisfy { $0.utf16.count <= 500 }, "builder.notesError")
        try require(program.workouts.count <= 7 && Set(program.workouts.map(\.day)).count == program.workouts.count && program.workouts.allSatisfy { (1...7).contains($0.day) }, "builder.invalidDays")
        try require(Set(program.workouts.map(\.id)).count == program.workouts.count, "builder.invalidIdentity")
        for workout in program.workouts {
            try require(validID(workout.id), "builder.invalidIdentity")
            let previousTitle = original?.workouts.first { $0.id == workout.id }?.title
            try require(!workout.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && workout.title.utf16.count <= 100 && (!editingTitles || Workout.isValidTitle(workout.title, originalTitle: previousTitle)), "builder.invalidTitle")
            try require(workout.focus.utf16.count <= 180, "builder.focusError")
            try require(workout.exercises.count <= maxExercises, "builder.exerciseLimit")
            try require(Set(workout.exercises.map(\.id)).count == workout.exercises.count && workout.exercises.allSatisfy { validID($0.id) }, "builder.invalidIdentity")
            try require(Set(workout.targetMuscles).count == workout.targetMuscles.count && workout.targetMuscles.allSatisfy { MuscleGroup.fromKey($0) != nil }, "builder.invalidDetails")
            try require(["violet", "orange", "blue", "lime", "rose", "sand"].contains(workout.tone), "builder.invalidDetails")
            for exercise in workout.exercises {
                try require(!exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && exercise.name.utf16.count <= 100, "builder.nameError")
                try require(exercise.sets.map { (1...10).contains($0) } ?? true, "targets.invalid")
                try require(exercise.restSeconds.map { (0...900).contains($0) } ?? true, "builder.invalidRest")
                try require(exercise.prescription.utf16.count <= 100 && exercise.cues.utf16.count <= 1000 && exercise.avoid.utf16.count <= 1000 && exercise.cues.components(separatedBy: "\n").count <= 100 && exercise.avoid.components(separatedBy: "\n").count <= 100, "builder.invalidDetails")
                if let reps = exercise.reps {
                    let validRange = reps.min.map { min in reps.max.map { max in (1...999).contains(min) && (min...999).contains(max) } ?? false } ?? false
                    try require(exercise.sets != nil && exercise.prescription.isEmpty && (reps.toFailure ? reps.min == nil && reps.max == nil : validRange), "targets.invalid")
                }
                try require(exercise.movementType.map { MovementType(rawValue: $0) != nil } ?? true, "builder.invalidDetails")
                try require(exercise.movementAssetId.map { movementAssets.contains($0) } ?? true, "builder.invalidDetails")
                try require(exercise.exerciseId.map(validID) ?? true, "builder.invalidIdentity")
                try require(exercise.videos.count <= 3 && exercise.videos.allSatisfy { value in
                    guard value.utf16.count <= 2000, let url = URL(string: value, encodingInvalidCharacters: false), let scheme = url.scheme?.lowercased() else { return false }
                    return ["http", "https"].contains(scheme) && !(url.host ?? "").isEmpty
                }, "builder.invalidVideos")
            }
        }
    }

    static func selectionKey(_ exercise: Exercise) -> String {
        ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) ?? ExerciseCatalog.key(exercise.name)
    }

    /// Catalogue descriptions do not carry another workout's prescription into a new plan.
    static func picked(_ exercise: Exercise, defaultRest: Int) -> Exercise {
        var copy = exercise
        copy.id = UUID().uuidString
        let custom = exercise.reps == nil && !exercise.prescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        copy.sets = custom ? WorkoutSessionUtils.initialSetCount(exercise: exercise) : 3
        copy.reps = custom ? nil : RepTarget(min: 8, max: 12)
        copy.prescription = custom ? exercise.prescription : ""
        copy.restSeconds = defaultRest
        return copy
    }

    static func copyWorkout(_ workout: Workout, day: Int) -> Workout {
        var copy = workout
        copy.id = UUID().uuidString
        copy.day = day
        copy.exercises = workout.exercises.map { exercise in
            var copy = exercise
            copy.id = UUID().uuidString
            return copy
        }
        return copy
    }

    static func copyProgram(_ program: Program) -> Program {
        var copy = program
        copy.id = UUID().uuidString
        // Resolve template translations before the copy loses its template identity.
        copy.name = program.displayName
        copy.description = program.displayDescription
        copy.guidelines = program.displayGuidelines
        copy.workouts = program.workouts.map { workout in
            var copy = copyWorkout(workout, day: workout.day)
            copy.title = workout.displayTitle(programId: program.id)
            copy.focus = workout.displayFocus(programId: program.id)
            return copy
        }
        return copy
    }
}

struct ProgramBuilderDraft: Codable, Equatable {
    var program: Program
    var original: Program?
    var creatingCopy: Bool = false
    init(program: Program, original: Program?, creatingCopy: Bool = false) {
        self.program = program; self.original = original; self.creatingCopy = creatingCopy
    }
    private enum CodingKeys: String, CodingKey { case program, original, creatingCopy }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        program = try fields.decode(Program.self, forKey: .program)
        original = try fields.decodeIfPresent(Program.self, forKey: .original)
        creatingCopy = try fields.decodeIfPresent(Bool.self, forKey: .creatingCopy) ?? false
    }
}

/// Editor drafts are deliberately separate from saved plans, history and full backups.
enum ProgramBuilderDraftStore {
    static func key(_ id: String?) -> String { "program_builder_draft_v1:\(id ?? "new")" }
    static func load(_ id: String?, defaults: UserDefaults = .standard) -> ProgramBuilderDraft? {
        defaults.data(forKey: key(id)).flatMap { try? JSONDecoder().decode(ProgramBuilderDraft.self, from: $0) }
    }
    static func save(_ draft: ProgramBuilderDraft, id: String?, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: key(id)) }
    }
    static func clear(_ id: String?, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(id)) }
}

/// Undo restores only the removed item, preserving edits made afterward.
enum ProgramRemovalUndo {
    case workout(Workout, Int)
    case exercise(String, Exercise, Int)
    func restoring(_ current: Program) -> Program? {
        var restored = current
        switch self {
        case .workout(let workout, let index):
            guard restored.workouts.count < 7 && !restored.workouts.contains(where: { $0.day == workout.day || $0.id == workout.id }) else { return nil }
            restored.workouts.insert(workout, at: min(index, restored.workouts.count))
        case .exercise(let workoutID, let exercise, let index):
            guard let w = restored.workouts.firstIndex(where: { $0.id == workoutID }), restored.workouts[w].exercises.count < ProgramEditing.maxExercises,
                  !restored.workouts[w].exercises.contains(where: { $0.id == exercise.id }) else { return nil }
            restored.workouts[w].exercises.insert(exercise, at: min(index, restored.workouts[w].exercises.count))
        }
        return restored
    }
}
