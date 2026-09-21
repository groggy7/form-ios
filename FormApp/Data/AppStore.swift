import Foundation
import Combine

public final class AppStore: ObservableObject {
    public static let shared = AppStore()

    private let stateKey = "stored_app_state"
    private let activeSessionKey = "active_session_v1"
    private let soundKey = "sound_enabled"
    private let defaultRestKey = "default_rest_seconds"
    private let prefillNextSetKey = "prefill_next_set"
    private let weightUnitKey = "weight_unit"
    private let barTypeKey = "bar_type"
    private let availablePlatesKey = "available_plates_kg"
    private let onboardingCompletedKey = "is_onboarding_completed"
    private let progressionCardDismissedKey = "pro_progression_card_dismissed"
    private let warmupCardDismissedKey = "pro_warmup_card_dismissed"

    @Published public var state: StoredAppState
    @Published public var activeSession: ActiveSessionDraft?
    @Published public var isOnboardingCompleted: Bool
    @Published public var isProgressionCardDismissed: Bool
    @Published public var isWarmupCardDismissed: Bool
    @Published public var currentView: ViewMode = .today {
        didSet {
            if currentView != .library {
                selectedExerciseId = nil
                returnView = nil
            }
        }
    }
    @Published public var soundEnabled: Bool
    @Published public var defaultRestSeconds: Int
    @Published public var prefillNextSet: Bool
    @Published public var weightUnit: WeightUnit
    @Published public var barType: BarType
    @Published public var availablePlatesKg: [Double]
    @Published public var noticeMessage: String?
    @Published public var exerciseCatalogue: [ExerciseCatalogEntry] = []
    
    // Navigation selection
    @Published public var selectedWorkoutId: String?
    @Published public var selectedExerciseId: String?
    @Published public var selectedHistoryDetailDay: String?
    @Published public var returnView: ViewMode?

    public func openExercise(id: String) {
        self.returnView = currentView
        self.selectedExerciseId = id
        self.currentView = .library
    }

    public func selectExerciseInLibrary(id: String?) {
        self.selectedExerciseId = id
        if id == nil {
            if let target = returnView {
                self.returnView = nil
                self.currentView = target
            }
        }
    }

    public func navigate(to view: ViewMode) {
        self.selectedExerciseId = nil
        self.selectedHistoryDetailDay = nil
        self.returnView = nil
        self.currentView = view
    }

    public func findExercise(id: String) -> Exercise? {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let found = exerciseCatalogue.first(where: {
            $0.key == cleanId ||
            $0.exercise.id == id ||
            $0.exercise.exerciseId == id ||
            $0.exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanId
        })?.exercise {
            return found
        }
        for program in state.programs {
            for workout in program.workouts {
                if let found = workout.exercises.first(where: {
                    $0.id == id ||
                    $0.exerciseId == id ||
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == cleanId
                }) {
                    return found
                }
            }
        }
        return nil
    }

    private var cancellables = Set<AnyCancellable>()

    public init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        self.defaultRestSeconds = UserDefaults.standard.object(forKey: defaultRestKey) as? Int ?? 90
        self.prefillNextSet = UserDefaults.standard.object(forKey: prefillNextSetKey) as? Bool ?? true
        if let savedUnitCode = UserDefaults.standard.string(forKey: weightUnitKey) {
            self.weightUnit = WeightUnit.fromCode(savedUnitCode)
        } else {
            self.weightUnit = WeightUnit.defaultForLocale()
        }
        if let savedBarKey = UserDefaults.standard.string(forKey: barTypeKey) {
            self.barType = BarType.fromKey(savedBarKey)
        } else {
            self.barType = .olympic20
        }
        if let savedPlates = UserDefaults.standard.array(forKey: availablePlatesKey) as? [Double] {
            self.availablePlatesKg = savedPlates
        } else {
            self.availablePlatesKg = WarmupPlateEngine.defaultPlatesKg
        }
        self.isProgressionCardDismissed = UserDefaults.standard.bool(forKey: progressionCardDismissedKey)
        self.isWarmupCardDismissed = UserDefaults.standard.bool(forKey: warmupCardDismissedKey)

