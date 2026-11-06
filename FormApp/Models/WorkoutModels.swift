import Foundation

public enum MovementType: String, Codable, CaseIterable {
    case press = "press"
    case pullUp = "pull-up"
    case row = "row"
    case shoulderRaise = "shoulder-raise"
    case curl = "curl"
    case triceps = "triceps"
    case squat = "squat"
    case hinge = "hinge"
    case lunge = "lunge"
    case calf = "calf"
    case core = "core"
    case conditioning = "conditioning"
    case boxing = "boxing"
    case other = "other"

    public var key: String { rawValue }

    public static func from(key: String?) -> MovementType {
        guard let key = key else { return .other }
        return MovementType(rawValue: key) ?? .other
    }

    public static func fromExerciseName(_ name: String) -> MovementType {
        let val = name.lowercased()
        if val.contains("leg raise") || val.contains("crunch") || val.contains("plank") { return .core }
        if val.contains("pull-up") || val.contains("pull up") || val.contains("chin-up") || val.contains("chin up") { return .pullUp }
        if val.contains("calf") { return .calf }
        if val.contains("lunge") || val.contains("split squat") { return .lunge }
        if val.contains("deadlift") || val.contains("rdl") || val.contains("hip hinge") { return .hinge }
        if val.contains("squat") { return .squat }
        if val.contains("row") { return .row }
        if val.contains("lateral") || val.contains("rear delt") || val.contains("reverse fly") { return .shoulderRaise }
        if val.contains("curl") { return .curl }
        if val.contains("tricep") || val.contains("close-grip") || val.contains("close grip") || val.contains("dip") { return .triceps }
        if val.contains("press") || val.contains("push-up") || val.contains("push up") { return .press }
        if val.contains("shadowboxing") || val.contains("bag") || val.contains("sparring") { return .boxing }
        if val.contains("jump rope") || val.contains("sprint") || val.contains("shuttle") || val.contains("burpee") || val.contains("ruck") { return .conditioning }
        return .other
    }
}

public enum BodyView: String, Codable, CaseIterable {
    case back = "back"
    case front = "front"
    case legsFront = "legs-front"
    case legsBack = "legs-back"

    public var artworkName: String {
        switch self {
        case .back: return "body_back"
        case .front: return "body_front"
        case .legsFront: return "body_legs_front"
        case .legsBack: return "body_legs_back"
        }
    }
}

public enum MuscleGroup: String, Codable, CaseIterable {
    case chest = "chest"
    case abs = "abs"
    case obliques = "obliques"
    case biceps = "biceps"
    case triceps = "triceps"
    case shoulders = "shoulders"
    case trapezius = "trapezius"
    case lats = "lats"
    case lowerBack = "lower-back"
    case forearms = "forearms"
    case quadriceps = "quadriceps"
    case adductors = "adductors"
    case hamstrings = "hamstrings"
    case calves = "calves"
    case tibialis = "tibialis"
    case glutes = "glutes"
    case frontDelts = "front-delts"
    case sideDelts = "side-delts"
    case rearDelts = "rear-delts"
    case upperBack = "upper-back"
    case hipFlexors = "hip-flexors"
    case hipAbductors = "hip-abductors"
    case serratus = "serratus"
    case rotatorCuff = "rotator-cuff"
    case neck = "neck"
    case deepCore = "deep-core"

    public var views: [BodyView] {
        switch self {
        case .chest, .abs, .obliques, .biceps, .frontDelts, .serratus, .deepCore:
            return [.front]
        case .triceps, .trapezius, .lats, .lowerBack, .upperBack, .rearDelts, .rotatorCuff:
            return [.back]
        case .shoulders:
            return [.back, .front]
        case .forearms, .sideDelts, .neck:
            return [.front, .back]
        case .quadriceps, .adductors, .tibialis, .hipFlexors:
            return [.legsFront]
        case .hamstrings, .calves, .glutes, .hipAbductors:
            return [.legsBack]
        }
    }

    public var hasSurfaceRegion: Bool { self != .hipFlexors && self != .deepCore }

    public static func fromKey(_ key: String?) -> MuscleGroup? {
        guard let key = key else { return nil }
        return MuscleGroup(rawValue: key)
    }
}

public struct RepTarget: Codable, Hashable {
    public var min: Int?
    public var max: Int?
    public var toFailure: Bool = false
    public var perSide: Bool = false

    public init(min: Int? = nil, max: Int? = nil, toFailure: Bool = false, perSide: Bool = false) {
        self.min = min
        self.max = max
        self.toFailure = toFailure
        self.perSide = perSide
    }

    private enum CodingKeys: String, CodingKey { case min, max, toFailure, perSide }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        min = try fields.decodeIfPresent(Int.self, forKey: .min)
        max = try fields.decodeIfPresent(Int.self, forKey: .max)
        toFailure = try fields.decodeIfPresent(Bool.self, forKey: .toFailure) ?? false
        perSide = try fields.decodeIfPresent(Bool.self, forKey: .perSide) ?? false
    }

    public var displayText: String {
        let base: String
        if toFailure {
            base = "technical failure"
        } else if let min = min, let max = max, min == max {
            base = "\(min)"
        } else if let min = min, let max = max {
            base = "\(min)–\(max)"
        } else if let min = min {
            base = "\(min)"
        } else {
            base = ""
        }
        return base + (perSide ? " / side" : "")
    }
}

public struct ExerciseDefinition: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var movementType: String
    public var movementAssetId: String?
    public var cues: [String]
    public var avoid: [String]
    public var cuesTr: [String]
    public var avoidTr: [String]
    public var searchKeywords: [String]

    public init(
        id: String,
        name: String,
        movementType: String,
        movementAssetId: String? = nil,
        cues: [String] = [],
        avoid: [String] = [],
        cuesTr: [String] = [],
        avoidTr: [String] = [],
        searchKeywords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.movementType = movementType
        self.movementAssetId = movementAssetId
        self.cues = cues
        self.avoid = avoid
        self.cuesTr = cuesTr
        self.avoidTr = avoidTr
        self.searchKeywords = searchKeywords
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, movementType, movementAssetId, cues, avoid, cuesTr, avoidTr, searchKeywords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.movementType = try container.decode(String.self, forKey: .movementType)
        self.movementAssetId = try container.decodeIfPresent(String.self, forKey: .movementAssetId)
        self.cues = (try? container.decode([String].self, forKey: .cues)) ?? []
        self.avoid = (try? container.decode([String].self, forKey: .avoid)) ?? []
        self.cuesTr = (try? container.decode([String].self, forKey: .cuesTr)) ?? []
        self.avoidTr = (try? container.decode([String].self, forKey: .avoidTr)) ?? []
        self.searchKeywords = (try? container.decode([String].self, forKey: .searchKeywords)) ?? []
    }

    public var cuesText: String { cues.joined(separator: "\n") }
    public var avoidText: String { avoid.joined(separator: "\n") }
    public var cuesTrText: String { cuesTr.joined(separator: "\n") }
    public var avoidTrText: String { avoidTr.joined(separator: "\n") }

    public func cuesText(lang: String) -> String {
        (lang == "tr" && !cuesTr.isEmpty) ? cuesTrText : cuesText
    }
    public func avoidText(lang: String) -> String {
        (lang == "tr" && !avoidTr.isEmpty) ? avoidTrText : avoidText
    }

    public func toExercise() -> Exercise {
        Exercise(
            id: id,
            name: name,
            exerciseId: id,
            prescription: "",
            cues: cuesText,
            avoid: avoidText,
            videos: [],
            sets: nil,
            reps: nil,
            restSeconds: nil,
            movementType: movementType,
            movementAssetId: movementAssetId
        )
    }
}

