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
    /// `area` labels a day's focus, `lead` names its emphasis, and `rank` orders exercises within a session.
    struct Role: Decodable { let area: String; let lead: String?; let rank: Int }
    let version: Int
    let equipment: [Equipment]
    let presets: [String: [String]]
    let candidates: [Candidate]
    /// Candidate weeks per day count, in preference order; entries name `slots`.
    let layouts: [String: [[String]]]
    let slots: [String: [String]]
    let regions: [String: [String]]
    let roles: [String: Role]
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
    private static let barbells: Set<String> = ["barbell", "ez-bar", "trap-bar"]
    private static let priorityCovers = ["push": "chest_side_pose", "row": "push_pull_legs", "squat": "upper_lower",
        "shoulders": "studio_lat_spread", "biceps": "biceps_peak_pose", "core": "core_abs_pose"]

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
    private static func kind(_ session: String) -> String { String(session.prefix { $0 != "." }) }
    /// Regions trained on back-to-back weekdays, Sunday to Monday included.
    private static func conflicts(_ layout: [String], days: [Int], catalog: TrainingCatalog) -> Int {
        layout.indices.reduce(0) { total, i in
            let next = (i + 1) % layout.count
            guard days[i] % 7 + 1 == days[next] else { return total }
            let shared = catalog.regions[kind(layout[next])] ?? []
            return total + (catalog.regions[kind(layout[i])] ?? []).filter(shared.contains).count
        }
    }
    /// The preferred week, or the first alternative that avoids back-to-back regions. Splits are offered only
    /// when the equipment can train every region they need; otherwise full-body days stay and a warning explains.
    static func layout(days: [Int], catalog: TrainingCatalog, eligible: [TrainingCatalog.Candidate]) -> [String]? {
        let trainable = Set(eligible.compactMap { catalog.roles[$0.role]?.lead })
        var best: (layout: [String], conflicts: Int)?
        for (index, layout) in (catalog.layouts[String(days.count)] ?? []).enumerated() {
            guard index == 0 || layout.allSatisfy({ (catalog.regions[kind($0)] ?? []).allSatisfy(trainable.contains) }) else { continue }
            let score = conflicts(layout, days: days, catalog: catalog)
            if best == nil || score < best!.conflicts { best = (layout, score) }
        }
        return best?.layout
    }
    /// Loaded work before bodyweight. Main lifts favour machines for beginners and barbells otherwise or for strength.
    private static func tier(_ row: TrainingCatalog.Candidate, profile: TrainingProfile, groups: [String: String]) -> Int {
        let gear = row.requirements.flatMap { $0 }
        let machine = gear.contains { groups[$0] == "machines" }
        if !machine && !gear.contains(where: { groups[$0] == "weights" }) { return 2 }
        if !row.compound { return 0 }
        if profile.experience == "beginner" && profile.goal != "strength" { return machine ? 0 : 1 }
        return gear.contains(where: barbells.contains) ? 0 : 1
    }
    private struct Pick { let row: TrainingCatalog.Candidate; let exercise: Exercise }

    static func generate(_ raw: TrainingProfile, catalog: TrainingCatalog, exercises: [String: ExerciseDefinition],
                         programID: String, text: (String, [String: Any]) -> String) throws -> GeneratedTrainingPlan {
        let profile = raw.normalized()
        guard profile.equipmentConfirmed, (2...6).contains(profile.selectedDays.count), catalog.goals[profile.goal] != nil,
              ["beginner", "intermediate", "advanced"].contains(profile.experience), catalog.presets[profile.location] != nil,
              profile.equipment.allSatisfy({ id in catalog.equipment.contains { $0.id == id } }) else { throw TrainingPlanError.incompleteProfile }
        let candidates = eligible(profile, catalog: catalog).filter { exercises[$0.id] != nil }
        guard !candidates.isEmpty else { throw TrainingPlanError.noExercises }
        let days = profile.selectedDays
        guard let layout = layout(days: days, catalog: catalog, eligible: candidates),
              layout.allSatisfy({ catalog.slots[$0] != nil && catalog.regions[kind($0)] != nil }),
              Set(catalog.candidates.map(\.role)).isSubset(of: catalog.roles.keys) else { throw TrainingPlanError.missingCatalog }
        let groups = Dictionary(catalog.equipment.map { ($0.id, $0.group) }, uniquingKeysWith: { first, _ in first })
        var uses: [String: Int] = [:], warnings: [String] = []
        func warn(_ key: String) { if !warnings.contains(key) { warnings.append(key) } }
        if !candidates.contains(where: { ["row", "pull"].contains($0.role) }) { warn("setup.warning.pulling") }
        if !candidates.contains(where: { ["hinge", "hamstrings"].contains($0.role) }) { warn("setup.warning.hamstrings") }
        if profile.equipment.contains("pull-up-bar") && profile.pullUpReps < 3 { warn("setup.warning.pullUps") }
        if profile.maxDumbbellKg != nil || profile.maxBarbellKg != nil { warn("setup.warning.loads") }
        if profile.equipment.contains(where: { ["band-bar", "sliders", "weight-vest", "dip-belt", "landmine", "box", "dip-station"].contains($0) }) { warn("setup.warning.accessories") }
        if layout != catalog.layouts[String(days.count)]?.first { warn("setup.warning.alternating") }
        else if conflicts(layout, days: days, catalog: catalog) > 0 { warn("setup.warning.adjacent") }
        // "Legs" priority covers single-leg work too.
        func prioritized(_ role: String) -> Bool { role == profile.priority || (profile.priority == "squat" && role == "lunge") }
        var picked = Array(repeating: [Pick](), count: layout.count)
        var seconds = Array(repeating: 300, count: layout.count) // Includes a five-minute warm-up; estimates include both sides.
        let slotLists: [[String]] = layout.map { session in
            var slots = catalog.slots[session] ?? []
            if !profile.priority.isEmpty, let position = slots.firstIndex(of: profile.priority), position > 3 {
                slots.remove(at: position); slots.insert(profile.priority, at: 4)
            }
            return slots
        }
        // Every day's lead keeps its best option and is chosen first; other slots then rotate away from it.
        for lead in [true, false] {
            for (index, slots) in slotLists.enumerated() {
                for (position, slot) in slots.enumerated() where (position == 0) == lead {
                    let roles = slot.components(separatedBy: "|")
                    let options = candidates.enumerated().filter { _, row in roles.contains(row.role) && !picked[index].contains { $0.row.id == row.id } }
                    let sorted = options.sorted { a, b in
                        func key(_ item: (offset: Int, element: TrainingCatalog.Candidate)) -> [Int] {
                            [roles.firstIndex(of: item.element.role) ?? 0, tier(item.element, profile: profile, groups: groups),
                             (lead ? 0 : (uses[item.element.id] ?? 0) * 8) + item.offset]
                        }
                        let ka = key(a), kb = key(b)
                        return ka == kb ? a.element.id < b.element.id : ka.lexicographicallyPrecedes(kb)
                    }
                    // When time is short, a shorter option for the same slot beats dropping the movement.
                    for row in sorted.map(\.element) {
                        guard let definition = exercises[row.id] else { continue }
                        let requirements = row.requirements.flatMap { $0 }
                        let loaded = requirements.contains { ["barbell", "dumbbells", "ez-bar", "trap-bar", "kettlebell", "leg-press", "chest-press", "shoulder-press"].contains($0) }
                        let strength = profile.goal == "strength" && row.compound && loaded
                        let light = requirements.contains("dumbbells") && (profile.maxDumbbellKg ?? 999) < 10
                        guard let policy = catalog.goals[strength && !light ? "strength" : "bulk"], policy.count == 3 else { throw TrainingPlanError.missingCatalog }
                        let range = row.pullUps > 0 ? [3, min(8, profile.pullUpReps), 120] : policy
                        let baseSets = profile.experience == "beginner" ? 2 : 3
                        var exercise = definition.toExercise()
                        exercise.sets = prioritized(row.role) ? min(4, baseSets + 1) : baseSets
                        exercise.reps = RepTarget(min: range[0], max: range[1], perSide: row.perSide)
                        exercise.restSeconds = row.compound ? range[2] + 30 : 60
                        // Retain the core movements before accessories when time is short.
                        if seconds[index] + estimateSeconds(exercise) > profile.minutes * 60 && (exercise.sets ?? 0) > 2 { exercise.sets = 2 }
                        if seconds[index] + estimateSeconds(exercise) > profile.minutes * 60 { continue }
                        picked[index].append(Pick(row: row, exercise: exercise)); seconds[index] += estimateSeconds(exercise)
                        uses[row.id, default: 0] += 1
                        break
                    }
                }
            }
        }
        guard picked.allSatisfy({ !$0.isEmpty }) else { throw TrainingPlanError.noExercises }
        let titles = layout.indices.map { title(session: layout[$0], picks: picked[$0], layout: layout, catalog: catalog, text: text) }
        let workouts: [Workout] = layout.indices.map { index in
            let day = days[index]
            // Main lifts first, then isolation, calves and core; the slot order only sets priority under time limits.
            let ordered = picked[index].enumerated().sorted { a, b in
                let ra = catalog.roles[a.element.row.role]?.rank ?? 0, rb = catalog.roles[b.element.row.role]?.rank ?? 0
                return ra == rb ? a.offset < b.offset : ra < rb
            }.map(\.element)
            let repeats = titles.indices.filter { titles[$0] == titles[index] }
            var areas: [String] = [], muscles: [String] = []
            for pick in ordered {
                if let area = catalog.roles[pick.row.role]?.area, !areas.contains(area) { areas.append(area) }
                for muscle in pick.row.muscles where !muscles.contains(muscle) { muscles.append(muscle) }
            }
            return Workout(id: "\(programID)-d\(day)", day: day,
                title: repeats.count < 2 ? titles[index] : text("setup.day.repeat", ["title": titles[index], "letter": String(UnicodeScalar(65 + repeats.firstIndex(of: index)!)!)]),
                focus: areas.prefix(4).map { text("setup.area.\($0)", [:]) }.joined(separator: " · "),
                exercises: ordered.enumerated().map { position, pick in
                    var exercise = pick.exercise; exercise.id = "\(programID)-d\(day)-\(position + 1)"; return exercise
                }, targetMuscles: muscles)
        }
        let rows = picked.flatMap { $0.map(\.row) }
        if Set(rows.map(\.role)).isDisjoint(with: ["row", "pull"]) { warn("setup.warning.pulling") }
        let estimates = workouts.map { (300 + $0.exercises.reduce(0) { $0 + estimateSeconds($1) } + 59) / 60 }
        let gear = Set(rows.flatMap { $0.requirements.flatMap { $0 } })
        let equipment: String?
        if gear.contains(where: { groups[$0] == "machines" || barbells.contains($0) }) { equipment = nil }
        else if gear.contains("dumbbells") { equipment = "dumbbells" }
        else if gear.contains("kettlebell") { equipment = "kettlebell" }
        else if gear.contains(where: { groups[$0] == "weights" }) { equipment = nil }
        else if gear.contains("bands") { equipment = "bands" }
        else { equipment = "bodyweight" }
        let kinds = Set(layout.map(kind))
        let structure = kinds == ["full"] ? "full" : kinds.isSubset(of: ["upper", "lower"]) ? "upperLower"
            : kinds.isSubset(of: ["push", "pull", "lower"]) ? "ppl" : "hybrid"
        var nameArgs: [String: Any] = ["goal": text("setup.name.goal.\(profile.goal)", [:]), "days": days.count,
                                       "structure": text("setup.name.structure.\(structure)", [:])]
        let name: String
        if let equipment {
            nameArgs["equipment"] = text("setup.name.equipment.\(equipment)", [:])
            name = text("setup.name.formatEquipment", nameArgs)
        } else { name = text("setup.name.format", nameArgs) }
        // Cable and machine isolation is common everywhere; main lifts decide whether a plan is machine based.
        let mainLifts = rows.filter { catalog.roles[$0.role]?.rank == 0 }
        let machineLifts = mainLifts.filter { $0.requirements.flatMap { $0 }.contains { groups[$0] == "machines" } }.count
        // Priority poses first, then pictures of the equipment the plan uses, then goal and weekly structure.
        let coverId: String
        if let cover = priorityCovers[profile.priority] { coverId = cover }
        else if equipment == "bodyweight" || equipment == "bands" { coverId = gear.contains("pull-up-bar") ? "triceps_side_pose" : "core_abs_pose" }
        else if equipment == "kettlebell" { coverId = "studio_kettlebell_swing" }
        else if equipment == "dumbbells" { coverId = "home_dumbbells" }
        else if profile.goal == "strength" && (gear.contains("barbell") || gear.contains("trap-bar")) {
            coverId = structure == "full" ? "strength_power" : structure == "upperLower" ? "powerbuilding" : "studio_bench_press"
        } else if machineLifts * 2 > mainLifts.count { coverId = "machines" }
        else if profile.goal == "cut" { coverId = "obliques_side_pose" }
        else {
            switch structure {
            case "full": coverId = days.count == 2 ? "studio_chest_clasp" : "full_body"
            case "upperLower": coverId = "upper_lower"
            case "ppl": coverId = "push_pull_legs"
            default: coverId = "hypertrophy"
            }
        }
        let program = Program(id: programID, name: name,
            description: text("setup.program.summary", ["days": days.count, "minutes": profile.minutes]),
            guidelines: [text("setup.guideline.effort", [:]), text("setup.guideline.progress", [:]), text("setup.guideline.load", [:])] + warnings.map { text($0, [:]) },
            workouts: workouts, coverId: coverId)
        return GeneratedTrainingPlan(program: program, warningKeys: warnings, estimatedMinutes: estimates, generatorVersion: catalog.version)
    }

    /// Names a day by what it actually leads with, such as "Lower: Squat" or "Upper: Chest & Back".
    private static func title(session: String, picks: [Pick], layout: [String], catalog: TrainingCatalog,
                              text: (String, [String: Any]) -> String) -> String {
        let sessionKind = kind(session)
        func lead(_ group: String) -> String? { picks.first { catalog.roles[$0.row.role]?.lead == group }?.row.role }
        var leads: [String] = []
        switch sessionKind {
        case "upper":
            var groups: [String] = []
            for pick in picks { if let group = catalog.roles[pick.row.role]?.lead, group != "lower", !groups.contains(group) { groups.append(group) } }
            leads = groups.compactMap(lead)
        case "push", "pull": leads = [lead(sessionKind)].compactMap { $0 }
        default: leads = [lead("lower")].compactMap { $0 }
        }
        let emphasis = leads.map { text("setup.emphasis.\($0)", [:]) }
        // Leg sessions beside push and pull days read as "Legs", as in a push/pull/legs split.
        let label = text("setup.day.\(sessionKind == "lower" && layout.contains { ["push", "pull"].contains(kind($0)) } ? "legs" : sessionKind)", [:])
        switch emphasis.count {
        case 0: return label
        case 1: return text("setup.day.titled", ["kind": label, "emphasis": emphasis[0]])
        default: return text("setup.day.titled", ["kind": label, "emphasis": text("setup.emphasis.pair", ["first": emphasis[0], "second": emphasis[1]])])
        }
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