        var loadedState = Self.loadStoredState()

        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        let hasExistingData = UserDefaults.standard.object(forKey: stateKey) != nil || UserDefaults.standard.object(forKey: activeSessionKey) != nil || !loadedState.history.isEmpty
        if !hasCompleted && hasExistingData {
            UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
            self.isOnboardingCompleted = true
        } else {
            self.isOnboardingCompleted = hasCompleted
        }
        let todayStr = WorkoutCalendar.formatDate(Date())
        let weekdays = WorkoutCalendar.weekdays(state: loadedState)
        let activeDraft = Self.loadActiveSession()
        let restored = WorkoutCalendar.restore(
            raw: loadedState.calendarHistory,
            sessions: loadedState.history,
            today: todayStr,
            weekdays: weekdays,
            activeSessionId: activeDraft?.id,
            programs: loadedState.programs
        )
        let refreshed = WorkoutCalendar.refresh(
            history: restored,
            today: todayStr,
            weekdays: weekdays
        )
        loadedState.calendarHistory = refreshed
        self.state = loadedState
        self.activeSession = activeDraft
        self.selectedWorkoutId = loadedState.programs.first { $0.id == loadedState.activeProgramId }?.workouts.first?.id

        // Auto-archive stale session if from previous day or > 12 hours old
        self.checkAndArchiveStaleSession()
        self.refreshCatalogue()
        self.saveState(self.state)

        // Sync sound preferences
        $soundEnabled
            .sink { UserDefaults.standard.set($0, forKey: self.soundKey) }
            .store(in: &cancellables)

        $defaultRestSeconds
            .sink { UserDefaults.standard.set($0, forKey: self.defaultRestKey) }
            .store(in: &cancellables)

        $prefillNextSet
            .sink { UserDefaults.standard.set($0, forKey: self.prefillNextSetKey) }
            .store(in: &cancellables)

        $weightUnit
            .sink { UserDefaults.standard.set($0.rawValue, forKey: self.weightUnitKey) }
            .store(in: &cancellables)

        $barType
            .sink { UserDefaults.standard.set($0.key, forKey: self.barTypeKey) }
            .store(in: &cancellables)

        $availablePlatesKg
            .sink { UserDefaults.standard.set($0, forKey: self.availablePlatesKey) }
            .store(in: &cancellables)

        $isOnboardingCompleted
            .sink { UserDefaults.standard.set($0, forKey: self.onboardingCompletedKey) }
            .store(in: &cancellables)