public struct Exercise: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var exerciseId: String?
    public var prescription: String
    public var cues: String
    public var avoid: String
    public var videos: [String]
    public var sets: Int?
    public var reps: RepTarget?
    public var restSeconds: Int?
    public var movementType: String?
    public var movementAssetId: String?
    public var setupNote: String?
    public var supersetId: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        exerciseId: String? = nil,
        prescription: String = "",
        cues: String? = nil,
        avoid: String? = nil,
        videos: [String] = [],
        sets: Int? = nil,
        reps: RepTarget? = nil,
        restSeconds: Int? = nil,
        movementType: String? = nil,
        movementAssetId: String? = nil,
        setupNote: String? = nil,
        supersetId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.exerciseId = exerciseId
        self.prescription = prescription
        self.cues = cues ?? exerciseId.flatMap { ExerciseCatalog.canonicalExercises[$0]?.cuesText } ?? ""
        self.avoid = avoid ?? exerciseId.flatMap { ExerciseCatalog.canonicalExercises[$0]?.avoidText } ?? ""
        self.videos = videos
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.movementType = movementType
        self.movementAssetId = movementAssetId
        self.setupNote = setupNote
        self.supersetId = supersetId
    }

    public var displayPrescription: String {
        if let sets = sets, let reps = reps {
            return "\(sets) × \(reps.displayText)"
        }
        if !prescription.trimmingCharacters(in: .whitespaces).isEmpty {
            return prescription
        }
        if let sets = sets {
            return "\(sets) sets"
        }
        return ""
    }

    public var resolvedMovement: MovementType {
        if let movementType = movementType {
            return MovementType.from(key: movementType)
        }
        return MovementType.fromExerciseName(name)
    }

    public var metadataSubtitle: String {
        ExerciseMetadata.format(self)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, exerciseId, prescription, cues, avoid, videos, sets, reps, restSeconds, movementType, movementAssetId, setupNote, supersetId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let exId = try container.decodeIfPresent(String.self, forKey: .exerciseId)
        self.exerciseId = exId
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        let def = exId.flatMap { ExerciseCatalog.canonicalExercises[$0] }
        let guidanceDefinition = def ?? (exId == nil ? ExerciseCatalog.canonicalExercises.values.first {
            ExerciseCatalog.key($0.name) == ExerciseCatalog.key(decodedName ?? "")
        } : nil)
        self.name = decodedName ?? def?.name ?? ""
        self.prescription = try container.decodeIfPresent(String.self, forKey: .prescription) ?? ""
        
        if let cuesStr = try? container.decode(String.self, forKey: .cues) {
            self.cues = cuesStr
        } else if let cuesArr = try? container.decode([String].self, forKey: .cues) {
            self.cues = cuesArr.joined(separator: "\n")
        } else {
            self.cues = guidanceDefinition?.cues.joined(separator: "\n") ?? ""
        }

        if let avoidStr = try? container.decode(String.self, forKey: .avoid) {
            self.avoid = avoidStr
        } else if let avoidArr = try? container.decode([String].self, forKey: .avoid) {
            self.avoid = avoidArr.joined(separator: "\n")
        } else {
            self.avoid = guidanceDefinition?.avoid.joined(separator: "\n") ?? ""
        }

        self.supersetId = try container.decodeIfPresent(String.self, forKey: .supersetId)
        self.setupNote = try container.decodeIfPresent(String.self, forKey: .setupNote)
        self.videos = try container.decodeIfPresent([String].self, forKey: .videos) ?? []
        self.sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        self.reps = try container.decodeIfPresent(RepTarget.self, forKey: .reps)
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.movementType = try container.decodeIfPresent(String.self, forKey: .movementType) ?? def?.movementType
        self.movementAssetId = try container.decodeIfPresent(String.self, forKey: .movementAssetId) ?? def?.movementAssetId
    }
}

public struct Workout: Identifiable, Codable, Hashable {
    public static let minTitleLength = 1
    public static let maxTitleLength = 24

    public static func titleLength(_ title: String) -> Int {
        title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    public static func isValidTitle(_ title: String, originalTitle: String? = nil) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let length = titleLength(trimmed)
        return length >= minTitleLength && (length <= maxTitleLength ||
            trimmed == originalTitle?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var id: String
    public var day: Int
    public var title: String
    public var focus: String
    public var tone: String
    public var exercises: [Exercise]
    public var targetMuscles: [String]

    public init(
        id: String = UUID().uuidString,
        day: Int,
        title: String,
        focus: String = "",
        tone: String = "violet",
        exercises: [Exercise] = [],
        targetMuscles: [String] = []
    ) {
        self.id = id
        self.day = day
        self.title = title
        self.focus = focus
        self.tone = tone
        self.exercises = exercises
        self.targetMuscles = targetMuscles
    }

    public var resolvedMuscles: [MuscleGroup] {
        mainFocus()
    }

    public static let maxFocusAreas = 4

    /// Primary working muscles only; legacy manual tags never override exercise metadata.
    func mainFocus(catalog: ExerciseMuscleCatalog? = ExerciseMuscleCatalog.shared) -> [MuscleGroup] {
        var scores: [MuscleGroup: Int] = [:]
        for exercise in exercises {
            let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name)
            let muscles = (catalog?.profile(id)?.primary ?? []).compactMap { key -> MuscleGroup? in
                switch key {
                case "quads": return .quadriceps
                default: return MuscleGroup.fromKey(key)
                }
            }
            for muscle in Set(muscles) {
                scores[muscle, default: 0] += WorkoutSessionUtils.initialSetCount(exercise: exercise)
            }
        }
        let order = MuscleGroup.allCases
        return Array(scores.keys.sorted {
            if scores[$0] != scores[$1] { return scores[$0, default: 0] > scores[$1, default: 0] }
            return order.firstIndex(of: $0)! < order.firstIndex(of: $1)!
        }.prefix(Self.maxFocusAreas))
    }

    enum CodingKeys: String, CodingKey {
        case id, day, title, focus, tone, exercises, targetMuscles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.day = try container.decode(Int.self, forKey: .day)
        self.title = try container.decode(String.self, forKey: .title)
        self.focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
        self.tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? "violet"
        self.exercises = try container.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        self.targetMuscles = try container.decodeIfPresent([String].self, forKey: .targetMuscles) ?? []
    }
}

public struct Program: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var description: String
    public var guidelines: [String]
    public var workouts: [Workout]
    public var coverId: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        guidelines: [String] = [],
        workouts: [Workout] = [],
        coverId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.guidelines = guidelines
        self.workouts = workouts
        self.coverId = Self.normalizedCoverId(coverId)
    }

    /// Retired leg pictures use the approved quadriceps cover in saved and imported programs.
    public static func normalizedCoverId(_ id: String?) -> String? {
        switch id {
        case "hamstrings_hinge", "glutes_hip_thrust", "calves_raise": return "upper_lower"
        default: return id
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, guidelines, workouts, coverId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.guidelines = try container.decodeIfPresent([String].self, forKey: .guidelines) ?? []
        self.workouts = try container.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        self.coverId = Self.normalizedCoverId(try container.decodeIfPresent(String.self, forKey: .coverId))
    }
}

public struct ExerciseSetLog: Identifiable, Codable, Hashable {
    public var id: String
    public var setNumber: Int
    public var weightInput: String
    public var repsInput: String
    public var weightKg: Double?
    public var completedReps: Int?
    public var isCompleted: Bool
    public var inputTouched: Bool?
    public var isWarmup: Bool
    /// Smart Progression's rep target, shown as the empty reps field's placeholder; never a logged value.
    public var targetReps: Int?
    /// `SetTechnique` code while the set has extensions (docs/design/intensity-sets.md).
    public var technique: String?
    /// Partial reps after the main part; nil hides the row, "" shows it empty.
    public var partialRepsInput: String?
    /// Drops or rest-pause efforts after the main part, in the order performed.
    public var extensions: [SetExtensionLog]?
    /// Reps in reserve the lifter reported for the main part, 0–4 (4 means four or more); docs/adaptive-training.md.
    public var rir: Int?

    enum CodingKeys: String, CodingKey {
        case id, setNumber, weightInput, repsInput, weightKg, completedReps, isCompleted, inputTouched, isWarmup, targetReps
        case technique, partialRepsInput, extensions, rir
    }

    public init(
        id: String = UUID().uuidString,
        setNumber: Int,
        weightInput: String = "",
        repsInput: String = "",
        weightKg: Double? = nil,
        completedReps: Int? = nil,
        isCompleted: Bool = false,
        inputTouched: Bool? = nil,
        isWarmup: Bool = false,
        targetReps: Int? = nil,
        technique: String? = nil,
        partialRepsInput: String? = nil,
        extensions: [SetExtensionLog]? = nil,
        rir: Int? = nil
    ) {
        self.rir = rir
        self.targetReps = targetReps
        self.id = id
        self.setNumber = setNumber
        self.weightInput = weightInput
        self.repsInput = repsInput
        self.weightKg = weightKg
        self.completedReps = completedReps
        self.isCompleted = isCompleted
        self.inputTouched = inputTouched
        self.isWarmup = isWarmup
        self.technique = technique
        self.partialRepsInput = partialRepsInput
        self.extensions = extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.setNumber = try container.decode(Int.self, forKey: .setNumber)
        self.weightInput = try container.decodeIfPresent(String.self, forKey: .weightInput) ?? ""
        self.repsInput = try container.decodeIfPresent(String.self, forKey: .repsInput) ?? ""
        self.weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        self.completedReps = try container.decodeIfPresent(Int.self, forKey: .completedReps)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.inputTouched = try container.decodeIfPresent(Bool.self, forKey: .inputTouched)
        self.isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        self.targetReps = try container.decodeIfPresent(Int.self, forKey: .targetReps)
        self.technique = try container.decodeIfPresent(String.self, forKey: .technique)
        self.partialRepsInput = try container.decodeIfPresent(String.self, forKey: .partialRepsInput)
        self.extensions = try container.decodeIfPresent([SetExtensionLog].self, forKey: .extensions)
        self.rir = (try? container.decodeIfPresent(Int.self, forKey: .rir)).flatMap { SetEffort.rirRange.contains($0) ? $0 : nil }
    }
}

