import Foundation
import Combine

public final class AppStore: ObservableObject {
    public static let shared = AppStore()

    private let stateKey = "stored_app_state"
    private let activeSessionKey = "active_session_v1"
    private let soundKey = "sound_enabled"
    private let defaultRestKey = "default_rest_seconds"

    @Published public var state: StoredAppState
    @Published public var activeSession: ActiveSessionDraft?
    @Published public var currentView: ViewMode = .today
    @Published public var soundEnabled: Bool
    @Published public var defaultRestSeconds: Int
    @Published public var noticeMessage: String?
    @Published public var exerciseCatalogue: [ExerciseCatalogEntry] = []
    
    // Navigation selection
    @Published public var selectedWorkoutId: String?

    private var cancellables = Set<AnyCancellable>()

    public init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        self.defaultRestSeconds = UserDefaults.standard.object(forKey: defaultRestKey) as? Int ?? 90

        let loadedState = Self.loadStoredState()
        self.state = loadedState
        self.activeSession = Self.loadActiveSession()
        self.selectedWorkoutId = loadedState.programs.first { $0.id == loadedState.activeProgramId }?.workouts.first?.id

        // Auto-archive stale session if from previous day or > 12 hours old
        self.checkAndArchiveStaleSession()
        self.refreshCatalogue()

        // Sync sound preferences
        $soundEnabled
            .sink { UserDefaults.standard.set($0, forKey: self.soundKey) }
            .store(in: &cancellables)

