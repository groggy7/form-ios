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

    public init(
        id: String = UUID().uuidString,
        name: String,
        exerciseId: String? = nil,
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
        self.exerciseId = exerciseId
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

    public var metadataSubtitle: String {
        ExerciseMetadata.format(self)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, exerciseId, prescription, cues, avoid, videos, sets, reps, restSeconds, movementType, movementAssetId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        let exId = try container.decodeIfPresent(String.self, forKey: .exerciseId)
        self.exerciseId = exId
        let def = exId.flatMap { ExerciseCatalog.canonicalExercises[$0] }
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        self.name = decodedName ?? def?.name ?? ""
        self.prescription = try container.decodeIfPresent(String.self, forKey: .prescription) ?? ""
        
        if let cuesStr = try? container.decode(String.self, forKey: .cues) {
            self.cues = cuesStr
        } else if let cuesArr = try? container.decode([String].self, forKey: .cues) {
            self.cues = cuesArr.joined(separator: "\n")
        } else {
            self.cues = def?.cues.joined(separator: "\n") ?? ""
        }

        if let avoidStr = try? container.decode(String.self, forKey: .avoid) {
            self.avoid = avoidStr
        } else if let avoidArr = try? container.decode([String].self, forKey: .avoid) {
            self.avoid = avoidArr.joined(separator: "\n")
        } else {
            self.avoid = def?.avoid.joined(separator: "\n") ?? ""
        }

        self.videos = try container.decodeIfPresent([String].self, forKey: .videos) ?? []
        self.sets = try container.decodeIfPresent(Int.self, forKey: .sets)
        self.reps = try container.decodeIfPresent(RepTarget.self, forKey: .reps)
        self.restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds)
        self.movementType = try container.decodeIfPresent(String.self, forKey: .movementType) ?? def?.movementType
        self.movementAssetId = try container.decodeIfPresent(String.self, forKey: .movementAssetId) ?? def?.movementAssetId
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
    public var inputTouched: Bool?

    public init(
        id: String = UUID().uuidString,
        setNumber: Int,
        weightInput: String = "",
        repsInput: String = "",
        weightKg: Double? = nil,
        completedReps: Int? = nil,
        isCompleted: Bool = false,
        inputTouched: Bool? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightInput = weightInput
        self.repsInput = repsInput
        self.weightKg = weightKg
        self.completedReps = completedReps
        self.isCompleted = isCompleted
        self.inputTouched = inputTouched
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
    public var targetSets: Int?

    public init(exerciseName: String, sets: [SessionSetLog] = [], targetSets: Int? = nil) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.targetSets = targetSets
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
    public static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f.string(from: date)
    }

    public static func parseDate(_ string: String, timeZone: TimeZone = .current) -> Date? {
        guard string.count == 10 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f.date(from: string)
    }

    public static func parseIsoTimestamp(_ timestamp: String?) -> Date? {
        guard let ts = timestamp, !ts.isEmpty else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: ts) {
            return d
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: ts)
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
            return formatDate(monday)
        }
        return formatDate(date)
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

    public static func restore(
        raw: WorkoutCalendarHistory?,
        sessions: [WorkoutSessionRecord],
        today: String,
        timeZone: TimeZone = .current,
        weekdays: [Int],
        activeSessionId: String? = nil,
        programs: [Program] = []
    ) -> WorkoutCalendarHistory {
        let history = sanitize(raw: raw, today: today)
            ?? WorkoutCalendarHistory(nextScheduledDate: mondayOfCurrentWeek(for: parseDate(today) ?? Date()), scheduledWeekdays: weekdays)
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
        let cal = Calendar(identifier: .gregorian)
        for session in sessions {
            let id = "session:\(session.id)"
            let workoutDay = programs.first(where: { $0.id == session.programId })?.workouts.first(where: { $0.id == session.workoutId })?.day
            let sessionDate = parseIsoTimestamp(session.startedAt) ?? parseIsoTimestamp(session.completedAt)
            let scheduled: String? = {
                guard let day = workoutDay, let date = sessionDate else { return nil }
                return scheduledDate(forWeekday: day, relativeTo: date, calendar: cal)
            }()
            let day = scheduled
                ?? entriesMap[id]?.date
                ?? localDate(from: session.startedAt, timeZone: timeZone)
                ?? localDate(from: session.completedAt, timeZone: timeZone)
            if let d = day {
                let status: WorkoutDayStatus = (session.isComplete == false) ? .unfinished : .completed
                entriesMap[id] = WorkoutDayEntry(id: id, date: d, status: status)
            }
        }
        return WorkoutCalendarHistory(
            nextScheduledDate: history.nextScheduledDate,
            scheduledWeekdays: history.scheduledWeekdays,
            missedDates: history.missedDates,
            entries: Array(entriesMap.values)
        )
    }

    public static func refresh(
        history: WorkoutCalendarHistory,
        today: String,
        weekdays: [Int],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WorkoutCalendarHistory {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        guard let todayDate = parseDate(today) else { return history }
        guard let minDate = cal.date(byAdding: .year, value: -100, to: todayDate) else { return history }
        let startDate = parseDate(history.nextScheduledDate).map { max($0, minDate) } ?? todayDate

        var missedSet = Set(history.missedDates)
        var cursor = startDate
        while cursor < todayDate {
            let weekday = (cal.component(.weekday, from: cursor) + 5) % 7 + 1 // 1=Mon..7=Sun
            let cursorStr = formatDate(cursor)
            if history.scheduledWeekdays.contains(weekday) {
                missedSet.insert(cursorStr)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return WorkoutCalendarHistory(
            nextScheduledDate: today,
            scheduledWeekdays: Array(Set(weekdays)).sorted(),
            missedDates: missedSet.sorted(),
            entries: history.entries
        )
    }

    public static func put(history: WorkoutCalendarHistory, entry: WorkoutDayEntry) -> WorkoutCalendarHistory {
        let filtered = history.entries.filter { $0.id != entry.id }
        return WorkoutCalendarHistory(
            nextScheduledDate: history.nextScheduledDate,
            scheduledWeekdays: history.scheduledWeekdays,
            missedDates: history.missedDates,
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
            case "lats", "upper-back": return "exercise.muscle.back"
            case "front-delts", "rear-delts": return "exercise.muscle.shoulders"
            case "biceps": return "exercise.muscle.biceps"
            case "triceps": return "exercise.muscle.triceps"
            case "quads": return "exercise.muscle.quads"
            case "hamstrings": return "exercise.muscle.hamstrings"
            case "glutes": return "exercise.muscle.glutes"
            case "calves": return "exercise.muscle.calves"
            case "abs", "obliques": return "exercise.muscle.core"
            default: return "exercise.muscle.full_body"
            }
        }

        let resolved = movementType ?? MovementType.fromExerciseName(name)
        let lowerName = name.lowercased()
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
            } else if lowerName.contains("lat") || lowerName.contains("pull") || lowerName.contains("row") {
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
        guard let muscleKey = muscleKey else { return true }
        let muscleMap: [String: [String]] = [
            "chest": ["chest"],
            "back": ["lats", "upper-back"],
            "shoulders": ["front-delts", "rear-delts"],
            "biceps": ["biceps"],
            "triceps": ["triceps"],
            "quads": ["quads"],
            "hamstrings": ["hamstrings"],
            "glutes": ["glutes"],
            "calves": ["calves"],
            "core": ["abs", "obliques"]
        ]
        let targetMuscles = muscleMap[muscleKey] ?? [muscleKey]
        if let profile = ExerciseMuscleCatalog.shared?.profile(exercise.exerciseId),
           profile.primary.contains(where: { targetMuscles.contains($0) }) {
            return true
        }
        let fallbackKey = resolveMuscleKey(exerciseId: exercise.exerciseId, name: exercise.name, movementType: exercise.resolvedMovement)
        switch muscleKey {
        case "chest": return fallbackKey == "exercise.muscle.chest"
        case "back": return fallbackKey == "exercise.muscle.back"
        case "shoulders": return fallbackKey == "exercise.muscle.shoulders"
        case "biceps": return fallbackKey == "exercise.muscle.biceps"
        case "triceps": return fallbackKey == "exercise.muscle.triceps"
        case "quads": return fallbackKey == "exercise.muscle.quads"
        case "hamstrings": return fallbackKey == "exercise.muscle.hamstrings"
        case "glutes": return fallbackKey == "exercise.muscle.glutes"
        case "calves": return fallbackKey == "exercise.muscle.calves"
        case "core": return fallbackKey == "exercise.muscle.core"
        default: return false
        }
    }
}

public enum MuscleGroupFilter: String, CaseIterable, Identifiable {
    case chest = "chest"
    case back = "back"
    case shoulders = "shoulders"
    case biceps = "biceps"
    case triceps = "triceps"
    case quads = "quads"
    case hamstrings = "hamstrings"
    case glutes = "glutes"
    case calves = "calves"
    case core = "core"

    public var id: String { rawValue }

    public var translationKey: String {
        return "exercise.muscle.\(rawValue)"
    }
}