/// An intensity technique on one set. Codes are shared with Android and backups.
public enum SetTechnique: String, Codable, CaseIterable {
    case drop
    case restPause
}

/// One drop or rest-pause effort in the active-session draft; ticked like a set row.
public struct SetExtensionLog: Identifiable, Codable, Hashable {
    public var id: String
    public var weightInput: String
    public var repsInput: String
    public var weightKg: Double?
    public var completedReps: Int?
    public var isCompleted: Bool
    public var partialRepsInput: String?

    public init(
        id: String = UUID().uuidString,
        weightInput: String = "",
        repsInput: String = "",
        weightKg: Double? = nil,
        completedReps: Int? = nil,
        isCompleted: Bool = false,
        partialRepsInput: String? = nil
    ) {
        self.id = id
        self.weightInput = weightInput
        self.repsInput = repsInput
        self.weightKg = weightKg
        self.completedReps = completedReps
        self.isCompleted = isCompleted
        self.partialRepsInput = partialRepsInput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.weightInput = try container.decodeIfPresent(String.self, forKey: .weightInput) ?? ""
        self.repsInput = try container.decodeIfPresent(String.self, forKey: .repsInput) ?? ""
        self.weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        self.completedReps = try container.decodeIfPresent(Int.self, forKey: .completedReps)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.partialRepsInput = try container.decodeIfPresent(String.self, forKey: .partialRepsInput)
    }
}

/// A saved drop or rest-pause effort. Optional fields keep a damaged record readable; backup restore validates them.
public struct SessionSetExtension: Codable, Hashable {
    public var weightKg: Double?
    public var reps: Int?
    public var partialReps: Int?

    public init(weightKg: Double?, reps: Int?, partialReps: Int? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.partialReps = partialReps
    }
}

public struct SessionSetLog: Codable, Hashable {
    public var setNumber: Int
    /// The main part: every metric that reads only these fields sees a correct straight set.
    public var weightKg: Double?
    public var reps: Int?
    public var isWarmup: Bool
    public var partialReps: Int?
    public var technique: String?
    public var extensions: [SessionSetExtension]?
    /// Reps in reserve the lifter reported for the main part (working sets only); see `SetEffort`.
    public var rir: Int?

    enum CodingKeys: String, CodingKey {
        case setNumber, weightKg, reps, isWarmup, partialReps, technique, extensions, rir
    }

    public init(setNumber: Int, weightKg: Double? = nil, reps: Int? = nil, isWarmup: Bool = false,
                partialReps: Int? = nil, technique: String? = nil, extensions: [SessionSetExtension]? = nil, rir: Int? = nil) {
        self.rir = rir
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
        self.partialReps = partialReps
        self.technique = technique
        self.extensions = extensions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.setNumber = try container.decode(Int.self, forKey: .setNumber)
        self.weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        self.reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        self.isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        self.partialReps = try container.decodeIfPresent(Int.self, forKey: .partialReps)
        self.technique = try container.decodeIfPresent(String.self, forKey: .technique)
        self.extensions = try container.decodeIfPresent([SessionSetExtension].self, forKey: .extensions)
        // Kept as written so backup restore can reject a value the logger never writes (SetEffort.restoreError).
        self.rir = try container.decodeIfPresent(Int.self, forKey: .rir)
    }

    /// Completed extensions in order; empty for a straight set.
    public var setExtensions: [SessionSetExtension] { extensions ?? [] }
    public var setTechnique: SetTechnique? { technique.flatMap(SetTechnique.init(rawValue:)) }
}

public struct SessionExerciseLog: Codable, Hashable {
    public var exerciseName: String
    public var sets: [SessionSetLog]
    public var targetSets: Int?
    /// Stable catalog identity for new records. Nil keeps older/imported history compatible.
    public var exerciseId: String?
    /// Optional Smart Progression rating: easy, right or hard.
    public var effort: String?
    /// Optional `JointStress` raw value: the user's own report, never used in a calculation.
    public var jointStress: String?
    public var setupNote: String?

    public init(exerciseName: String, sets: [SessionSetLog] = [], targetSets: Int? = nil, exerciseId: String? = nil, effort: String? = nil,
                jointStress: String? = nil, setupNote: String? = nil) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.targetSets = targetSets
        self.exerciseId = exerciseId
        self.effort = effort
        self.jointStress = jointStress
        self.setupNote = setupNote
    }
}

public struct WorkoutSessionRecord: Identifiable, Codable, Hashable {
    public var id: String
    public var programId: String
    public var workoutId: String
    public var workoutTitle: String
    public var startedAt: String
    public var completedAt: String
    public var durationSeconds: Int
    public var totalVolumeKg: Double
    public var totalCompletedSets: Int
    public var exerciseLogs: [SessionExerciseLog]
    public var isComplete: Bool?
    public var scheduledDate: String?
    public var workoutSnapshot: Workout?
    /// Android's local day for a session moved to another day; kept so backups round-trip.
    public var performedDate: String?
    public var note: String?

    public init(
        id: String = UUID().uuidString,
        programId: String,
        workoutId: String,
        workoutTitle: String,
        startedAt: String,
        completedAt: String,
        durationSeconds: Int,
        totalVolumeKg: Double = 0.0,
        totalCompletedSets: Int = 0,
        exerciseLogs: [SessionExerciseLog] = [],
        isComplete: Bool? = nil,
        scheduledDate: String? = nil,
        workoutSnapshot: Workout? = nil,
        performedDate: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.programId = programId
        self.workoutId = workoutId
        self.workoutTitle = workoutTitle
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.totalVolumeKg = totalVolumeKg
        self.totalCompletedSets = totalCompletedSets
        self.exerciseLogs = exerciseLogs
        self.isComplete = isComplete
        self.scheduledDate = scheduledDate
        self.workoutSnapshot = workoutSnapshot
        self.performedDate = performedDate
        self.note = note
    }
}

public struct RestTimerState: Codable, Hashable {
    public var exerciseName: String
    public var totalSeconds: Int
    public var isRunning: Bool
    public var endsAtEpochMillis: Int64?
    public var pausedSecondsRemaining: Int
    /// The set whose completion started this rest; ticking one of its extensions restarts it.
    public var setId: String?

    public init(
        exerciseName: String,
        totalSeconds: Int,
        isRunning: Bool,
        endsAtEpochMillis: Int64? = nil,
        pausedSecondsRemaining: Int = 0,
        setId: String? = nil
    ) {
        self.exerciseName = exerciseName
        self.totalSeconds = totalSeconds
        self.isRunning = isRunning
        self.endsAtEpochMillis = endsAtEpochMillis
        self.pausedSecondsRemaining = pausedSecondsRemaining
        self.setId = setId
    }

    public func secondsRemaining(nowEpochMillis: Int64) -> Int {
        if !isRunning {
            return max(0, pausedSecondsRemaining)
        }
        guard let end = endsAtEpochMillis else { return 0 }
        let diff = end - nowEpochMillis
        return max(0, Int((diff + 999) / 1000))
    }

    /// Holds a running rest at its remaining time; the workout screen and the watch share these transitions.
    public func paused(nowEpochMillis: Int64) -> RestTimerState {
        guard isRunning else { return self }
        var copy = self
        copy.pausedSecondsRemaining = secondsRemaining(nowEpochMillis: nowEpochMillis)
        copy.isRunning = false
        copy.endsAtEpochMillis = nil
        return copy
    }

    public func resumed(nowEpochMillis: Int64) -> RestTimerState {
        guard !isRunning, pausedSecondsRemaining > 0 else { return self }
        var copy = self
        copy.isRunning = true
        copy.endsAtEpochMillis = nowEpochMillis + Int64(pausedSecondsRemaining * 1000)
        return copy
    }

    /// Adds (or with a negative value removes) seconds; a rest reduced to zero stops.
    public func adjusted(by seconds: Int, nowEpochMillis: Int64) -> RestTimerState {
        var copy = self
        let remaining = max(0, secondsRemaining(nowEpochMillis: nowEpochMillis) + seconds)
        copy.totalSeconds = max(totalSeconds, remaining)
        copy.pausedSecondsRemaining = remaining
        if isRunning && remaining > 0 {
            copy.endsAtEpochMillis = nowEpochMillis + Int64(remaining * 1000)
        } else {
            copy.isRunning = false
            copy.endsAtEpochMillis = nil
        }
        return copy
    }
}