        $defaultRestSeconds
            .sink { UserDefaults.standard.set($0, forKey: self.defaultRestKey) }
            .store(in: &cancellables)
    }

    public var activeProgram: Program? {
        state.programs.first { $0.id == state.activeProgramId } ?? state.programs.first
    }

    public var activeWorkout: Workout? {
        guard let program = activeProgram else { return nil }
        if let id = selectedWorkoutId, let w = program.workouts.first(where: { $0.id == id }) {
            return w
        }
        let todayDay = currentWeekDayNumber() // 1 = Mon, ..., 7 = Sun
        return program.workouts.first(where: { $0.day == todayDay }) ?? program.workouts.first
    }

    public var weekCalendar: WeekCalendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // Convert to 0 = Mon, ..., 6 = Sun
        let todayIndex = (weekday + 5) % 7

        // Get 7 dates for the current week starting from Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let monday = calendar.date(from: components) else {
            return WeekCalendar(today: todayIndex, numbers: (1...7).map { $0 })
        }

        var numbers: [Int] = []
        for i in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: i, to: monday) {
                numbers.append(calendar.component(.day, from: day))
            } else {
                numbers.append(i + 1)
            }
        }
        return WeekCalendar(today: todayIndex, numbers: numbers)
    }

    public func currentWeekDayNumber() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let weekday = calendar.component(.weekday, from: Date())
        return (weekday + 5) % 7 + 1 // 1 = Mon, ..., 7 = Sun
    }

    public func canStartWorkout(_ workout: Workout) -> Bool {
        return workout.day <= currentWeekDayNumber()
    }

    public func unfinishedWorkoutKeys() -> Set<String> {
        guard let program = activeProgram else { return [] }
        let currentWeek = currentWeekIsoKey()
        let fromHistory = state.history.filter { record in
            record.programId == program.id &&
            record.isComplete == false &&
            recordWeekIsoKey(record) == currentWeek
        }.map { "\($0.programId):\($0.workoutId)" }

        var fromActive: Set<String> = []
        if let active = activeSession, active.programId == program.id {
            let hasSets = active.setsByExercise.values.flatMap { $0 }.contains {
                $0.isCompleted || !$0.weightInput.isEmpty || !$0.repsInput.isEmpty
            }
            if hasSets {
                fromActive.insert("\(active.programId):\(active.workout.id)")
            }
        }
        return Set(fromHistory + fromActive)
    }

    // MARK: - Active Session

    public func startActiveSession(programId: String, workout: Workout) -> Bool {
        if activeSession != nil || workout.exercises.isEmpty || !canStartWorkout(workout) {
            return false
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let currentWeek = currentWeekIsoKey()
        let unfinishedRecord = state.history.first { r in
            r.programId == programId &&
            r.workoutId == workout.id &&
            r.isComplete == false &&
            recordWeekIsoKey(r) == currentWeek
        }

        let setsByExercise = unfinishedRecord != nil
            ? WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: unfinishedRecord!)
            : WorkoutSessionUtils.initialSets(for: workout)
        let initialIndex = unfinishedRecord != nil
            ? WorkoutSessionUtils.firstIncompleteExerciseIndex(workout: workout, setsByExercise: setsByExercise)
            : 0

        let previousDuration = unfinishedRecord?.durationSeconds ?? 0
        let clampedPrevSecs = min(max(0, previousDuration), 4 * 3600)
        let startedAtEpoch = now - Int64(clampedPrevSecs * 1000)

        let formatter = ISO8601DateFormatter()
        let startedAtTimestamp = formatter.string(from: Date(timeIntervalSince1970: Double(startedAtEpoch) / 1000.0))

        let draft = ActiveSessionDraft(
            id: unfinishedRecord?.id ?? UUID().uuidString,
            programId: programId,
            workout: workout,
            startedAt: startedAtTimestamp,
            startedAtEpochMillis: startedAtEpoch,
            currentExerciseIndex: initialIndex,
            setsByExercise: setsByExercise
        )

        saveActiveSession(draft)
        self.activeSession = draft
        FormAudioPlayer.playWorkoutStartSound()
        return true
    }

    public func updateActiveSession(_ transform: (ActiveSessionDraft) -> ActiveSessionDraft) {
        guard let current = activeSession else { return }
        let updated = transform(current)
        saveActiveSession(updated)
        self.activeSession = updated
    }

    public func abandonActiveSession() {
        saveActiveSession(nil)
        self.activeSession = nil
    }

    public func completeActiveSession(_ record: WorkoutSessionRecord) {
        let isComplete = activeSession.map(WorkoutSessionUtils.isComplete) ?? (record.isComplete ?? true)
        let finalRecord = WorkoutSessionRecord(
            id: record.id,
            programId: record.programId,
            workoutId: record.workoutId,
            workoutTitle: record.workoutTitle,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            durationSeconds: record.durationSeconds,
            totalVolumeKg: record.totalVolumeKg,
            totalCompletedSets: record.totalCompletedSets,
            exerciseLogs: record.exerciseLogs,
            isComplete: isComplete
        )

        var newHistory = state.history
        newHistory.insert(finalRecord, at: 0)

        var newCompleted = state.completed
        let key = "\(finalRecord.programId):\(finalRecord.workoutId)"
        if isComplete && !newCompleted.contains(key) {
            newCompleted.append(key)
        }

        var newState = state
        newState.history = newHistory
        newState.completed = newCompleted
        saveState(newState)
        abandonActiveSession()

        showNotice(LanguageManager.t("notice.workoutRecorded", [
            "sets": finalRecord.totalCompletedSets,
            "volume": Int(finalRecord.totalVolumeKg)
        ]))
    }

    // MARK: - Program Management

    public func switchProgram(to programId: String) {
        guard let prog = state.programs.first(where: { $0.id == programId }) else { return }
        var newState = state
        newState.activeProgramId = prog.id
        saveState(newState)
        selectedWorkoutId = prog.workouts.first?.id
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programApplied", ["name": prog.name]))
    }

    public func addProgram(_ program: Program) {
        var newState = state
        newState.programs.append(program)
        newState.activeProgramId = program.id
        saveState(newState)
        selectedWorkoutId = program.workouts.first?.id
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programApplied", ["name": program.name]))
    }

    public func updateProgram(_ program: Program) {
        var newState = state
        if let idx = newState.programs.firstIndex(where: { $0.id == program.id }) {
            newState.programs[idx] = program
            saveState(newState)
            refreshCatalogue()
        }
    }

    public func deleteProgram(withId id: String) {
        guard state.programs.count > 1 else { return }
        var newState = state
        newState.programs.removeAll { $0.id == id }
        if newState.activeProgramId == id {
            newState.activeProgramId = newState.programs.first?.id ?? ""
        }
        saveState(newState)
        refreshCatalogue()
    }

    public func importProgram(jsonData: Data) throws -> Program {
        let decoder = JSONDecoder()
        let program = try decoder.decode(Program.self, from: jsonData)
        addProgram(program)
        return program
    }

    public func showNotice(_ message: String) {
        self.noticeMessage = message
    }

    // MARK: - Internal Helpers & Persistence

    private func refreshCatalogue() {
        let bundled = Self.loadBundledStarterPrograms()
        self.exerciseCatalogue = ExerciseCatalog.build(
            bundledPrograms: bundled,
            userPrograms: state.programs,
            preferredProgramId: activeProgram?.id,
            preferredWorkout: activeWorkout
        )
    }

    private func checkAndArchiveStaleSession() {
        guard let draft = activeSession else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let isStale = (now - draft.startedAtEpochMillis) > 12 * 3600 * 1000
        if isStale {
            let hasCompleted = draft.setsByExercise.values.flatMap { $0 }.contains { $0.isCompleted }
            if hasCompleted {
                let rec = SessionProgress.from(draft: draft, nowEpochMillis: draft.startedAtEpochMillis + 30 * 60 * 1000)
                    .record(draft: draft, completedAtEpochMillis: draft.startedAtEpochMillis + 30 * 60 * 1000)
                completeActiveSession(rec)
            } else {
                abandonActiveSession()
            }
        }
    }

    private func saveState(_ newState: StoredAppState) {
        self.state = newState
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(newState)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            print("Failed to save state: \(error)")
        }
    }

    private func saveActiveSession(_ draft: ActiveSessionDraft?) {
        if let draft = draft {
            do {
                let data = try JSONEncoder().encode(draft)
                UserDefaults.standard.set(data, forKey: activeSessionKey)
            } catch {
                print("Failed to save active session: \(error)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: activeSessionKey)
        }
    }

    private static func loadActiveSession() -> ActiveSessionDraft? {
        guard let data = UserDefaults.standard.data(forKey: "active_session_v1") else { return nil }
        return try? JSONDecoder().decode(ActiveSessionDraft.self, from: data)
    }

    private static func loadStoredState() -> StoredAppState {
        if let data = UserDefaults.standard.data(forKey: "stored_app_state"),
           let stored = try? JSONDecoder().decode(StoredAppState.self, from: data) {
            return stored
        }
        let bundled = loadBundledStarterPrograms()
        let activeId = bundled.first?.id ?? UUID().uuidString
        let initial = StoredAppState(
            schemaVersion: 4,
            programs: bundled,
            activeProgramId: activeId,
            completed: [],
            currentWeekKey: currentWeekIsoKeyStatic(),
            weeklyArchives: [],
            history: [],
            calendarHistory: nil
        )
        return initial
    }

    public static func loadBundledStarterPrograms() -> [Program] {
        let programNames = [
            "01_aesthetic_hypertrophy",
            "02_powerbuilding_strength",
            "03_classic_ppl",
            "04_full_body_classic",
            "05_home_forge_dumbbells",
            "06_athletic_performance"
        ]

        var programs: [Program] = []
        let decoder = JSONDecoder()

        for name in programNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "json") ??
                         Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "StarterPrograms") {
                if let data = try? Data(contentsOf: url),
                   let prog = try? decoder.decode(Program.self, from: data) {
                    programs.append(prog)
                }
            }
        }
        return programs
    }

    private func currentWeekIsoKey() -> String {
        Self.currentWeekIsoKeyStatic()
    }

    private static func currentWeekIsoKeyStatic() -> String {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date()
        let year = calendar.component(.yearForWeekOfYear, from: now)
        let week = calendar.component(.weekOfYear, from: now)
        return String(format: "%04d-W%02d", year, week)
    }

    private func recordWeekIsoKey(_ record: WorkoutSessionRecord) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: record.completedAt) ?? formatter.date(from: record.startedAt) else {
            return ""
        }
        let calendar = Calendar(identifier: .iso8601)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
}

