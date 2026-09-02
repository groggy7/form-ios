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

public enum BodyView: String, Codable {
    case back = "back"
    case front = "front"
    case legsFront = "legs-front"
    case legsBack = "legs-back"
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
    case hamstrings = "hamstrings"
    case calves = "calves"
    case glutes = "glutes"

    public var views: [BodyView] {
        switch self {
        case .chest, .abs, .obliques, .biceps:
            return [.front]
        case .triceps, .trapezius, .lats, .lowerBack:
            return [.back]
        case .shoulders:
            return [.back, .front]
        case .forearms:
            return [.front, .back]
        case .quadriceps:
            return [.legsFront]
        case .hamstrings, .calves, .glutes:
            return [.legsBack]
        }
    }

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

public struct Exercise: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var prescription: String
    public var cues: String
    public var avoid: String
    public var videos: [String]
    public var sets: Int?
    public var reps: RepTarget?
    public var restSeconds: Int?
    public var movementType: String?
    public var movementAssetId: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        prescription: String = "",
        cues: String = "",
        avoid: String = "",
        videos: [String] = [],
        sets: Int? = nil,
        reps: RepTarget? = nil,
        restSeconds: Int? = nil,
        movementType: String? = nil,
        movementAssetId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prescription = prescription
        self.cues = cues
        self.avoid = avoid
        self.videos = videos
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.movementType = movementType
        self.movementAssetId = movementAssetId
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

    enum CodingKeys: String, CodingKey {
        case id, name, prescription, cues, avoid, videos, sets, reps, restSeconds, movementType, movementAssetId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.prescription = try container.decodeIfPresent(String.self, forKey: .prescription) ?? ""
        
        if let cuesStr = try? container.decode(String.self, forKey: .cues) {
            self.cues = cuesStr
        } else if let cuesArr = try? container.decode([String].self, forKey: .cues) {
            self.cues = cuesArr.joined(separator: "\n")
        } else {
            self.cues = ""
        }

        if let avoidStr = try? container.decode(String.self, forKey: .avoid) {
            self.avoid = avoidStr
        } else if let avoidArr = try? container.decode([String].self, forKey: .avoid) {
            self.avoid = avoidArr.joined(separator: "\n")
        } else {
            self.avoid = ""
        }

        self.videos = try container.decodeIfPresent([String].self, forKey: .videos) ?? []
        self.sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        self.reps = try container.decodeIfPresent(RepTarget.self, forKey: .reps)
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.movementType = try container.decodeIfPresent(String.self, forKey: .movementType)
        self.movementAssetId = try container.decodeIfPresent(String.self, forKey: .movementAssetId)
    }
}

public struct Workout: Identifiable, Codable, Hashable {
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
        targetMuscles.compactMap(MuscleGroup.fromKey).reduce(into: [MuscleGroup]()) { acc, m in
            if !acc.contains(m) { acc.append(m) }
        }
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

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        guidelines: [String] = [],
        workouts: [Workout] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.guidelines = guidelines
        self.workouts = workouts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, guidelines, workouts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.guidelines = try container.decodeIfPresent([String].self, forKey: .guidelines) ?? []
        self.workouts = try container.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
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

    public init(
        id: String = UUID().uuidString,
        setNumber: Int,
        weightInput: String = "",
        repsInput: String = "",
        weightKg: Double? = nil,
        completedReps: Int? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightInput = weightInput
        self.repsInput = repsInput
        self.weightKg = weightKg
        self.completedReps = completedReps
        self.isCompleted = isCompleted
    }
}

public struct SessionSetLog: Codable, Hashable {
    public var setNumber: Int
    public var weightKg: Double?
    public var reps: Int?

    public init(setNumber: Int, weightKg: Double? = nil, reps: Int? = nil) {
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
    }
}

public struct SessionExerciseLog: Codable, Hashable {
    public var exerciseName: String
    public var sets: [SessionSetLog]

    public init(exerciseName: String, sets: [SessionSetLog] = []) {
        self.exerciseName = exerciseName
        self.sets = sets
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
        isComplete: Bool? = nil
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
    }
}

public struct RestTimerState: Codable, Hashable {
    public var exerciseName: String
    public var totalSeconds: Int
    public var isRunning: Bool
    public var endsAtEpochMillis: Int64?
    public var pausedSecondsRemaining: Int

    public init(
        exerciseName: String,
        totalSeconds: Int,
        isRunning: Bool,
        endsAtEpochMillis: Int64? = nil,
        pausedSecondsRemaining: Int = 0
    ) {
        self.exerciseName = exerciseName
        self.totalSeconds = totalSeconds
        self.isRunning = isRunning
        self.endsAtEpochMillis = endsAtEpochMillis
        self.pausedSecondsRemaining = pausedSecondsRemaining
    }

    public func secondsRemaining(nowEpochMillis: Int64) -> Int {
        if !isRunning {
            return max(0, pausedSecondsRemaining)
        }
        guard let end = endsAtEpochMillis else { return 0 }
        let diff = end - nowEpochMillis
        return max(0, Int((diff + 999) / 1000))
    }
}

public struct ActiveSessionDraft: Identifiable, Codable, Hashable {
    public var schemaVersion: Int
    public var id: String
    public var programId: String
    public var workout: Workout
    public var startedAt: String
    public var startedAtEpochMillis: Int64
    public var currentExerciseIndex: Int
    public var setsByExercise: [String: [ExerciseSetLog]]
    public var restTimer: RestTimerState?

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        programId: String,
        workout: Workout,
        startedAt: String,
        startedAtEpochMillis: Int64,
        currentExerciseIndex: Int = 0,
        setsByExercise: [String: [ExerciseSetLog]] = [:],
        restTimer: RestTimerState? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.programId = programId
        self.workout = workout
        self.startedAt = startedAt
        self.startedAtEpochMillis = startedAtEpochMillis
        self.currentExerciseIndex = currentExerciseIndex
        self.setsByExercise = setsByExercise
        self.restTimer = restTimer
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

public enum WorkoutDayStatus: String, Codable {
    case missed = "MISSED"
    case unfinished = "UNFINISHED"
    case completed = "COMPLETED"
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

public struct StoredAppState: Codable {
    public var schemaVersion: Int
    public var programs: [Program]
    public var activeProgramId: String
    public var completed: [String]
    public var currentWeekKey: String
    public var weeklyArchives: [WeeklyArchive]
    public var history: [WorkoutSessionRecord]
    public var calendarHistory: WorkoutCalendarHistory?

    public init(
        schemaVersion: Int = 4,
        programs: [Program] = [],
        activeProgramId: String = "",
        completed: [String] = [],
        currentWeekKey: String = "",
        weeklyArchives: [WeeklyArchive] = [],
        history: [WorkoutSessionRecord] = [],
        calendarHistory: WorkoutCalendarHistory? = nil
    ) {
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

    public init(today: Int, numbers: [Int]) {
        self.today = today
        self.numbers = numbers
    }
}