public struct ActiveSessionDraft: Identifiable, Codable, Hashable {
    /// 2 adds set techniques, partials and the rest timer's set.
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var id: String
    public var programId: String
    public var workout: Workout
    public var startedAt: String
    public var startedAtEpochMillis: Int64
    public var lastActivityEpochMillis: Int64
    public var currentExerciseIndex: Int
    public var setsByExercise: [String: [ExerciseSetLog]]
    public var weightInputUnit: WeightUnit?
    public var restTimer: RestTimerState?
    public var assignedCalendarDate: String?
    public var scheduledDate: String?
    public var accumulatedSeconds: Int
    public var isPaused: Bool
    public var lastResumedAtEpochMillis: Int64?
    /// Optional Smart Progression effort ratings by workout exercise ID.
    public var effortByExercise: [String: String]?
    /// Optional joint-stress ratings by workout exercise ID; the field is optional, so the schema stays 2.
    public var jointStressByExercise: [String: String]?
    public var note: String?

    public init(
        schemaVersion: Int = ActiveSessionDraft.currentSchemaVersion,
        id: String = UUID().uuidString,
        programId: String,
        workout: Workout,
        startedAt: String,
        startedAtEpochMillis: Int64,
        lastActivityEpochMillis: Int64? = nil,
        currentExerciseIndex: Int = 0,
        setsByExercise: [String: [ExerciseSetLog]] = [:],
        restTimer: RestTimerState? = nil,
        assignedCalendarDate: String? = nil,
        accumulatedSeconds: Int = 0,
        isPaused: Bool = false,
        lastResumedAtEpochMillis: Int64? = nil,
        scheduledDate: String? = nil,
        weightInputUnit: WeightUnit? = nil,
        effortByExercise: [String: String]? = nil,
        jointStressByExercise: [String: String]? = nil,
        note: String? = nil
    ) {
        self.effortByExercise = effortByExercise
        self.jointStressByExercise = jointStressByExercise
        self.note = note
        self.schemaVersion = schemaVersion
        self.id = id
        self.programId = programId
        self.workout = workout
        self.startedAt = startedAt
        self.startedAtEpochMillis = startedAtEpochMillis
        self.lastActivityEpochMillis = lastActivityEpochMillis ?? startedAtEpochMillis
        self.currentExerciseIndex = currentExerciseIndex
        self.setsByExercise = setsByExercise
        self.weightInputUnit = weightInputUnit
        self.restTimer = restTimer
        self.assignedCalendarDate = assignedCalendarDate
        self.scheduledDate = scheduledDate
        self.accumulatedSeconds = accumulatedSeconds
        self.isPaused = isPaused
        self.lastResumedAtEpochMillis = lastResumedAtEpochMillis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try container.decode(String.self, forKey: .id)
        self.programId = try container.decode(String.self, forKey: .programId)
        self.workout = try container.decode(Workout.self, forKey: .workout)
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.startedAtEpochMillis = try container.decode(Int64.self, forKey: .startedAtEpochMillis)
        self.lastActivityEpochMillis = try container.decodeIfPresent(Int64.self, forKey: .lastActivityEpochMillis) ?? self.startedAtEpochMillis
        self.currentExerciseIndex = try container.decodeIfPresent(Int.self, forKey: .currentExerciseIndex) ?? 0
        self.setsByExercise = try container.decodeIfPresent([String: [ExerciseSetLog]].self, forKey: .setsByExercise) ?? [:]
        self.weightInputUnit = try container.decodeIfPresent(WeightUnit.self, forKey: .weightInputUnit)
        self.restTimer = try container.decodeIfPresent(RestTimerState.self, forKey: .restTimer)
        self.assignedCalendarDate = try container.decodeIfPresent(String.self, forKey: .assignedCalendarDate)
        self.scheduledDate = try container.decodeIfPresent(String.self, forKey: .scheduledDate)
        self.accumulatedSeconds = try container.decodeIfPresent(Int.self, forKey: .accumulatedSeconds) ?? 0
        self.isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        self.lastResumedAtEpochMillis = try container.decodeIfPresent(Int64.self, forKey: .lastResumedAtEpochMillis)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.effortByExercise = try container.decodeIfPresent([String: String].self, forKey: .effortByExercise)?
            .filter { ProgressionEffort(rawValue: $0.value) != nil }
        self.jointStressByExercise = try container.decodeIfPresent([String: String].self, forKey: .jointStressByExercise)?
            .filter { JointStress(rawValue: $0.value) != nil }
    }

    public func currentDurationSeconds(nowEpochMillis: Int64) -> Int {
        if isPaused { return min(max(0, accumulatedSeconds), 6 * 3600) }
        let runningFrom = lastResumedAtEpochMillis ?? startedAtEpochMillis
        let additionalSeconds = Int(max(0, (nowEpochMillis - runningFrom) / 1000))
        return min(max(0, accumulatedSeconds + additionalSeconds), 6 * 3600)
    }

    public func paused(nowEpochMillis: Int64) -> ActiveSessionDraft {
        if isPaused { return self }
        var copy = self
        let runningFrom = lastResumedAtEpochMillis ?? startedAtEpochMillis
        let additionalSeconds = Int(max(0, (nowEpochMillis - runningFrom) / 1000))
        copy.accumulatedSeconds = min(max(0, accumulatedSeconds + additionalSeconds), 6 * 3600)
        copy.isPaused = true
        copy.lastActivityEpochMillis = nowEpochMillis
        if var rest = copy.restTimer, rest.isRunning {
            let remaining = rest.secondsRemaining(nowEpochMillis: nowEpochMillis)
            rest.isRunning = false
            rest.pausedSecondsRemaining = remaining
            rest.endsAtEpochMillis = nil
            copy.restTimer = rest
        }
        return copy
    }

    public func resumed(nowEpochMillis: Int64) -> ActiveSessionDraft {
        var copy = self
        copy.lastActivityEpochMillis = nowEpochMillis
        // Reopening a running workout must not discard the time since it last resumed.
        guard isPaused else { return copy }
        copy.isPaused = false
        copy.lastResumedAtEpochMillis = nowEpochMillis
        return copy
    }

    /// Clears a running rest whose deadline passed while the workout was not visible.
    /// Its system notification was the alert, so the workout must not chime again on return.
    public func clearingEndedRest(nowEpochMillis: Int64) -> ActiveSessionDraft {
        guard let rest = restTimer, rest.isRunning, let end = rest.endsAtEpochMillis, end <= nowEpochMillis else { return self }
        var copy = self
        copy.restTimer = nil
        return copy
    }
}

public enum ViewMode: String, Codable, CaseIterable {
    case programs
    case today
    case plan
    case library
    case history
}

public struct WeeklyArchive: Codable, Hashable {
    public var weekKey: String
    public var completed: [String]
    public var archivedAt: String
}

public enum WorkoutDayStatus: String, Codable, Comparable {
    case missed = "MISSED"
    case unfinished = "UNFINISHED"
    case completed = "COMPLETED"

    public var priority: Int {
        switch self {
        case .missed: return 0
        case .unfinished: return 1
        case .completed: return 2
        }
    }

    public static func < (lhs: WorkoutDayStatus, rhs: WorkoutDayStatus) -> Bool {
        lhs.priority < rhs.priority
    }
}

public struct WorkoutDayEntry: Identifiable, Codable, Hashable {
    public var id: String
    public var date: String
    public var status: WorkoutDayStatus

    public init(id: String, date: String, status: WorkoutDayStatus) {
        self.id = id
        self.date = date
        self.status = status
    }
}

public struct WorkoutCalendarHistory: Codable, Hashable {
    public var nextScheduledDate: String
    public var scheduledWeekdays: [Int]
    public var missedDates: [String]
    public var entries: [WorkoutDayEntry]

    public init(
        nextScheduledDate: String,
        scheduledWeekdays: [Int] = [],
        missedDates: [String] = [],
        entries: [WorkoutDayEntry] = []
    ) {
        self.nextScheduledDate = nextScheduledDate
        self.scheduledWeekdays = scheduledWeekdays
        self.missedDates = missedDates
        self.entries = entries
    }
}