        $isProgressionCardDismissed
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: self.progressionCardDismissedKey) }
            .store(in: &cancellables)

        $isWarmupCardDismissed
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: self.warmupCardDismissedKey) }
            .store(in: &cancellables)
    }

    public func resetDismissedProCards() {
        isProgressionCardDismissed = false
        isWarmupCardDismissed = false
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

    public func canStartWorkout(_ workout: Workout, allowPast: Bool = false) -> Bool {
        return allowPast || workout.day <= currentWeekDayNumber()
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

    public func startActiveSession(
        programId: String,
        workout: Workout,
        allowPast: Bool = false,
        unfinishedRecordId: String? = nil
    ) -> Bool {
        checkAndArchiveStaleSession()
        if activeSession != nil || workout.exercises.isEmpty || !canStartWorkout(workout, allowPast: allowPast) {
            return false
        }
        let now = Date()
        let currentWeek = currentWeekIsoKey()
        let unfinishedRecord = (unfinishedRecordId.flatMap { recId in
            state.history.first { $0.id == recId }
        }) ?? state.history.first { r in
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

        let sessionDay = (unfinishedRecord?.id).flatMap { recId in
            state.calendarHistory?.entries.first(where: { $0.id == "session:\(recId)" })?.date
        } ?? WorkoutCalendar.scheduledDate(forWeekday: workout.day, relativeTo: now)

        let startedAtDate = now.addingTimeInterval(-Double(clampedPrevSecs))
        let startedAtEpoch = Int64(startedAtDate.timeIntervalSince1970 * 1000)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startedAtTimestamp = formatter.string(from: startedAtDate)

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

        var curCal = state.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(for: now),
            scheduledWeekdays: WorkoutCalendar.weekdays(state: state)
        )
        curCal = WorkoutCalendar.put(
            history: curCal,
            entry: WorkoutDayEntry(id: "session:\(draft.id)", date: sessionDay, status: .unfinished)
        )
        var nextSt = state
        nextSt.calendarHistory = curCal
        saveState(nextSt)

        FormAudioPlayer.playWorkoutStartSound()
        return true
    }

    public func updateActiveSession(_ transform: (ActiveSessionDraft) -> ActiveSessionDraft) {
        guard let current = activeSession else { return }
        var updated = transform(current)
        updated.lastActivityEpochMillis = Int64(Date().timeIntervalSince1970 * 1000)
        saveActiveSession(updated)
        self.activeSession = updated

        let allSets = updated.setsByExercise.values.flatMap { $0 }
        let hasCompleted = allSets.contains { $0.isCompleted }
        if var cal = state.calendarHistory {
            let sessionDate: String = {
                if let d = cal.entries.first(where: { $0.id == "session:\(updated.id)" })?.date {
                    return d
                }
                return WorkoutCalendar.localDate(from: updated.startedAt) ?? WorkoutCalendar.formatDate(Date())
            }()
            let updatedCal: WorkoutCalendarHistory
            if hasCompleted {
                updatedCal = WorkoutCalendar.put(
                    history: cal,
                    entry: WorkoutDayEntry(id: "session:\(updated.id)", date: sessionDate, status: .unfinished)
                )
            } else {
                updatedCal = WorkoutCalendar.remove(history: cal, id: "session:\(updated.id)")
            }
            var nextSt = state
            nextSt.calendarHistory = updatedCal
            saveState(nextSt)
        }
    }

    public func setBarType(_ type: BarType) {
        self.barType = type
    }

    public func setAvailablePlatesKg(_ plates: [Double]) {
        self.availablePlatesKg = plates
    }

    public func insertWarmupSets(exerciseId: String, warmupSets: [ExerciseSetLog]) {
        updateActiveSession { d in
            var copy = d
            let sets = copy.setsByExercise[exerciseId] ?? []
            let workingSets = sets.filter { !$0.isWarmup }
            let completedWarmups = sets.filter { $0.isWarmup && $0.isCompleted }
            let newWarmups = completedWarmups.isEmpty ? warmupSets : (completedWarmups + warmupSets.dropFirst(completedWarmups.count))
            let combined = newWarmups + workingSets
            copy.setsByExercise[exerciseId] = Self.reindexSets(combined)
            return copy
        }
    }

    public func clearWarmupSets(exerciseId: String) {
        updateActiveSession { d in
            var copy = d
            let sets = copy.setsByExercise[exerciseId] ?? []
            let remaining = sets.filter { !$0.isWarmup || $0.isCompleted }
            copy.setsByExercise[exerciseId] = Self.reindexSets(remaining)
            return copy
        }
    }

    public func toggleWarmup(exerciseId: String, index: Int) {
        updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            guard sets.indices.contains(index) else { return copy }
            var set = sets[index]
            set.isWarmup.toggle()
            sets[index] = set
            copy.setsByExercise[exerciseId] = Self.reindexSets(sets)
            return copy
        }
    }

    public static func reindexSets(_ sets: [ExerciseSetLog]) -> [ExerciseSetLog] {
        let warmups = sets.filter { $0.isWarmup }.enumerated().map { idx, s in
            ExerciseSetLog(
                id: s.id,
                setNumber: idx + 1,
                weightInput: s.weightInput,
                repsInput: s.repsInput,
                weightKg: s.weightKg,
                completedReps: s.completedReps,
                isCompleted: s.isCompleted,
                inputTouched: s.inputTouched,
                isWarmup: true
            )
        }
        let working = sets.filter { !$0.isWarmup }.enumerated().map { idx, s in
            ExerciseSetLog(
                id: s.id,
                setNumber: idx + 1,
                weightInput: s.weightInput,
                repsInput: s.repsInput,
                weightKg: s.weightKg,
                completedReps: s.completedReps,
                isCompleted: s.isCompleted,
                inputTouched: s.inputTouched,
                isWarmup: false
            )
        }
        return warmups + working
    }

    public func abandonActiveSession() {
        if let draft = activeSession {
            let allSets = draft.setsByExercise.values.flatMap { $0 }
            let hasCompleted = allSets.contains { $0.isCompleted }
            if hasCompleted {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let rec = SessionProgress.from(draft: draft, nowEpochMillis: now)
                    .record(draft: draft, completedAtEpochMillis: now)
                completeActiveSession(rec)
                return
            } else {
                if var cal = state.calendarHistory {
                    cal = WorkoutCalendar.remove(history: cal, id: "session:\(draft.id)")
                    var nextSt = state
                    nextSt.calendarHistory = cal
                    saveState(nextSt)
                }
            }
        }
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
        newHistory.removeAll { $0.id == finalRecord.id }
        newHistory.insert(finalRecord, at: 0)

        var newCompleted = state.completed
        let key = "\(finalRecord.programId):\(finalRecord.workoutId)"
        if isComplete && !newCompleted.contains(key) {
            newCompleted.append(key)
        }

        var cal = state.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(),
            scheduledWeekdays: WorkoutCalendar.weekdays(state: state)
        )
        if let draft = activeSession {
            cal = WorkoutCalendar.remove(history: cal, id: "session:\(draft.id)")
        }
        let draftEntryDate = activeSession.flatMap { draft in
            state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })?.date
        }
        let recordEntryDate = state.calendarHistory?.entries.first(where: { $0.id == "session:\(finalRecord.id)" })?.date
        let draftWorkoutDay = activeSession?.workout.day
        let recordWorkoutDay = state.programs.first(where: { $0.id == finalRecord.programId })?.workouts.first(where: { $0.id == finalRecord.workoutId })?.day
            ?? activeProgram?.workouts.first(where: { $0.id == finalRecord.workoutId })?.day
            ?? state.programs.flatMap(\.workouts).first(where: { $0.id == finalRecord.workoutId })?.day
        let targetWeekday = draftWorkoutDay ?? recordWorkoutDay

        let sessionDate: String
        if let d = draftEntryDate {
            sessionDate = d
        } else if let d = recordEntryDate {
            sessionDate = d
        } else if let day = targetWeekday {
            sessionDate = WorkoutCalendar.scheduledDate(forWeekday: day, relativeTo: Date())
        } else if let d = WorkoutCalendar.localDate(from: finalRecord.startedAt) {
            sessionDate = d
        } else if let d = WorkoutCalendar.localDate(from: finalRecord.completedAt) {
            sessionDate = d
        } else {
            sessionDate = WorkoutCalendar.formatDate(Date())
        }

        let hasSets = finalRecord.totalCompletedSets > 0 || finalRecord.exerciseLogs.contains { log in
            log.sets.contains { ($0.reps ?? 0) > 0 || ($0.weightKg ?? 0) > 0 }
        }
        let sessionDateParsed = WorkoutCalendar.parseDate(sessionDate)
        let todayDate = WorkoutCalendar.parseDate(WorkoutCalendar.formatDate(Date())) ?? Date()
        let isPast = (sessionDateParsed.map { $0 < todayDate }) ?? false

        let entryStatus: WorkoutDayStatus?
        if isComplete {
            entryStatus = .completed
        } else if hasSets {
            entryStatus = .unfinished
        } else if isPast {
            entryStatus = .missed
        } else {
            entryStatus = nil
        }

        if let s = entryStatus {
            cal = WorkoutCalendar.put(
                history: cal,
                entry: WorkoutDayEntry(
                    id: "session:\(finalRecord.id)",
                    date: sessionDate,
                    status: s
                )
            )
        } else {
            cal = WorkoutCalendar.remove(history: cal, id: "session:\(finalRecord.id)")
        }

        var newState = state
        newState.history = newHistory
        newState.completed = newCompleted
        newState.calendarHistory = cal
        saveState(newState)
        
        saveActiveSession(nil)
        self.activeSession = nil

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
        newState = refreshCalendarState(newState)
        saveState(newState)
        selectedWorkoutId = prog.workouts.first?.id
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programApplied", ["name": prog.name]))
    }

    public func addProgram(_ program: Program) {
        var newState = state
        newState.programs.append(program)
        newState.activeProgramId = program.id
        newState = refreshCalendarState(newState)
        saveState(newState)
        selectedWorkoutId = program.workouts.first?.id
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programApplied", ["name": program.name]))
    }

    public func updateProgram(_ program: Program) {
        var newState = state
        if let idx = newState.programs.firstIndex(where: { $0.id == program.id }) {
            newState.programs[idx] = program
            newState = refreshCalendarState(newState)
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
        newState = refreshCalendarState(newState)
        saveState(newState)
        refreshCatalogue()
    }

    public func completeOnboarding(preferences: OnboardingPreferences, targetProgramId: String? = nil) {
        let rec = OnboardingRecommender.recommendProgram(preferences: preferences, availablePrograms: state.programs)
        let chosenProgramId = targetProgramId ?? rec.targetProgramId
        let currentProg = state.programs.first(where: { $0.id == chosenProgramId }) ?? activeProgram ?? state.programs[0]

        let updatedWorkouts = currentProg.workouts.enumerated().map { index, workout -> Workout in
            let newDay = index < rec.scheduledWeekdays.count ? rec.scheduledWeekdays[index] : workout.day
            return Workout(
                id: workout.id,
                day: newDay,
                title: workout.title,
                focus: workout.focus,
                tone: workout.tone,
                exercises: workout.exercises,
                targetMuscles: workout.targetMuscles
            )
        }
        let updatedProg = Program(
            id: currentProg.id,
            name: currentProg.name,
            description: currentProg.description,
            guidelines: currentProg.guidelines,
            workouts: updatedWorkouts
        )
        var newState = state
        if let idx = newState.programs.firstIndex(where: { $0.id == updatedProg.id }) {
            newState.programs[idx] = updatedProg
        }
        newState.activeProgramId = updatedProg.id
        newState = refreshCalendarState(newState)
        saveState(newState)
        selectedWorkoutId = updatedProg.workouts.first?.id
        setOnboardingCompleted(true)
        refreshCatalogue()
    }

    public func setOnboardingCompleted(_ completed: Bool) {
        UserDefaults.standard.set(completed, forKey: onboardingCompletedKey)
        isOnboardingCompleted = completed
    }

    public func resetOnboarding() {
        setOnboardingCompleted(false)
    }

    public func calendarStatuses(today: Date = Date()) -> [String: WorkoutDayStatus] {
        let todayStr = WorkoutCalendar.formatDate(today)
        let curCal = state.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(for: today),
            scheduledWeekdays: WorkoutCalendar.weekdays(state: state)
        )
        let refreshed = WorkoutCalendar.refresh(
            history: curCal,
            today: todayStr,
            weekdays: WorkoutCalendar.weekdays(state: state)
        )
        var statuses = WorkoutCalendar.statuses(history: refreshed, today: todayStr)

        func hasLoggedSets(for dateStr: String) -> Bool {
            if let active = activeSession {
                let activeDate = curCal.entries.first(where: { $0.id == "session:\(active.id)" })?.date
                    ?? WorkoutCalendar.localDate(from: active.startedAt) ?? todayStr
                if activeDate == dateStr {
                    let allSets = active.setsByExercise.values.flatMap { $0 }
                    if allSets.contains(where: { $0.isCompleted }) { return true }
                }
            }
            return state.history.contains { rec in
                let calDate = state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date
                let d = calDate ?? WorkoutCalendar.localDate(from: rec.startedAt) ?? WorkoutCalendar.localDate(from: rec.completedAt)
                guard d == dateStr else { return false }
                if rec.totalCompletedSets > 0 { return true }
                return rec.exerciseLogs.contains { log in
                    log.sets.contains { ($0.reps ?? 0) > 0 || ($0.weightKg ?? 0) > 0 }
                }
            }
        }

        if let active = activeSession {
            let allSets = active.setsByExercise.values.flatMap { $0 }
            if allSets.contains(where: { $0.isCompleted }) {
                let activeDate = WorkoutCalendar.localDate(from: active.startedAt) ?? todayStr
                if (statuses[activeDate]?.priority ?? -1) < WorkoutDayStatus.unfinished.priority {
                    statuses[activeDate] = .unfinished
                }
            }
        }

        // 1. Today with no logged sets -> neutral (no status)
        if statuses[todayStr] == .unfinished && !hasLoggedSets(for: todayStr) {
            statuses.removeValue(forKey: todayStr)
        }

        // 2. Passed days with no logged sets -> red (.missed)
        for (dateStr, status) in statuses {
            if dateStr < todayStr && status == .unfinished && !hasLoggedSets(for: dateStr) {
                statuses[dateStr] = .missed
            }
        }

        return statuses
    }

    private func refreshCalendarState(_ st: StoredAppState) -> StoredAppState {
        let weekdays = WorkoutCalendar.weekdays(state: st)
        let today = Date()
        let todayStr = WorkoutCalendar.formatDate(today)
        let curCal = st.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(for: today),
            scheduledWeekdays: weekdays
        )
        let refreshed = WorkoutCalendar.refresh(history: curCal, today: todayStr, weekdays: weekdays)
        var copy = st
        copy.calendarHistory = refreshed
        return copy
    }

    public struct ProgramFileEnvelope: Codable {
        public var format: String?
        public var schemaVersion: Int?
        public var program: Program
    }

    public static func decodeProgram(from data: Data) throws -> Program {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ProgramFileEnvelope.self, from: data) {
            return envelope.program
        }
        return try decoder.decode(Program.self, from: data)
    }

    public func importProgram(jsonData: Data) throws -> Program {
        let program = try Self.decodeProgram(from: jsonData)
        addProgram(program)
        return program
    }

    public func setExerciseVideos(exerciseName: String, videoUrls: [String]) {
        let key = exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
        if key.isEmpty { return }

        guard let cleanUrls = YouTubeVideo.validatedLinks(videoUrls) else {
            noticeMessage = LanguageManager.t("video.youtubeOnly")
            return
        }

        var matched = false
        var updatedPrograms = state.programs.map { program in
            var prog = program
            prog.workouts = program.workouts.map { workout in
                var w = workout
                w.exercises = workout.exercises.map { existing in
                    if existing.name.trimmingCharacters(in: .whitespaces).lowercased() == key {
                        matched = true
                        var updated = existing
                        updated.videos = cleanUrls
                        return updated
                    }
                    return existing
                }
                return w
            }
            return prog
        }

        if !matched {
            let targetProgramIndex = updatedPrograms.firstIndex { $0.id == state.activeProgramId } ?? (updatedPrograms.isEmpty ? nil : 0)
            if let pIdx = targetProgramIndex, !updatedPrograms[pIdx].workouts.isEmpty {
                let newEx = Exercise(name: exerciseName.trimmingCharacters(in: .whitespaces), videos: cleanUrls)
                updatedPrograms[pIdx].workouts[0].exercises.append(newEx)
            }
        }

        var newState = state
        newState.programs = updatedPrograms
        saveState(newState)
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.videosUpdated", ["name": exerciseName]))
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
            preferredWorkout: activeWorkout,
            canonicalExercises: Array(ExerciseCatalog.canonicalExercises.values)
        )
    }

    @discardableResult
    public func checkAndArchiveStaleSession() -> Bool {
        guard let draft = activeSession else { return false }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let startedDate = WorkoutCalendar.localDate(from: draft.startedAt) ?? WorkoutCalendar.formatDate(Date())
        let todayStr = WorkoutCalendar.formatDate(Date())
        let lastActivity = draft.lastActivityEpochMillis > 0 ? draft.lastActivityEpochMillis : draft.startedAtEpochMillis

        let isStartedOnPreviousDay = startedDate < todayStr && (now - lastActivity) > (2 * 3600 * 1000)
        let isInactive = (now - lastActivity) > (4 * 3600 * 1000)
        let isOverMaxDuration = (now - draft.startedAtEpochMillis) > (6 * 3600 * 1000)

        let isStale = isStartedOnPreviousDay || isInactive || isOverMaxDuration
        guard isStale else { return false }

        let allSets = draft.setsByExercise.values.flatMap { $0 }
        let hasCompleted = allSets.contains { $0.isCompleted }
        if hasCompleted {
            let elapsedActivitySeconds = Int((lastActivity - draft.startedAtEpochMillis) / 1000)
            let effectiveDurationSeconds = elapsedActivitySeconds >= 60 ? min(max(60, elapsedActivitySeconds), 4 * 3600) : (30 * 60)
            let effectiveCompletionMillis = draft.startedAtEpochMillis + Int64(effectiveDurationSeconds * 1000)
            var rec = SessionProgress.from(draft: draft, nowEpochMillis: effectiveCompletionMillis)
                .record(draft: draft, completedAtEpochMillis: effectiveCompletionMillis)
            rec.isComplete = false
            rec.durationSeconds = effectiveDurationSeconds
            completeActiveSession(rec)
        } else {
            abandonActiveSession()
        }
        return true
    }

    func saveState(_ newState: StoredAppState) {
        self.state = newState
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(newState)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            print("Failed to save state: \(error)")
        }
    }

    public func exportBackupJson() -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(state)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    @discardableResult
    public func restoreBackupJson(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        do {
            let decoder = JSONDecoder()
            let decodedState = try decoder.decode(StoredAppState.self, from: data)
            saveState(decodedState)
            return true
        } catch {
            print("Failed to restore backup: \(error)")
            return false
        }
    }

    public func previewHistoryImport(csvText: String) throws -> HistoryImportPreview {
        guard activeSession == nil else {
            throw NSError(domain: "FormApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Finish or discard the current workout before importing history."])
        }
        let canonicalNames = Array(ExerciseCatalog.canonicalExercises.values.map { $0.name })
        return try WorkoutHistoryImporter.preview(
            csvText: csvText,
            existingHistory: state.history,
            canonicalNames: canonicalNames
        )
    }

    @discardableResult
    public func executeHistoryImport(_ preview: HistoryImportPreview) -> HistoryImportResult {
        // 1. Safety backup
        let backupJson = exportBackupJson()
        let backupFileName = "safety_backup_before_import_\(Int(Date().timeIntervalSince1970 * 1000)).json"
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsDir.appendingPathComponent(backupFileName)
            try? backupJson.data(using: .utf8)?.write(to: fileURL)
        }

        // 2. Add imported workouts to history
        guard !preview.workoutsToImport.isEmpty else {
            return HistoryImportResult(
                importedCount: 0,
                skippedCount: preview.duplicateWorkoutsCount,
                backupFilePath: backupFileName
            )
        }

        var newHistory = state.history
        newHistory.append(contentsOf: preview.workoutsToImport)
        newHistory.sort { $0.startedAt > $1.startedAt }

        let todayStr = WorkoutCalendar.formatDate(Date())
        let weekdays = WorkoutCalendar.weekdays(state: state)
        let newCal = WorkoutCalendar.restore(
            raw: state.calendarHistory,
            sessions: newHistory,
            today: todayStr,
            timeZone: .current,
            weekdays: weekdays,
            activeSessionId: activeSession?.id,
            programs: state.programs
        )

        var newState = state
        newState.history = newHistory
        newState.calendarHistory = newCal
        saveState(newState)

        showNotice(LanguageManager.t("notice.historyImported", ["count": "\(preview.workoutsToImport.count)"]))

        return HistoryImportResult(
            importedCount: preview.workoutsToImport.count,
            skippedCount: preview.duplicateWorkoutsCount,
            backupFilePath: backupFileName
        )
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
        let bundled = loadBundledStarterPrograms()
        if let data = UserDefaults.standard.data(forKey: "stored_app_state"),
           var stored = try? JSONDecoder().decode(StoredAppState.self, from: data) {
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: "seeded_starters_v9"), bundled.count == 8 {
                if defaults.data(forKey: "starter_programs_before_v9") == nil {
                    defaults.set(data, forKey: "starter_programs_before_v9")
                }
                stored.programs = refreshedStarterPrograms(existing: stored.programs, bundled: bundled)
                // Persist the replacement before its marker. History and the separate draft stay intact.
                if let refreshed = try? JSONEncoder().encode(stored) {
                    defaults.set(refreshed, forKey: "stored_app_state")
                    defaults.set(true, forKey: "seeded_starters_v9")
                }
            }
            stored.programs = enrichStandardizedTechniqueCues(stored.programs, bundled: bundled)
            return stored
        }
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
        if bundled.count == 8 {
            UserDefaults.standard.set(true, forKey: "seeded_starters_v9")
        }
        return initial
    }

    public static func refreshedStarterPrograms(existing: [Program], bundled: [Program]) -> [Program] {
        let ids = Set(bundled.map(\.id))
        return bundled + existing.filter { !ids.contains($0.id) }
    }

    private static func enrichStandardizedTechniqueCues(_ programs: [Program], bundled: [Program]) -> [Program] {
        var standardNotes: [String: (cues: String, avoid: String, exerciseId: String?)] = [:]
        for p in bundled {
            for w in p.workouts {
                for e in w.exercises {
                    let key = e.name.trimmingCharacters(in: .whitespaces).lowercased()
                    if !key.isEmpty && (!e.cues.isEmpty || !e.avoid.isEmpty) {
                        standardNotes[key] = (e.cues, e.avoid, e.exerciseId)
                    }
                }
            }
        }
        if standardNotes.isEmpty { return programs }
        return programs.map { prog in
            var updatedProg = prog
            updatedProg.workouts = prog.workouts.map { w in
                var updatedW = w
                updatedW.exercises = w.exercises.map { e in
                    let key = e.name.trimmingCharacters(in: .whitespaces).lowercased()
                    if let std = standardNotes[key] {
                        var updatedE = e
                        if updatedE.exerciseId == nil { updatedE.exerciseId = std.exerciseId }
                        updatedE.cues = std.cues
                        updatedE.avoid = std.avoid
                        return updatedE
                    }
                    return e
                }
                return updatedW
            }
            return updatedProg
        }
    }

    public static func loadBundledStarterPrograms() -> [Program] {
        let programNames = [
            "01_aesthetic_hypertrophy",
            "02_powerbuilding_strength",
            "03_classic_ppl",
            "04_full_body_classic",
            "05_home_forge_dumbbells",
            "06_athletic_performance",
            "07_upper_lower",
            "08_machine_foundation"
        ]

        var programs: [Program] = []

        for name in programNames {
            var fileData: Data? = nil
            for b in Bundle.allBundles {
                if let url = b.url(forResource: name, withExtension: "json") ??
                             b.url(forResource: name, withExtension: "json", subdirectory: "StarterPrograms"),
                   let data = try? Data(contentsOf: url) {
                    fileData = data
                    break
                }
                let directPath = (b.bundlePath as NSString).appendingPathComponent("\(name).json")
                if FileManager.default.fileExists(atPath: directPath),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: directPath)) {
                    fileData = data
                    break
                }
            }

            if let data = fileData,
               let prog = try? decodeProgram(from: data) {
                programs.append(prog)
            }
        }
        return programs
    }

    public static func loadBundledExercises() -> [String: ExerciseDefinition] {
        var fileData: Data? = nil
        for b in Bundle.allBundles {
            if let url = b.url(forResource: "exercises", withExtension: "json") ??
                         b.url(forResource: "exercises", withExtension: "json", subdirectory: "Resources"),
               let data = try? Data(contentsOf: url) {
                fileData = data
                break
            }
            let directPath = (b.bundlePath as NSString).appendingPathComponent("exercises.json")
            if FileManager.default.fileExists(atPath: directPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: directPath)) {
                    fileData = data
                    break
            }
        }
        if fileData == nil {
            let possiblePaths = [
                "FormApp/Resources/exercises.json",
                "../FormApp/Resources/exercises.json",
                "../../FormApp/Resources/exercises.json"
            ]
            for p in possiblePaths {
                if FileManager.default.fileExists(atPath: p),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: p)) {
                    fileData = data
                    break
                }
            }
        }
        guard let data = fileData,
              let list = try? JSONDecoder().decode([ExerciseDefinition].self, from: data) else {
            return [:]
        }
        var map: [String: ExerciseDefinition] = [:]
        for def in list {
            map[def.id] = def
        }
        return map
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
        guard let date = WorkoutCalendar.parseIsoTimestamp(record.completedAt) ?? WorkoutCalendar.parseIsoTimestamp(record.startedAt) else {
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
    private static var _canonicalExercises: [String: ExerciseDefinition]?

    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static var canonicalExercises: [String: ExerciseDefinition] {
        if let cached = _canonicalExercises { return cached }
        let loaded = AppStore.loadBundledExercises()
        _canonicalExercises = loaded
        return loaded
    }

    public static func build(
        bundledPrograms: [Program] = [],
        userPrograms: [Program] = [],
        preferredProgramId: String? = nil,
        preferredWorkout: Workout? = nil,
        canonicalExercises: [ExerciseDefinition] = []
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

        let canonicalById = Dictionary(uniqueKeysWithValues: canonicalExercises.map { ($0.id, $0) })
        let canonicalByKey = Dictionary(canonicalExercises.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var map: [String: ExerciseCatalogEntry] = [:]
        for s in sources {
            let rawKey = s.exercise.name.trimmingCharacters(in: .whitespaces).lowercased()
            let def = s.exercise.exerciseId.flatMap { canonicalById[$0] }
                ?? canonicalByKey[rawKey]
                ?? canonicalById[rawKey.replacingOccurrences(of: " ", with: "-")]
            let resolvedName = def?.name ?? s.exercise.name
            let key = resolvedName.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty { continue }

            var ex = s.exercise
            if let def = def {
                ex.name = def.name
                if ex.exerciseId == nil { ex.exerciseId = def.id }
            }

            let occ = "\(s.programId)\u{0}\(s.workoutId)"
            if let existing = map[key] {
                let merged = merge(primary: existing.exercise, fallback: ex)
                map[key] = ExerciseCatalogEntry(
                    key: key,
                    exercise: merged,
                    programIds: existing.programIds.union([s.programId]),
                    workoutKeys: existing.workoutKeys.union([occ])
                )
            } else {
                map[key] = ExerciseCatalogEntry(
                    key: key,
                    exercise: ex,
                    programIds: [s.programId],
                    workoutKeys: [occ]
                )
            }
        }

        for def in canonicalExercises {
            let key = def.name.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty && map[key] == nil {
                map[key] = ExerciseCatalogEntry(
                    key: key,
                    exercise: def.toExercise(),
                    programIds: [],
                    workoutKeys: []
                )
            }
        }

        var standardNotes: [String: Exercise] = [:]
        for p in bundledPrograms {
            for w in p.workouts {
                for e in w.exercises {
                    let def = e.exerciseId.flatMap { canonicalById[$0] }
                    let k = def?.name.trimmingCharacters(in: .whitespaces).lowercased()
                        ?? e.name.trimmingCharacters(in: .whitespaces).lowercased()
                    if !k.isEmpty && (!e.cues.isEmpty || !e.avoid.isEmpty) {
                        standardNotes[k] = e
                    }
                }
            }
        }
        return map.values.map { entry in
            var ex = entry.exercise
            let def = ex.exerciseId.flatMap { canonicalById[$0] } ?? canonicalByKey[entry.key]
            let std = standardNotes[entry.key]
            if let def = def {
                ex.name = def.name
                if ex.exerciseId == nil { ex.exerciseId = def.id }
                if ex.cues.trimmingCharacters(in: .whitespaces).isEmpty { ex.cues = def.cuesText }
                if ex.avoid.trimmingCharacters(in: .whitespaces).isEmpty { ex.avoid = def.avoidText }
                if ex.movementType == nil { ex.movementType = def.movementType }
                if ex.movementAssetId == nil { ex.movementAssetId = def.movementAssetId }
            } else if let std = std {
                if ex.exerciseId == nil { ex.exerciseId = std.exerciseId }
                if ex.cues.trimmingCharacters(in: .whitespaces).isEmpty { ex.cues = std.cues }
                if ex.avoid.trimmingCharacters(in: .whitespaces).isEmpty { ex.avoid = std.avoid }
                if ex.movementType == nil { ex.movementType = std.movementType }
                if ex.movementAssetId == nil { ex.movementAssetId = std.movementAssetId }
            }
            return ExerciseCatalogEntry(
                key: entry.key,
                exercise: ex,
                programIds: entry.programIds,
                workoutKeys: entry.workoutKeys
            )
        }.sorted { ExercisePriority.compare($0.exercise, $1.exercise) }
    }

    private static func merge(primary: Exercise, fallback: Exercise) -> Exercise {
        var merged = primary
        if merged.exerciseId == nil { merged.exerciseId = fallback.exerciseId }
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
