import Foundation

struct TrainingProfile: Codable, Equatable {
    var version = 1
    var goal = "bulk"
    var experience = "beginner"
    var location = "commercial_gym"
    var equipment: [String] = []
    var equipmentConfirmed = false
    var selectedDays = [1, 3, 5]
    var minutes = 45
    var dumbbellPair = true
    var maxDumbbellKg: Double?
    var maxBarbellKg: Double?
    var pullUpReps = 0
    var advancedLifts = false
    var priority = ""
    var excludedExerciseIds: [String] = []

    func normalized() -> Self {
        var p = self
        p.selectedDays = Array(Set(selectedDays.filter { (1...7).contains($0) })).sorted()
        p.equipment = Array(Set(equipment)).sorted()
        p.minutes = min(max(minutes, 20), 90)
        p.maxDumbbellKg = maxDumbbellKg.flatMap { $0.isFinite && $0 > 0 && $0 <= 250 ? $0 : nil }
        p.maxBarbellKg = maxBarbellKg.flatMap { $0.isFinite && $0 > 0 && $0 <= 1000 ? $0 : nil }
        p.pullUpReps = min(max(pullUpReps, 0), 50)
        return p
    }
}

struct TrainingCatalog: Decodable {
    struct Equipment: Decodable { let id: String; let group: String; let artwork: String?; let home: Bool? }
    struct Candidate: Decodable {
        let id: String; let role: String; let requirements: [[String]]
        let pair: Bool; let advanced: Bool; let pullUps: Int
        let compound: Bool; let perSide: Bool; let muscles: [String]
    }
    let version: Int
    let equipment: [Equipment]
    let presets: [String: [String]]
    let candidates: [Candidate]
    let layouts: [String: [String]]
    let slots: [String: [String]]
    let goals: [String: [Int]]
    static let bundled: TrainingCatalog? = {
        guard let url = Bundle.main.url(forResource: "training_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }()
}

struct GeneratedTrainingPlan {
    let program: Program
    let warningKeys: [String]
    let estimatedMinutes: [Int]
    let generatorVersion: Int
}

enum TrainingPlanError: Error { case incompleteProfile, missingCatalog, noExercises }

enum TrainingPlanGenerator {
    static func capabilities(_ profile: TrainingProfile) -> Set<String> {
        var gear = Set(profile.equipment)
        if gear.contains("adjustable-bench") { gear.insert("bench") }
        return gear
    }
    static func eligible(_ profile: TrainingProfile, catalog: TrainingCatalog) -> [TrainingCatalog.Candidate] {
        let gear = capabilities(profile)
        return catalog.candidates.filter { row in
            !profile.excludedExerciseIds.contains(row.id) && (!row.pair || profile.dumbbellPair) &&
            (!row.advanced || (profile.advancedLifts && profile.experience != "beginner")) &&
            profile.pullUpReps >= row.pullUps && row.requirements.contains { $0.allSatisfy(gear.contains) }
        }
    }
    static func estimateSeconds(_ exercise: Exercise) -> Int {
        let sets = exercise.sets ?? 2, reps = exercise.reps?.max ?? 12
        let sides = exercise.reps?.perSide == true ? 2 : 1
        return sets * reps * 3 * sides + (sets - 1) * (exercise.restSeconds ?? 90) + 45
    }
    static func generate(_ raw: TrainingProfile, catalog: TrainingCatalog, exercises: [String: ExerciseDefinition],
                         programID: String, text: (String, [String: Any]) -> String) throws -> GeneratedTrainingPlan {
        let profile = raw.normalized()
        guard profile.equipmentConfirmed, (2...6).contains(profile.selectedDays.count), catalog.goals[profile.goal] != nil,
              ["beginner", "intermediate", "advanced"].contains(profile.experience), catalog.presets[profile.location] != nil,
              profile.equipment.allSatisfy({ id in catalog.equipment.contains { $0.id == id } }),
              let layout = catalog.layouts[String(profile.selectedDays.count)] else { throw TrainingPlanError.incompleteProfile }
        let candidates = eligible(profile, catalog: catalog).filter { exercises[$0.id] != nil }
        guard !candidates.isEmpty else { throw TrainingPlanError.noExercises }
        var uses: [String: Int] = [:], warnings: [String] = []
        func warn(_ key: String) { if !warnings.contains(key) { warnings.append(key) } }
        if !candidates.contains(where: { ["row", "pull"].contains($0.role) }) { warn("setup.warning.pulling") }
        if !candidates.contains(where: { ["hinge", "hamstrings"].contains($0.role) }) { warn("setup.warning.hamstrings") }
        if profile.equipment.contains("pull-up-bar") && profile.pullUpReps < 3 { warn("setup.warning.pullUps") }
        if profile.maxDumbbellKg != nil || profile.maxBarbellKg != nil { warn("setup.warning.loads") }
        if profile.equipment.contains(where: { ["band-bar", "sliders", "weight-vest", "dip-belt", "landmine", "box", "dip-station"].contains($0) }) { warn("setup.warning.accessories") }
        let days = profile.selectedDays
        if layout.contains("full") && days.contains(where: { days.contains(($0 % 7) + 1) }) { warn("setup.warning.adjacent") }
        var workouts: [Workout] = []
        for (index, kind) in layout.enumerated() {
            var chosen: [Exercise] = [], seconds = 300
            guard var slots = catalog.slots[kind] else { throw TrainingPlanError.missingCatalog }
            if !profile.priority.isEmpty, let position = slots.firstIndex(of: profile.priority), position > 3 {
                slots.remove(at: position); slots.insert(profile.priority, at: 4)
            }
            for slot in slots {
                let roles = slot.components(separatedBy: "|")
                let options = candidates.enumerated().filter { _, row in roles.contains(row.role) && !chosen.contains { $0.exerciseId == row.id } }
                let sorted = options.sorted { a, b in
                    let ra = [roles.firstIndex(of: a.element.role) ?? 0, (uses[a.element.id] ?? 0) * 8 + a.offset]
                    let rb = [roles.firstIndex(of: b.element.role) ?? 0, (uses[b.element.id] ?? 0) * 8 + b.offset]
                    return ra == rb ? a.element.id < b.element.id : ra.lexicographicallyPrecedes(rb)
                }
                guard let row = sorted.first?.element, let definition = exercises[row.id] else { continue }
                let requirements = row.requirements.flatMap { $0 }
                let loaded = requirements.contains { ["barbell", "dumbbells", "ez-bar", "trap-bar", "kettlebell", "leg-press", "chest-press", "shoulder-press"].contains($0) }
                let strength = profile.goal == "strength" && row.compound && loaded
                let light = requirements.contains("dumbbells") && (profile.maxDumbbellKg ?? 999) < 10
                guard let policy = catalog.goals[strength && !light ? "strength" : "bulk"], policy.count == 3 else { throw TrainingPlanError.missingCatalog }
                let range = row.pullUps > 0 ? [3, min(8, profile.pullUpReps), 120] : policy
                let baseSets = profile.experience == "beginner" ? 2 : 3
                let sets = row.role == profile.priority ? min(4, baseSets + 1) : baseSets
                var exercise = definition.toExercise()
                exercise.id = "\(programID)-d\(days[index])-\(chosen.count + 1)"
                exercise.sets = sets; exercise.reps = RepTarget(min: range[0], max: range[1], perSide: row.perSide)
                exercise.restSeconds = row.compound ? range[2] + 30 : 60
                if seconds + estimateSeconds(exercise) > profile.minutes * 60 && sets > 2 { exercise.sets = 2 }
                if seconds + estimateSeconds(exercise) > profile.minutes * 60 { continue }
                chosen.append(exercise); seconds += estimateSeconds(exercise)
                uses[row.id, default: 0] += 1
            }
            guard !chosen.isEmpty else { throw TrainingPlanError.noExercises }
            var muscles: [String] = []
            for exercise in chosen {
                for muscle in candidates.first(where: { $0.id == exercise.exerciseId })?.muscles ?? [] {
                    if !muscles.contains(muscle) { muscles.append(muscle) }
                }
            }
            workouts.append(Workout(id: "\(programID)-d\(days[index])", day: days[index],
                title: text("setup.workout.\(kind)", ["letter": String(UnicodeScalar(65 + index)!)]),
                focus: text("setup.workout.\(kind).focus", [:]), exercises: chosen, targetMuscles: muscles))
        }
        let coverage = Set(workouts.flatMap(\.exercises).compactMap { ex in candidates.first { $0.id == ex.exerciseId }?.role })
        if coverage.isDisjoint(with: ["row", "pull"]) { warn("setup.warning.pulling") }
        let estimates = workouts.map { (300 + $0.exercises.reduce(0) { $0 + estimateSeconds($1) } + 59) / 60 }
        let program = Program(id: programID, name: text("setup.program.name", [:]),
            description: text("setup.program.summary", ["days": days.count, "minutes": profile.minutes]),
            guidelines: [text("setup.guideline.effort", [:]), text("setup.guideline.progress", [:]), text("setup.guideline.load", [:])] + warnings.map { text($0, [:]) },
            workouts: workouts, coverId: profile.location == "home" && profile.equipment.contains("dumbbells") ? "home_dumbbells" : "full_body")
        return GeneratedTrainingPlan(program: program, warningKeys: warnings, estimatedMinutes: estimates, generatorVersion: catalog.version)
    }
}

enum TrainingSetupStore {
    struct Draft: Codable { var profile: TrainingProfile; var step: Int; var programId: String; var program: Program?; var flowVersion: Int? = 2 }
    static func draft() -> Draft? {
        guard var draft = read(Draft.self, key: "training_setup_draft_v1"), (1...(draft.flowVersion == 2 ? 7 : 6)).contains(draft.step) else { return nil }
        if draft.flowVersion != 2 { draft.step += draft.step >= 3 ? 1 : 0; draft.flowVersion = 2 }
        return draft
    }
    static func profile() -> TrainingProfile? { read(TrainingProfile.self, key: "training_profile_v1") }
    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    static func saveDraft(_ draft: Draft) { if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: "training_setup_draft_v1") } }
    static func saveProfile(_ profile: TrainingProfile) { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "training_profile_v1") } }
    static func clearDraft() { UserDefaults.standard.removeObject(forKey: "training_setup_draft_v1") }
    static func generate(_ profile: TrainingProfile, id: String) throws -> GeneratedTrainingPlan {
        guard let catalog = TrainingCatalog.bundled else { throw TrainingPlanError.missingCatalog }
        return try TrainingPlanGenerator.generate(profile, catalog: catalog, exercises: ExerciseCatalog.canonicalExercises,
            programID: id, text: { LanguageManager.t($0, $1) })
    }
}