public enum WorkoutCalendar {
    // History scans call these per record. Creating a formatter per call made calendar and
    // weekly totals scale with history on every redraw, so formatters are cached.
    // DateFormatter is thread safe once configured; ISO8601DateFormatter is not documented so.
    private static let formatterLock = NSLock()
    private static var dayFormatters: [TimeZone: DateFormatter] = [:]
    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func dayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = dayFormatters[timeZone] { return cached }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        dayFormatters[timeZone] = f
        return f
    }

    public static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        dayFormatter(timeZone).string(from: date)
    }

    public static func parseDate(_ string: String, timeZone: TimeZone = .current) -> Date? {
        guard string.count == 10 else { return nil }
        return dayFormatter(timeZone).date(from: string)
    }

    /// The fractional-second form records store; Home builds the live workout's record on every redraw.
    public static func formatIsoTimestamp(_ date: Date) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return isoFormatterWithFractionalSeconds.string(from: date)
    }

    /// Parsed history timestamps. An ISO parse costs tens of microseconds and redraws reread the same records.
    private static var parsedTimestamps: [String: Date?] = [:]

    public static func parseIsoTimestamp(_ timestamp: String?) -> Date? {
        guard let ts = timestamp, !ts.isEmpty else { return nil }
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = parsedTimestamps[ts] { return cached }
        let date = isoFormatterWithFractionalSeconds.date(from: ts) ?? isoFormatter.date(from: ts)
        if parsedTimestamps.count >= 20_000 { parsedTimestamps.removeAll(keepingCapacity: true) }
        parsedTimestamps[ts] = date
        return date
    }

    public static func localDate(from timestamp: String?, timeZone: TimeZone = .current) -> String? {
        guard let date = parseIsoTimestamp(timestamp) else { return nil }
        return formatDate(date, timeZone: timeZone)
    }

    public static func mondayOfCurrentWeek(for date: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let weekday = cal.component(.weekday, from: date)
        let leadingDays = (weekday + 5) % 7
        if let monday = cal.date(byAdding: .day, value: -leadingDays, to: date) {
            return formatDate(monday, timeZone: cal.timeZone)
        }
        return formatDate(date, timeZone: cal.timeZone)
    }

    public static func scheduledDate(
        forWeekday weekday: Int,
        relativeTo date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let mondayStr = mondayOfCurrentWeek(for: date, calendar: cal)
        guard let monday = parseDate(mondayStr) else { return formatDate(date) }
        let clampedDay = min(max(1, weekday), 7)
        if let target = cal.date(byAdding: .day, value: clampedDay - 1, to: monday) {
            return formatDate(target)
        }
        return mondayStr
    }

    public static func weekdays(state: StoredAppState) -> [Int] {
        guard let activeProg = state.programs.first(where: { $0.id == state.activeProgramId }) else { return [] }
        let days = activeProg.workouts.filter { !$0.exercises.isEmpty }.map { $0.day }.filter { $0 >= 1 && $0 <= 7 }
        return Array(Set(days)).sorted()
    }

    public static func sanitize(raw: WorkoutCalendarHistory?, today: String) -> WorkoutCalendarHistory? {
        guard let raw = raw else { return nil }
        guard let nextDate = parseDate(raw.nextScheduledDate) else { return nil }
        guard let todayDate = parseDate(today) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        guard let minDate = cal.date(byAdding: .year, value: -100, to: todayDate) else { return nil }
        let coercedDate = min(max(nextDate, minDate), todayDate)
        let nextStr = formatDate(coercedDate)

        let scheduled = Array(Set(raw.scheduledWeekdays.filter { $0 >= 1 && $0 <= 7 })).sorted()
        let missed = Array(Set(raw.missedDates.compactMap { parseDate($0) }
            .filter { $0 < todayDate }
            .map { formatDate($0) }))
            .sorted()
            .suffix(36_600)

        var seen = Set<String>()
        var validEntries: [WorkoutDayEntry] = []
        for entry in raw.entries {
            guard let _ = parseDate(entry.date) else { continue }
            let trimmedId = String(entry.id.prefix(240))
            guard !trimmedId.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if !seen.contains(trimmedId) {
                seen.insert(trimmedId)
                validEntries.append(WorkoutDayEntry(id: trimmedId, date: entry.date, status: entry.status))
            }
        }
        let cappedEntries = Array(validEntries.suffix(10_000))

        return WorkoutCalendarHistory(
            nextScheduledDate: nextStr,
            scheduledWeekdays: scheduled,
            missedDates: Array(missed),
            entries: cappedEntries
        )
    }

    static func snapshotLogIndices(exercises: [Exercise], logs: [SessionExerciseLog]) -> [Int?] {
        var used = Set<Int>()
        return exercises.enumerated().map { index, exercise in
            func matches(_ log: SessionExerciseLog) -> Bool {
                let key = PersonalRecordTracker.normalizeExerciseKey(log.exerciseName)
                return key == PersonalRecordTracker.normalizeExerciseKey(exercise.name)
                    || key == PersonalRecordTracker.normalizeExerciseKey(exercise.displayName)
            }
            // Captured logs follow snapshot row order, including repeated movements.
            let captured = logs.indices.contains(index) && !used.contains(index) && matches(logs[index]) ? index : nil
            let resolved = captured ?? logs.indices.first { !used.contains($0) && matches(logs[$0]) }
            if let resolved { used.insert(resolved) }
            return resolved
        }
    }

    public static func isSessionComplete(session: WorkoutSessionRecord, workout: Workout?) -> Bool {
        if session.isComplete == false { return false }
        let logs = session.exerciseLogs.map { log in
            var workingLog = log
            workingLog.sets = log.sets.filter { !$0.isWarmup }
            return workingLog
        }
        let planned = session.workoutSnapshot?.exercises ?? []
        if !planned.isEmpty {
            let indices = snapshotLogIndices(exercises: planned, logs: logs)
            guard planned.enumerated().allSatisfy({ index, exercise in
                let log = indices[index].map { logs[$0] }
                let target = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: exercise)
                return target > 0 && (log?.sets.count ?? 0) >= target
            }) else { return false }
            let used = Set(indices.compactMap { $0 })
            return logs.enumerated().filter { !used.contains($0.offset) }.allSatisfy { _, log in
                let target = log.targetSets ?? max(log.sets.count, 1)
                return target > 0 && log.sets.count >= target
            }
        }
        // A mutable plan is not evidence about a saved bout's prescription.
        guard !logs.isEmpty else { return session.isComplete == true }
        return logs.allSatisfy { log in
            let target = log.targetSets ?? max(log.sets.count, 1)
            return target > 0 && log.sets.count >= target
        }
    }

    /// Each entry ID's date, for lookups across all history. The first entry for an ID wins, as `first(where:)` finds it.
    static func entryDates(_ entries: [WorkoutDayEntry]) -> [String: String] {
        var dates: [String: String] = [:]
        for entry in entries where dates[entry.id] == nil { dates[entry.id] = entry.date }
        return dates
    }

    static func scheduledOriginsWithActivity(sessions: [WorkoutSessionRecord], entries: [WorkoutDayEntry], timeZone: TimeZone = .current) -> Set<String> {
        let performedDates = entryDates(entries)
        return Set(sessions.compactMap { session in
            guard let origin = session.scheduledDate, parseDate(origin, timeZone: timeZone) != nil,
                  let performed = performedDates["session:\(session.id)"]
                    ?? localDate(from: session.startedAt, timeZone: timeZone) ?? localDate(from: session.completedAt, timeZone: timeZone),
                  origin != performed,
                  session.totalCompletedSets > 0 || session.exerciseLogs.contains(where: { !$0.sets.isEmpty }) else { return nil }
            return origin
        })
    }

    private static func reconcileScheduledOrigins(missed: Set<String>, sessions: [WorkoutSessionRecord], entries: [WorkoutDayEntry], today: String, timeZone: TimeZone) -> Set<String> {
        let activeOrigins = scheduledOriginsWithActivity(sessions: sessions, entries: entries, timeZone: timeZone)
        var result = missed.subtracting(activeOrigins)
        let recordedDates = Set(entries.map(\.date))
        for session in sessions {
            guard let origin = session.scheduledDate, parseDate(origin, timeZone: timeZone) != nil,
                  origin < today, !activeOrigins.contains(origin), !recordedDates.contains(origin) else { continue }
            result.insert(origin)
        }
        return result
    }

    public static func restore(
        raw: WorkoutCalendarHistory?,
        sessions: [WorkoutSessionRecord],
        today: String,
        timeZone: TimeZone = .current,
        weekdays: [Int],
        activeSessionId: String? = nil,
        programs: [Program] = []
    ) -> WorkoutCalendarHistory {
        // A new schedule starts today: days before the plan existed cannot be missed.
        let history = sanitize(raw: raw, today: today)
            ?? WorkoutCalendarHistory(nextScheduledDate: today, scheduledWeekdays: weekdays)
        let sessionIds = Set(sessions.map { "session:\($0.id)" })
        let validActiveId = activeSessionId.map { "session:\($0)" }

        var entriesMap: [String: WorkoutDayEntry] = [:]
        for entry in history.entries {
            if entry.id.hasPrefix("session:") {
                if sessionIds.contains(entry.id) || entry.id == validActiveId {
                    entriesMap[entry.id] = entry
                }
            } else {
                entriesMap[entry.id] = entry
            }
        }
        for session in sessions {
            let id = "session:\(session.id)"
            // Preserve an explicit past-day assignment; otherwise use the actual
            // session date instead of moving it to the workout's usual weekday.
            let day = entriesMap[id]?.date
                ?? localDate(from: session.startedAt, timeZone: timeZone)
                ?? localDate(from: session.completedAt, timeZone: timeZone)
            if let d = day {
                let workout = programs.first(where: { $0.id == session.programId })?.workouts.first(where: { $0.id == session.workoutId })
                    ?? programs.flatMap(\.workouts).first(where: { $0.id == session.workoutId })
                let isComplete = isSessionComplete(session: session, workout: workout)
                let status: WorkoutDayStatus = isComplete ? .completed : .unfinished
                entriesMap[id] = WorkoutDayEntry(id: id, date: d, status: status)
            }
        }
        let entriesByDate = Set(entriesMap.values.map { $0.date })
        var missedSet = Set(history.missedDates).subtracting(entriesByDate)
        // Only refresh's saved schedule/cursor can establish missed days, as on Android. Recorded activity in a
        // week is not evidence that the plan existed on that week's earlier days.
        missedSet = reconcileScheduledOrigins(missed: missedSet, sessions: sessions,
            entries: Array(entriesMap.values), today: today, timeZone: timeZone)

        return WorkoutCalendarHistory(
            nextScheduledDate: history.nextScheduledDate,
            scheduledWeekdays: history.scheduledWeekdays,
            missedDates: missedSet.sorted(),
            entries: Array(entriesMap.values)
        )
    }

    public static func refresh(
        history: WorkoutCalendarHistory,
        today: String,
        weekdays: [Int],
        calendar: Calendar = Calendar(identifier: .gregorian),
        programs: [Program] = [],
        sessions: [WorkoutSessionRecord] = []
    ) -> WorkoutCalendarHistory {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let todayDate = parseDate(today) else { return history }
        guard let minDate = cal.date(byAdding: .year, value: -100, to: todayDate) else { return history }
        let startDate = parseDate(history.nextScheduledDate).map { max($0, minDate) } ?? todayDate

        let entriesByDate = Set(history.entries.map { $0.date })
        var missedSet = Set(history.missedDates).subtracting(entriesByDate)
        var cursor = startDate
        while cursor < todayDate {
            let weekday = (cal.component(.weekday, from: cursor) + 5) % 7 + 1 // 1=Mon..7=Sun
            let cursorStr = formatDate(cursor)
            if history.scheduledWeekdays.contains(weekday) && !entriesByDate.contains(cursorStr) {
                missedSet.insert(cursorStr)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        missedSet = reconcileScheduledOrigins(missed: missedSet, sessions: sessions,
            entries: history.entries, today: today, timeZone: cal.timeZone)

        return WorkoutCalendarHistory(
            nextScheduledDate: today,
            scheduledWeekdays: Array(Set(weekdays)).sorted(),
            missedDates: missedSet.sorted(),
            entries: history.entries
        )
    }

    public static func put(history: WorkoutCalendarHistory, entry: WorkoutDayEntry) -> WorkoutCalendarHistory {
        let filtered = history.entries.filter { $0.id != entry.id }
        let missedFiltered = history.missedDates.filter { $0 != entry.date }
        return WorkoutCalendarHistory(
            nextScheduledDate: history.nextScheduledDate,
            scheduledWeekdays: history.scheduledWeekdays,
            missedDates: missedFiltered,
            entries: filtered + [entry]
        )
    }

    public static func remove(history: WorkoutCalendarHistory, id: String) -> WorkoutCalendarHistory {
        let filtered = history.entries.filter { $0.id != id }
        return WorkoutCalendarHistory(
            nextScheduledDate: history.nextScheduledDate,
            scheduledWeekdays: history.scheduledWeekdays,
            missedDates: history.missedDates,
            entries: filtered
        )
    }

    public static func statuses(history: WorkoutCalendarHistory?, today: String) -> [String: WorkoutDayStatus] {
        guard let history = history else { return [:] }
        var result: [String: WorkoutDayStatus] = [:]
        for missed in history.missedDates {
            if missed < today {
                result[missed] = .missed
            }
        }
        for entry in history.entries {
            if entry.date <= today {
                let current = result[entry.date]
                if (current?.priority ?? -1) < entry.status.priority {
                    result[entry.date] = entry.status
                }
            }
        }
        return result
    }

    /// Weekday indices (0 = Monday) before `today` in its week that `statuses` mark missed.
    public static func missedWeekdays(statuses: [String: WorkoutDayStatus], today: Date,
                                      calendar: Calendar = Calendar(identifier: .gregorian)) -> Set<Int> {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let todayIndex = (cal.component(.weekday, from: today) + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -todayIndex, to: today) else { return [] }
        return Set((0..<todayIndex).filter { index in
            cal.date(byAdding: .day, value: index, to: monday)
                .map { statuses[formatDate($0, timeZone: cal.timeZone)] == .missed } ?? false
        })
    }

    public static func monthWeeks(for displayedMonthDate: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> [[Date?]] {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let monthInterval = cal.dateInterval(of: .month, for: displayedMonthDate) else { return [] }
        let firstDayOfMonth = monthInterval.start
        guard let range = cal.range(of: .day, in: .month, for: displayedMonthDate) else { return [] }
        let numberOfDaysInMonth = range.count

        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        let leadingEmpty = (weekday + 5) % 7 // 0 for Monday ... 6 for Sunday

        let totalCells = ((leadingEmpty + numberOfDaysInMonth + 6) / 7) * 7
        var cells: [Date?] = []
        for i in 0..<totalCells {
            let dayNumber = i - leadingEmpty + 1
            if dayNumber >= 1 && dayNumber <= numberOfDaysInMonth {
                if let d = cal.date(byAdding: .day, value: dayNumber - 1, to: firstDayOfMonth) {
                    cells.append(d)
                } else {
                    cells.append(nil)
                }
            } else {
                cells.append(nil)
            }
        }

        var weeks: [[Date?]] = []
        for chunk in stride(from: 0, to: cells.count, by: 7) {
            let end = min(chunk + 7, cells.count)
            weeks.append(Array(cells[chunk..<end]))
        }
        return weeks
    }

    public static func earliestWorkoutMonth(
        history: WorkoutCalendarHistory?,
        sessions: [WorkoutSessionRecord],
        timeZone: TimeZone = .current
    ) -> String? {
        var dates: [String] = []
        for session in sessions {
            if let d = localDate(from: session.startedAt, timeZone: timeZone) ?? localDate(from: session.completedAt, timeZone: timeZone) ?? session.scheduledDate {
                dates.append(d)
            }
        }
        if let history = history {
            for entry in history.entries {
                dates.append(entry.date)
            }
            for missed in history.missedDates {
                dates.append(missed)
            }
        }
        guard let earliest = dates.filter({ $0.count >= 7 }).min() else { return nil }
        return String(earliest.prefix(7))
    }
}


public struct StoredAppState: Codable {
    /// Matches Android's CURRENT_BACKUP_SCHEMA_VERSION; restore rejects newer backups. 6 adds the body log; 7 adds set effort (rir).
    public static let currentSchemaVersion = 7

    public var schemaVersion: Int
    public var programs: [Program]
    public var activeProgramId: String
    public var completed: [String]
    public var currentWeekKey: String
    public var weeklyArchives: [WeeklyArchive]
    public var history: [WorkoutSessionRecord]
    public var calendarHistory: WorkoutCalendarHistory?
    /// One entry per date (docs/design/body-and-joint-journal.md). Nil in schema 5 and older backups.
    public var bodyEntries: [BodyEntry]?
    /// Dates whose Apple Health weigh-in the user hid. Dates only: Health values are never stored.
    public var hiddenHealthWeighIns: [String]?

    public init(
        schemaVersion: Int = StoredAppState.currentSchemaVersion,
        programs: [Program] = [],
        activeProgramId: String = "",
        completed: [String] = [],
        currentWeekKey: String = "",
        weeklyArchives: [WeeklyArchive] = [],
        history: [WorkoutSessionRecord] = [],
        calendarHistory: WorkoutCalendarHistory? = nil,
        bodyEntries: [BodyEntry]? = nil,
        hiddenHealthWeighIns: [String]? = nil
    ) {
        self.bodyEntries = bodyEntries
        self.hiddenHealthWeighIns = hiddenHealthWeighIns
        self.schemaVersion = schemaVersion
        self.programs = programs
        self.activeProgramId = activeProgramId
        self.completed = completed
        self.currentWeekKey = currentWeekKey
        self.weeklyArchives = weeklyArchives
        self.history = history
        self.calendarHistory = calendarHistory
    }
}

public struct WeekCalendar {
    public var today: Int // 0 = Mon, ..., 6 = Sun
    public var numbers: [Int]
    /// Earlier days this week the Progress calendar records as missed. Days before the plan existed never are.
    public var missedDays: Set<Int>

    public init(today: Int, numbers: [Int], missedDays: Set<Int> = []) {
        self.today = today
        self.numbers = numbers
        self.missedDays = missedDays
    }
}

public struct ExerciseMetadata {

    private static let knownCableIds: Set<String> = [
        "lat-pulldown", "face-pull", "rope-triceps-pressdown",
        "straight-bar-cable-triceps-pressdown", "kneeling-cable-crunch",
        "pallof-press", "cable-seated-row", "cable-curl",
        "cable-lateral-raise", "overhead-cable-triceps-extension",
        "cable-pull-through", "cable-standing-fly", "cable-low-fly",
        "cable-decline-fly", "cable-middle-fly", "cable-woodchopper"
    ]

    public static func resolveMuscleKey(
        exerciseId: String?,
        name: String,
        movementType: MovementType?
    ) -> String {
        if let profile = ExerciseMuscleCatalog.shared?.profile(exerciseId),
           let primary = profile.primary.first {
            switch primary {
            case "chest": return "exercise.muscle.chest"
            case "lats", "upper-back", "lower-back": return "exercise.muscle.back"
            case "front-delts", "side-delts", "rear-delts": return "exercise.muscle.shoulders"
            case "biceps": return "exercise.muscle.biceps"
            case "forearms": return "exercise.muscle.forearms"
            case "hip-flexors": return "exercise.muscle.hip-flexors"
            case "hip-abductors": return "exercise.muscle.hip-abductors"
            case "serratus": return "exercise.muscle.serratus"
            case "rotator-cuff": return "exercise.muscle.rotator-cuff"
            case "neck": return "exercise.muscle.neck"
            case "deep-core": return "exercise.muscle.deep-core"
            case "triceps": return "exercise.muscle.triceps"
            case "quads": return "exercise.muscle.quads"
            case "adductors": return "exercise.muscle.adductors"
            case "hamstrings": return "exercise.muscle.hamstrings"
            case "glutes": return "exercise.muscle.glutes"
            case "calves": return "exercise.muscle.calves"
            case "tibialis": return "exercise.muscle.shins"
            case "abs", "obliques": return "exercise.muscle.core"
            default: return "exercise.muscle.full_body"
            }
        }

        let resolved = movementType ?? MovementType.fromExerciseName(name)
        let lowerName = name.lowercased()
        if let key = customNameMuscleKey(lowerName) { return key }
        switch resolved {
        case .press:
            if lowerName.contains("overhead") || lowerName.contains("shoulder") ||
                lowerName.contains("military") || lowerName.contains("arnold") ||
                lowerName.contains("viking") {
                return "exercise.muscle.shoulders"
            } else {
                return "exercise.muscle.chest"
            }
        case .pullUp, .row:
            return "exercise.muscle.back"
        case .shoulderRaise:
            return "exercise.muscle.shoulders"
        case .curl:
            return "exercise.muscle.biceps"
        case .triceps:
            return "exercise.muscle.triceps"
        case .squat, .lunge:
            return "exercise.muscle.quads"
        case .hinge:
            if lowerName.contains("glute") || lowerName.contains("thrust") || lowerName.contains("bridge") {
                return "exercise.muscle.glutes"
            } else {
                return "exercise.muscle.hamstrings"
            }
        case .calf:
            return "exercise.muscle.calves"
        case .core:
            return "exercise.muscle.core"
        case .conditioning, .boxing:
            return "exercise.muscle.cardio"
        case .other:
            if lowerName.contains("chest") || lowerName.contains("bench") || lowerName.contains("push-up") {
                return "exercise.muscle.chest"
            } else if lowerName.range(of: #"\blats?\b"#, options: .regularExpression) != nil ||
                        lowerName.contains("pull") || lowerName.contains("row") {
                return "exercise.muscle.back"
            } else if lowerName.contains("shoulder") || lowerName.contains("delt") {
                return "exercise.muscle.shoulders"
            } else if lowerName.contains("squat") || lowerName.contains("quad") || lowerName.contains("leg extension") {
                return "exercise.muscle.quads"
            } else if lowerName.contains("deadlift") || lowerName.contains("rdl") || lowerName.contains("hamstring") {
                return "exercise.muscle.hamstrings"
            } else if lowerName.contains("calf") {
                return "exercise.muscle.calves"
            } else if lowerName.contains("curl") {
                return "exercise.muscle.biceps"
            } else if lowerName.contains("tricep") || lowerName.contains("dip") {
                return "exercise.muscle.triceps"
            } else if lowerName.contains("abs") || lowerName.contains("crunch") || lowerName.contains("plank") {
                return "exercise.muscle.core"
            } else {
                return "exercise.muscle.full_body"
            }
        }
    }

    /// Specific exercise names outrank the coarse movement type (a leg curl is not a biceps curl).
    private static func customNameMuscleKey(_ lowerName: String) -> String? {
        func has(_ terms: String...) -> Bool { terms.contains { lowerName.contains($0) } }
        if has("behind neck press", "behind-the-neck press") { return "exercise.muscle.shoulders" }
        if has("hip flexor", "iliopsoas", "psoas") { return "exercise.muscle.hip-flexors" }
        if has("hip abduction", "hip abductor", "glute med", "glute min") { return "exercise.muscle.hip-abductors" }
        if has("serratus", "scapular push") { return "exercise.muscle.serratus" }
        if has("rotator cuff", "shoulder external rotation", "shoulder internal rotation") { return "exercise.muscle.rotator-cuff" }
        if has("neck flexion", "neck extension", "neck curl", "neck bridge", "neck harness", "neck rotation", "neck isometric", "cervical flexion", "cervical extension") { return "exercise.muscle.neck" }
        if has("transversus", "multifidus", "quadratus lumborum", "deep core") { return "exercise.muscle.deep-core" }
        if has("reverse hyper") { return "exercise.muscle.glutes" }
        if has("back extension", "hyperextension") { return "exercise.muscle.back" }
        if has("calf") { return "exercise.muscle.calves" }
        if has("tibialis", "shin raise", "shins") { return "exercise.muscle.shins" }
        if has("adductor", "adduction") { return "exercise.muscle.adductors" }
        if has("wrist", "forearm", "reverse curl") { return "exercise.muscle.forearms" }
        if has("leg curl", "hamstring curl", "nordic", "glute-ham", "glute ham", "good morning") {
            return "exercise.muscle.hamstrings"
        }
        if has("leg press", "hack squat") { return "exercise.muscle.quads" }
        if has("hip thrust", "glute bridge", "pull-through", "pull through", "glute kickback",
               "kettlebell swing") {
            return "exercise.muscle.glutes"
        }
        if has("upright row", "face pull", "lateral raise", "front raise", "rear delt", "reverse fly", "rear fly") {
            return "exercise.muscle.shoulders"
        }
        if has("pec deck", " fly", "flye") || lowerName.hasPrefix("fly") { return "exercise.muscle.chest" }
        if has("pushdown", "pressdown", "skull crusher") { return "exercise.muscle.triceps" }
        if has("shrug") { return "exercise.muscle.back" }
        if has("russian twist", "woodchop", "dead bug", "ab wheel", "rollout", "sit-up", "sit up", "hollow", "pallof") {
            return "exercise.muscle.core"
        }
        return nil
    }

    public static func resolveEquipmentKey(
        exerciseId: String?,
        name: String,
        searchKeywords: [String] = []
    ) -> String {
        let lowerId = (exerciseId ?? "").lowercased()
        let lowerName = name.lowercased()

        // 1. Cable check
        let isCable = knownCableIds.contains(lowerId) ||
            lowerId.contains("cable") ||
            lowerName.contains("cable") ||
            searchKeywords.contains { $0.caseInsensitiveCompare("cable") == .orderedSame || $0.caseInsensitiveCompare("pulley") == .orderedSame }
        if isCable { return "exercise.equipment.cable" }

        // 2. Equipment Catalog check
        let eqCat = EquipmentCatalog.shared.categoryId(exerciseId)
        switch eqCat {
        case "bar": return "exercise.equipment.barbell"
        case "dumbbell": return "exercise.equipment.dumbbell"
        case "kettlebell": return "exercise.equipment.kettlebell"
        case "resistance-band": return "exercise.equipment.band"
        case "weight-plate": return "exercise.equipment.plate"
        case "machine": return "exercise.equipment.machine"
        case "other":
            if lowerId == "jump-rope" || lowerName.contains("jump rope") { return "exercise.equipment.rope" }
            if lowerId == "ab-wheel-rollout" || lowerName.contains("ab wheel") { return "exercise.equipment.ab_wheel" }
            if exerciseId != nil && EquipmentCatalog.shared.exercises[exerciseId!] != nil {
                return "exercise.equipment.bodyweight"
            }
        default:
            break
        }

        // 3. Fallback heuristics
        if lowerName.contains("barbell") || lowerName.contains("ez-bar") { return "exercise.equipment.barbell" }
        if lowerName.contains("dumbbell") || lowerName.contains(" db ") { return "exercise.equipment.dumbbell" }
        if lowerName.contains("kettlebell") || lowerName.contains(" kb ") { return "exercise.equipment.kettlebell" }
        if lowerName.contains("band") { return "exercise.equipment.band" }
        if lowerName.contains("plate") { return "exercise.equipment.plate" }
        if lowerName.contains("machine") || lowerName.contains("lever") || lowerName.contains("sled") || lowerName.contains("smith") { return "exercise.equipment.machine" }
        if lowerName.contains("jump rope") { return "exercise.equipment.rope" }
        if lowerName.contains("ab wheel") { return "exercise.equipment.ab_wheel" }
        return "exercise.equipment.bodyweight"
    }

    public static func format(_ exercise: Exercise) -> String {
        let muscleKey = resolveMuscleKey(
            exerciseId: exercise.exerciseId,
            name: exercise.name,
            movementType: exercise.resolvedMovement
        )
        let equipmentKey = resolveEquipmentKey(
            exerciseId: exercise.exerciseId,
            name: exercise.name,
            searchKeywords: []
        )
        let muscle = LanguageManager.t(muscleKey)
        let equipment = LanguageManager.t(equipmentKey)
        return "\(muscle) · \(equipment)"
    }

    public static func format(
        exerciseId: String?,
        name: String,
        movementType: MovementType?,
        searchKeywords: [String] = []
    ) -> String {
        let muscleKey = resolveMuscleKey(
            exerciseId: exerciseId,
            name: name,
            movementType: movementType
        )
        let equipmentKey = resolveEquipmentKey(
            exerciseId: exerciseId,
            name: name,
            searchKeywords: searchKeywords
        )
        let muscle = LanguageManager.t(muscleKey)
        let equipment = LanguageManager.t(equipmentKey)
        return "\(muscle) · \(equipment)"
    }

    public static func matchesMuscle(
        exercise: Exercise,
        muscleKey: String?
    ) -> Bool {
        guard let muscleKey else { return true }
        return muscleMatchRank(exercise: exercise, muscleKey: muscleKey) != nil
    }

    /// 0 when the filter names a primary target, 1 for supporting work, nil when it does not match.
    public static func muscleMatchRank(exercise: Exercise, muscleKey: String) -> Int? {
        if muscleKey == "cardio" {
            let mov = exercise.resolvedMovement
            if mov == .conditioning || mov == .boxing { return 0 }
            let lowerName = exercise.name.lowercased()
            let lowerId = (exercise.exerciseId ?? "").lowercased()
            let cardio = lowerId.contains("jump-rope") || lowerId.contains("burpee") ||
                   lowerName.contains("jump rope") || lowerName.contains("sprint") ||
                   lowerName.contains("burpee") || lowerName.range(of: #"\brun(?:ning)?\b"#, options: .regularExpression) != nil ||
                   lowerName.contains("cardio") || lowerName.contains("box jump") ||
                   lowerName.contains("battle rope") || lowerName.contains("jumping jack") ||
                   lowerName.contains("mountain climber")
            return cardio ? 0 : nil
        }
        let muscleMap: [String: [String]] = [
            "chest": ["chest"],
            "back": ["lats", "upper-back", "lower-back"],
            "shoulders": ["front-delts", "side-delts", "rear-delts"],
            "biceps": ["biceps"],
            "triceps": ["triceps"],
            "forearms": ["forearms"],
            "quads": ["quads"],
            "adductors": ["adductors"],
            "hamstrings": ["hamstrings"],
            // Glutes is the broad group for its hip-abductor refinement, so it covers both.
            "glutes": ["glutes", "hip-abductors"],
            "calves": ["calves"],
            "shins": ["tibialis"],
            "core": ["abs", "obliques", "deep-core"],
            "front-delts": ["front-delts"],
            "side-delts": ["side-delts"],
            "rear-delts": ["rear-delts"],
            "upper-back": ["upper-back"],
            "lats": ["lats"],
            "lower-back": ["lower-back"],
            "abs": ["abs"],
            "obliques": ["obliques"],
            "hip-flexors": ["hip-flexors"],
            "hip-abductors": ["hip-abductors"],
            "serratus": ["serratus"],
            "rotator-cuff": ["rotator-cuff"],
            "neck": ["neck"],
            "deep-core": ["deep-core"]
        ]
        let targetMuscles = muscleMap[muscleKey] ?? [muscleKey]
        if let profile = ExerciseMuscleCatalog.shared?.profile(exercise.exerciseId) {
            if profile.primary.contains(where: { targetMuscles.contains($0) }) { return 0 }
            if profile.secondary.contains(where: { targetMuscles.contains($0) }) { return 1 }
        }
        // Custom and uncurated exercises carry one inferred label, treated as their main target.
        let fallbackKey = resolveMuscleKey(exerciseId: exercise.exerciseId, name: exercise.name, movementType: exercise.resolvedMovement)
        guard let fallbackFilter = MuscleGroupFilter.allCases.first(where: { $0.translationKey == fallbackKey }) else { return nil }
        if fallbackFilter.rawValue == muscleKey { return 0 }
        // A narrower inferred label (deep core, hip abductors) still belongs to its broad group.
        guard let fallbackMuscles = muscleMap[fallbackFilter.rawValue] else { return nil }
        return fallbackMuscles.allSatisfy { targetMuscles.contains($0) } ? 0 : nil
    }
}

public enum MuscleGroupFilter: String, CaseIterable, Identifiable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case forearms = "forearms"
    case quads = "quads"
    case adductors = "adductors"
    case hamstrings = "hamstrings"
    case glutes = "glutes"
    case calves = "calves"
    case shins = "shins"
    case core = "core"
    case frontDelts = "front-delts"
    case sideDelts = "side-delts"
    case rearDelts = "rear-delts"
    case upperBack = "upper-back"
    case lats = "lats"
    case lowerBack = "lower-back"
    case abs = "abs"
    case obliques = "obliques"
    case hipFlexors = "hip-flexors"
    case hipAbductors = "hip-abductors"
    case serratus = "serratus"
    case rotatorCuff = "rotator-cuff"
    case neck = "neck"
    case deepCore = "deep-core"
    case cardio = "cardio"

    public var id: String { rawValue }

    public var translationKey: String {
        return "exercise.muscle.\(rawValue)"
    }

    public var bodyView: BodyView {
        switch self {
        case .chest, .shoulders, .biceps, .forearms, .core, .cardio, .frontDelts, .sideDelts, .abs, .obliques, .serratus, .deepCore, .neck:
            return .front
        case .back, .triceps, .rearDelts, .upperBack, .lats, .lowerBack, .rotatorCuff:
            return .back
        case .quads, .adductors, .shins, .hipFlexors:
            return .legsFront
        case .hamstrings, .glutes, .calves, .hipAbductors:
            return .legsBack
        }
    }

    public var muscleGroups: [MuscleGroup] {
        switch self {
        case .chest: return [.chest]
        case .back: return [.lats, .upperBack, .lowerBack]
        case .shoulders: return [.shoulders]
        case .biceps: return [.biceps]
        case .triceps: return [.triceps]
        case .forearms: return [.forearms]
        case .quads: return [.quadriceps]
        case .adductors: return [.adductors]
        case .hamstrings: return [.hamstrings]
        case .glutes: return [.glutes, .hipAbductors]
        case .calves: return [.calves]
        case .shins: return [.tibialis]
        case .core: return [.abs, .obliques, .deepCore]
        case .frontDelts: return [.frontDelts]
        case .sideDelts: return [.sideDelts]
        case .rearDelts: return [.rearDelts]
        case .upperBack: return [.upperBack]
        case .lats: return [.lats]
        case .lowerBack: return [.lowerBack]
        case .abs: return [.abs]
        case .obliques: return [.obliques]
        case .hipFlexors: return [.hipFlexors]
        case .hipAbductors: return [.hipAbductors]
        case .serratus: return [.serratus]
        case .rotatorCuff: return [.rotatorCuff]
        case .neck: return [.neck]
        case .deepCore: return [.deepCore]
        case .cardio: return []
        }
    }

    /// Library modal tiles in display order. Regions without main-target exercises stay search-only.
    public static let libraryTiles: [MuscleGroupFilter] = [
        .chest, .back, .shoulders, .biceps, .triceps, .forearms, .core, .cardio,
        .quads, .hamstrings, .glutes, .calves, .adductors
    ]

    /// Narrower regions offered as chips once their broad group is the active filter.
    public static let refinements: [MuscleGroupFilter: [MuscleGroupFilter]] = [
        .back: [.lats, .upperBack, .lowerBack],
        .shoulders: [.frontDelts, .sideDelts, .rearDelts],
        .core: [.abs, .obliques],
        .glutes: [.hipAbductors]
    ]

    /// The broad group a filter belongs to: itself for a broad group, its parent for a refinement.
    public static func family(of filter: MuscleGroupFilter?) -> MuscleGroupFilter? {
        guard let filter else { return nil }
        return refinements.first(where: { $0.value.contains(filter) })?.key ?? filter
    }
}