public struct ExerciseCatalogEntry: Identifiable, Hashable {
    public var id: String { key }
    public var key: String
    public var exercise: Exercise
    public var programIds: Set<String>
    public var workoutKeys: Set<String>

    public init(key: String, exercise: Exercise, programIds: Set<String>, workoutKeys: Set<String>) {
        self.key = key
        self.exercise = exercise
        self.programIds = programIds
        self.workoutKeys = workoutKeys
    }
}

public enum ExerciseCatalog {
    public static func build(
        bundledPrograms: [Program],
        userPrograms: [Program],
        preferredProgramId: String? = nil,
        preferredWorkout: Workout? = nil
    ) -> [ExerciseCatalogEntry] {
        struct Source {
            let programId: String
            let workoutId: String
            let exercise: Exercise
        }

        var sources: [Source] = []
        if let prefId = preferredProgramId, let prefW = preferredWorkout {
            sources.append(contentsOf: prefW.exercises.map { Source(programId: prefId, workoutId: prefW.id, exercise: $0) })
        }

        for prog in (userPrograms + bundledPrograms) {
            for w in prog.workouts {
                sources.append(contentsOf: w.exercises.map { Source(programId: prog.id, workoutId: w.id, exercise: $0) })
            }
        }

        var map: [String: ExerciseCatalogEntry] = [:]
        for s in sources {
            let key = s.exercise.name.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty { continue }
            let occ = "\(s.programId)\u{0}\(s.workoutId)"
            if let existing = map[key] {
                let merged = merge(primary: existing.exercise, fallback: s.exercise)
                map[key] = ExerciseCatalogEntry(
                    key: key,
                    exercise: merged,
                    programIds: existing.programIds.union([s.programId]),
                    workoutKeys: existing.workoutKeys.union([occ])
                )
            } else {
                map[key] = ExerciseCatalogEntry(
                    key: key,
                    exercise: s.exercise,
                    programIds: [s.programId],
                    workoutKeys: [occ]
                )
            }
        }
        return map.values.sorted { $0.exercise.name.localizedCaseInsensitiveCompare($1.exercise.name) == .orderedAscending }
    }

    private static func merge(primary: Exercise, fallback: Exercise) -> Exercise {
        var merged = primary
        if merged.cues.trimmingCharacters(in: .whitespaces).isEmpty { merged.cues = fallback.cues }
        if merged.avoid.trimmingCharacters(in: .whitespaces).isEmpty { merged.avoid = fallback.avoid }
        if merged.videos.isEmpty { merged.videos = fallback.videos }
        if merged.sets == nil { merged.sets = fallback.sets }
        if merged.reps == nil { merged.reps = fallback.reps }
        if merged.restSeconds == nil { merged.restSeconds = fallback.restSeconds }
        if merged.movementType == nil { merged.movementType = fallback.movementType }
        if merged.movementAssetId == nil { merged.movementAssetId = fallback.movementAssetId }
        return merged
    }
}
