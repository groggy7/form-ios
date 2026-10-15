import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public final class AppStore: ObservableObject {
    public static let shared = AppStore()

    private let stateKey = "stored_app_state"
    let statePersistence: AppStatePersistence
    private var persistenceEnabled = true
    private let activeSessionKey = "active_session_v1"
    private let soundKey = "sound_enabled"
    private let defaultRestKey = "default_rest_seconds"
    private let prefillNextSetKey = "prefill_next_set"
    private let homeGlowTilesKey = "home_glow_tiles"
    private let weightUnitKey = "weight_unit"
    private let barTypeKey = "bar_type"
    private let availablePlatesKey = "available_plates_kg"
    private let onboardingCompletedKey = "is_onboarding_completed"
    private let showProgressionTargetsKey = "show_progression_targets"
    private let showWarmupCalculatorKey = "show_warmup_calculator"
    private let progressionCardDismissedKey = "pro_progression_card_dismissed"
    private let warmupCardDismissedKey = "pro_warmup_card_dismissed"
    private let calendarStartMonthKey = "calendar_start_month"

    @Published public var state: StoredAppState
    @Published public var activeSession: ActiveSessionDraft?
    @Published public var isSessionPresented: Bool = false
    @Published public var isOnboardingCompleted: Bool
    @Published public var showProgressionTargets: Bool
    @Published public var showWarmupCalculator: Bool
    @Published public var calendarStartMonth: String

    public var isProgressionCardDismissed: Bool {
        get { !showProgressionTargets }
        set { showProgressionTargets = !newValue }
    }

    public var isWarmupCardDismissed: Bool {
        get { !showWarmupCalculator }
        set { showWarmupCalculator = !newValue }
    }

    public var appThemeId: String {
        get { ThemeManager.shared.currentTheme.id }
        set { ThemeManager.shared.setThemeId(newValue) }
    }
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
    /// Home day tiles use the calm glass by default; this opts back in to the earlier neon glow.
    @Published public var homeGlowTiles: Bool
    @Published public var weightUnit: WeightUnit {
        didSet {
            guard weightUnit != oldValue, let draft = activeSession else { return }
            let rebased = WorkoutSessionUtils.rebaseWeightInputs(draft, from: draft.weightInputUnit ?? oldValue, to: weightUnit)
            saveActiveSession(rebased)
            activeSession = rebased
        }
    }
    @Published public var barType: BarType
    @Published public var availablePlatesKg: [Double]
    @Published public var currentToast: ToastItem?
    @Published public var noticeMessage: String? {
        didSet {
            if let msg = noticeMessage, !msg.isEmpty {
                currentToast = ToastItem(message: msg, style: .info, duration: 3.0)
            }
        }
    }
    @Published public var exerciseCatalogue: [ExerciseCatalogEntry] = []
    let libraryResults = LibraryExerciseResults()
    let sessionHistoryInsights = SessionHistoryInsightsCache()
    
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

    public static let mainTabs: [ViewMode] = [.today, .plan, .library, .history]

    public func navigate(to view: ViewMode) {
        self.selectedExerciseId = nil
        self.selectedHistoryDetailDay = nil
        self.returnView = nil
        self.currentView = view
    }

    public func setCalendarStartMonth(_ month: String) {
        guard month.count == 7 else { return }
        self.calendarStartMonth = month
        UserDefaults.standard.set(month, forKey: calendarStartMonthKey)
    }

    public func updateCalendarStartMonthIfEarlier(_ month: String) {
        guard month.count == 7 else { return }
        if month < calendarStartMonth {
            setCalendarStartMonth(month)
        }
    }

    @discardableResult
    public func navigateToNextTab() -> Bool {
        guard let currentIndex = Self.mainTabs.firstIndex(of: currentView),
              currentIndex < Self.mainTabs.count - 1 else {
            return false
        }
        navigate(to: Self.mainTabs[currentIndex + 1])
        return true
    }

    @discardableResult
    public func navigateToPreviousTab() -> Bool {
        guard let currentIndex = Self.mainTabs.firstIndex(of: currentView),
              currentIndex > 0 else {
            return false
        }
        let target = Self.mainTabs[currentIndex - 1]
        if target == .today {
            selectedWorkoutId = nil
        }
        navigate(to: target)
        return true
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

    public convenience init() {
        self.init(persistence: .shared)
    }

    init(persistence: AppStatePersistence) {
        self.statePersistence = persistence
        self.soundEnabled = UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        self.defaultRestSeconds = UserDefaults.standard.object(forKey: defaultRestKey) as? Int ?? 90
        self.prefillNextSet = UserDefaults.standard.object(forKey: prefillNextSetKey) as? Bool ?? true
        self.homeGlowTiles = UserDefaults.standard.object(forKey: homeGlowTilesKey) as? Bool ?? false
        let initialWeightUnit: WeightUnit
        if let savedUnitCode = UserDefaults.standard.string(forKey: weightUnitKey) {
            initialWeightUnit = WeightUnit.fromCode(savedUnitCode)
        } else {
            initialWeightUnit = WeightUnit.defaultForLocale()
        }
        self.weightUnit = initialWeightUnit
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
        if UserDefaults.standard.object(forKey: showProgressionTargetsKey) != nil {
            self.showProgressionTargets = UserDefaults.standard.bool(forKey: showProgressionTargetsKey)
        } else if UserDefaults.standard.object(forKey: progressionCardDismissedKey) != nil {
            self.showProgressionTargets = !UserDefaults.standard.bool(forKey: progressionCardDismissedKey)
        } else {
            self.showProgressionTargets = true
        }

        if UserDefaults.standard.object(forKey: showWarmupCalculatorKey) != nil {
            self.showWarmupCalculator = UserDefaults.standard.bool(forKey: showWarmupCalculatorKey)
        } else if UserDefaults.standard.object(forKey: warmupCardDismissedKey) != nil {
            self.showWarmupCalculator = !UserDefaults.standard.bool(forKey: warmupCardDismissedKey)
        } else {
            self.showWarmupCalculator = true
        }

        if let savedStartMonth = UserDefaults.standard.string(forKey: calendarStartMonthKey), savedStartMonth.count == 7 {
            self.calendarStartMonth = savedStartMonth
        } else {
            let currentMonth = String(WorkoutCalendar.formatDate(Date()).prefix(7))
            let installMonth: String
            if let docsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last,
               let attrs = try? FileManager.default.attributesOfItem(atPath: docsUrl.path),
               let date = attrs[.creationDate] as? Date {
                installMonth = String(WorkoutCalendar.formatDate(date).prefix(7))
            } else {
                installMonth = currentMonth
            }
            let initial = min(installMonth, currentMonth)
            self.calendarStartMonth = initial
            UserDefaults.standard.set(initial, forKey: calendarStartMonthKey)
        }

        let loaded = Self.loadStoredState(persistence: persistence)
        self.persistenceEnabled = loaded.canPersist
        var loadedState = Self.rotateWeek(loaded.state, now: Date())

        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        let hasExistingData = loaded.hasSavedState || UserDefaults.standard.object(forKey: stateKey) != nil || UserDefaults.standard.object(forKey: activeSessionKey) != nil || !loadedState.history.isEmpty
        if !hasCompleted && hasExistingData {
            UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
            self.isOnboardingCompleted = true
        } else {
            self.isOnboardingCompleted = hasCompleted
        }
        let todayStr = WorkoutCalendar.formatDate(Date())
        let weekdays = WorkoutCalendar.weekdays(state: loadedState)
        let currentWeightUnit = initialWeightUnit
        let rawDraft = Self.loadActiveSession().map { draft in
            // Legacy drafts may contain stale display text from the old unit-switch
            // bug. Prefer their canonical weights and bind the input unit on load.
            guard draft.weightInputUnit == nil || draft.weightInputUnit != currentWeightUnit else { return draft }
            return WorkoutSessionUtils.rebaseWeightInputs(draft, from: draft.weightInputUnit ?? currentWeightUnit, to: currentWeightUnit)
        }
        let isKnownDraft: Bool = {
            guard let draft = rawDraft else { return false }
            return loadedState.programs.contains { prog in
                prog.id == draft.programId && prog.workouts.contains { $0.id == draft.workout.id }
            }
        }()
        let activeDraft = isKnownDraft ? rawDraft : nil
        if rawDraft != nil && !isKnownDraft {
            Self.clearActiveSession()
        }
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
            weekdays: weekdays,
            programs: loadedState.programs,
            sessions: loadedState.history
        )
        loadedState.calendarHistory = refreshed
        self.state = loadedState
        if let earliest = WorkoutCalendar.earliestWorkoutMonth(history: loadedState.calendarHistory, sessions: loadedState.history) {
            updateCalendarStartMonthIfEarlier(earliest)
        }
        if let draft = activeDraft, !draft.isPaused {
            let paused = draft.paused(nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
            self.activeSession = paused
            self.saveActiveSession(paused)
        } else {
            self.activeSession = activeDraft
            if let activeDraft { self.saveActiveSession(activeDraft) }
        }
        self.isSessionPresented = false
        self.selectedWorkoutId = nil
        if let targetView = ProcessInfo.processInfo.environment["INITIAL_VIEW"], targetView == "history" {
            self.currentView = .history
        }

        // Auto-archive stale session if from previous day or > 12 hours old
        self.checkAndArchiveStaleSession()
        self.refreshCatalogue()
        self.saveState(self.state)
        if !persistenceEnabled { showErrorNotice(LanguageManager.t("notice.storageFailed")) }

        // Sync sound preferences
        $soundEnabled
            .sink { [soundKey] in UserDefaults.standard.set($0, forKey: soundKey) }
            .store(in: &cancellables)

        $defaultRestSeconds
            .sink { [defaultRestKey] in UserDefaults.standard.set($0, forKey: defaultRestKey) }
            .store(in: &cancellables)

        $prefillNextSet
            .sink { [prefillNextSetKey] in UserDefaults.standard.set($0, forKey: prefillNextSetKey) }
            .store(in: &cancellables)

        $homeGlowTiles
            .sink { [homeGlowTilesKey] in UserDefaults.standard.set($0, forKey: homeGlowTilesKey) }
            .store(in: &cancellables)

        $weightUnit
            .sink { [weightUnitKey] in UserDefaults.standard.set($0.rawValue, forKey: weightUnitKey) }
            .store(in: &cancellables)

        $barType
            .sink { [barTypeKey] in UserDefaults.standard.set($0.key, forKey: barTypeKey) }
            .store(in: &cancellables)

        $availablePlatesKg
            .sink { [availablePlatesKey] in UserDefaults.standard.set($0, forKey: availablePlatesKey) }
            .store(in: &cancellables)

        $isOnboardingCompleted
            .sink { [onboardingCompletedKey] in UserDefaults.standard.set($0, forKey: onboardingCompletedKey) }
            .store(in: &cancellables)

        $showProgressionTargets
            .dropFirst()
            .sink { [weak self] show in
                guard let self = self else { return }
                UserDefaults.standard.set(show, forKey: self.showProgressionTargetsKey)
                UserDefaults.standard.set(!show, forKey: self.progressionCardDismissedKey)
            }
            .store(in: &cancellables)

        $showWarmupCalculator
            .dropFirst()
            .sink { [weak self] show in
                guard let self = self else { return }
                UserDefaults.standard.set(show, forKey: self.showWarmupCalculatorKey)
                UserDefaults.standard.set(!show, forKey: self.warmupCardDismissedKey)
            }
            .store(in: &cancellables)

        #if canImport(UIKit)
        CloudMirrorManager.shared.retryPendingSyncIfAny()
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.refreshForCurrentDate()
                CloudMirrorManager.shared.retryPendingSyncIfAny()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
            .sink { [weak self] _ in self?.refreshForCurrentDate() }
            .store(in: &cancellables)
        #endif
    }

    public func resetDismissedProCards() {
        showProgressionTargets = true
        showWarmupCalculator = true
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
        if let active = activeSession, active.programId == program.id {
            return active.workout
        }
        let todayDay = currentWeekDayNumber() // 1 = Mon, ..., 7 = Sun
        return program.workouts.first(where: { $0.day == todayDay })
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
            fromActive.insert("\(active.programId):\(active.workout.id)")
        }
        return Set(fromHistory + fromActive)
    }

    // MARK: - Active Session

    public func startActiveSession(
        programId: String,
        workout: Workout,
        allowPast: Bool = false,
        unfinishedRecordId: String? = nil,
        assignedCalendarDate: String? = nil,
        startNewSession: Bool = false,
        scheduledDate: String? = nil,
        resumeHistory: Bool = false
    ) -> Bool {
        checkAndArchiveStaleSession()
        let now = Date()
        let todayStr = WorkoutCalendar.formatDate(now)
        let monday = WorkoutCalendar.mondayOfCurrentWeek(for: now)
        let calendar = Calendar(identifier: .gregorian)
        let nextMonday = WorkoutCalendar.parseDate(monday).flatMap { calendar.date(byAdding: .day, value: 7, to: $0) }
        func resumableDate(_ performed: String?, _ scheduled: String?) -> Bool {
            guard let performed, performed >= monday, performed <= todayStr else { return false }
            guard let scheduledDate = scheduled.flatMap({ WorkoutCalendar.parseDate($0) }), let nextMonday else { return true }
            return scheduledDate >= WorkoutCalendar.parseDate(monday)! && scheduledDate < nextMonday
        }
        if let active = activeSession {
            let isKnown = state.programs.contains { prog in
                prog.id == active.programId && prog.workouts.contains { $0.id == active.workout.id }
            }
            if !isKnown {
                abandonActiveSession()
                showErrorNotice(LanguageManager.t("notice.orphanedSessionCleared"))
            } else if !startNewSession && active.programId == programId && active.workout.id == workout.id
                && (unfinishedRecordId == nil || unfinishedRecordId == active.id) {
                if resumeHistory && !resumableDate(active.assignedCalendarDate ?? WorkoutCalendar.localDate(from: active.startedAt), active.scheduledDate) { return false }
                resumeActiveSession()
                return true
            } else {
                showErrorNotice(LanguageManager.t("history.finishActiveFirst"))
                return false
            }
        }
        if workout.exercises.isEmpty {
            showErrorNotice(LanguageManager.t("notice.needOneExercise"))
            return false
        }
        if !canStartWorkout(workout, allowPast: allowPast) {
            let day = LanguageManager.workoutDays.indices.contains(workout.day - 1) ? LanguageManager.workoutDays[workout.day - 1] : ""
            showErrorNotice(LanguageManager.t("today.availableOn", ["day": day]))
            return false
        }
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        let currentWeek = currentWeekIsoKey()
        let unfinishedRecord = startNewSession ? nil : ((unfinishedRecordId.flatMap { recId in
            state.history.first { $0.id == recId }
        }) ?? state.history.first { r in
            r.programId == programId &&
            r.workoutId == workout.id &&
            r.isComplete == false &&
            recordWeekIsoKey(r) == currentWeek
        })

        let unfinishedRecordDate: String? = {
            guard let record = unfinishedRecord else { return nil }
            return state.calendarHistory?.entries.first(where: { $0.id == "session:\(record.id)" })?.date
                ?? WorkoutCalendar.localDate(from: record.startedAt)
        }()
        if resumeHistory {
            guard let record = unfinishedRecord, record.id == unfinishedRecordId,
                  record.programId == programId, record.workoutId == workout.id,
                  !WorkoutCalendar.isSessionComplete(session: record, workout: workout),
                  resumableDate(unfinishedRecordDate, record.scheduledDate) else { return false }
        }
        let sessionWorkout = resumeHistory ? (unfinishedRecord?.workoutSnapshot ?? workout) : workout
        let setsByExercise = unfinishedRecord.map { WorkoutSessionUtils.restoreSetsFromHistory(workout: sessionWorkout, record: $0, unit: weightUnit) }
            ?? WorkoutSessionUtils.initialSets(for: sessionWorkout)
        let initialIndex = WorkoutSessionUtils.firstIncompleteExerciseIndex(workout: sessionWorkout, setsByExercise: setsByExercise)
        let isSameDayUnfinished = unfinishedRecordDate == nil || unfinishedRecordDate == todayStr
        let sessionDay = resumeHistory ? unfinishedRecordDate! : (assignedCalendarDate ?? (isSameDayUnfinished ? unfinishedRecordDate : nil) ?? todayStr)
        let previousDuration = resumeHistory || isSameDayUnfinished ? (unfinishedRecord?.durationSeconds ?? 0) : 0
        let clampedPrevSecs = min(max(0, previousDuration), 4 * 3600)
        let startedAtDate = now.addingTimeInterval(-Double(clampedPrevSecs))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startedAtTimestamp = resumeHistory ? unfinishedRecord!.startedAt : formatter.string(from: startedAtDate)
        let startedAtEpoch = Int64((WorkoutCalendar.parseIsoTimestamp(startedAtTimestamp) ?? startedAtDate).timeIntervalSince1970 * 1000)
        let draft = ActiveSessionDraft(
            id: (resumeHistory || assignedCalendarDate != nil || isSameDayUnfinished) ? (unfinishedRecord?.id ?? UUID().uuidString) : UUID().uuidString,
            programId: programId,
            workout: sessionWorkout,
            startedAt: startedAtTimestamp,
            startedAtEpochMillis: startedAtEpoch,
            lastActivityEpochMillis: nowMillis,
            currentExerciseIndex: initialIndex,
            setsByExercise: setsByExercise,
            assignedCalendarDate: sessionDay,
            accumulatedSeconds: clampedPrevSecs,
            isPaused: false,
            lastResumedAtEpochMillis: nowMillis,
            scheduledDate: resumeHistory ? unfinishedRecord?.scheduledDate : (unfinishedRecord?.scheduledDate ?? scheduledDate
                ?? WorkoutCalendar.scheduledDate(forWeekday: sessionWorkout.day, relativeTo: now)),
            weightInputUnit: weightUnit
        )

        saveActiveSession(draft)
        self.activeSession = draft
        self.isSessionPresented = true

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

    public func pauseActiveSession() {
        guard let active = activeSession, !active.isPaused else { return }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let paused = active.paused(nowEpochMillis: nowMillis)
        saveActiveSession(paused)
        self.activeSession = paused
        self.isSessionPresented = false
    }

    public func resumeActiveSession() {
        guard let active = activeSession else { return }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let resumed = active.resumed(nowEpochMillis: nowMillis)
        saveActiveSession(resumed)
        self.activeSession = resumed
        self.isSessionPresented = true
        FormAudioPlayer.playWorkoutStartSound()
    }

    public func updateActiveSession(_ transform: (ActiveSessionDraft) -> ActiveSessionDraft) {
        guard let current = activeSession else { return }
        var updated = transform(current)
        updated.weightInputUnit = weightUnit
        updated.lastActivityEpochMillis = Int64(Date().timeIntervalSince1970 * 1000)
        saveActiveSession(updated)
        self.activeSession = updated

        let allSets = updated.setsByExercise.values.flatMap { $0 }
        let hasCompleted = allSets.contains { $0.isCompleted }
        if let cal = state.calendarHistory {
            let sessionDate: String = {
                if let assigned = updated.assignedCalendarDate {
                    return assigned
                }
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
        self.isSessionPresented = false
    }

    private func resolveWorkout(for record: WorkoutSessionRecord) -> Workout? {
        if let w = activeSession?.workout, w.id == record.workoutId {
            return w
        }
        if let p = state.programs.first(where: { $0.id == record.programId }),
           let w = p.workouts.first(where: { $0.id == record.workoutId }) {
            return w
        }
        if let w = activeProgram?.workouts.first(where: { $0.id == record.workoutId }) {
            return w
        }
        for p in state.programs {
            if let w = p.workouts.first(where: { $0.id == record.workoutId }) {
                return w
            }
        }
        return nil
    }

    public func completeActiveSession(_ record: WorkoutSessionRecord) {
        refreshForCurrentDate()
        let workout = resolveWorkout(for: record)
        let isComplete = activeSession.map(WorkoutSessionUtils.isComplete)
            ?? WorkoutCalendar.isSessionComplete(session: record, workout: workout)
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
            isComplete: isComplete,
            scheduledDate: record.scheduledDate ?? activeSession?.scheduledDate,
            workoutSnapshot: record.workoutSnapshot ?? activeSession?.workout
        )

        var cal = state.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(),
            scheduledWeekdays: WorkoutCalendar.weekdays(state: state)
        )
        let draftEntryDate = activeSession?.assignedCalendarDate
            ?? (activeSession.flatMap { draft in
                state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })?.date
            })
        let recordEntryDate = state.calendarHistory?.entries.first(where: { $0.id == "session:\(finalRecord.id)" })?.date
        let sessionDate: String
        if let d = draftEntryDate {
            sessionDate = d
        } else if let d = recordEntryDate {
            sessionDate = d
        } else if let d = WorkoutCalendar.localDate(from: finalRecord.startedAt) {
            sessionDate = d
        } else if let d = WorkoutCalendar.localDate(from: finalRecord.completedAt) {
            sessionDate = d
        } else {
            sessionDate = WorkoutCalendar.formatDate(Date())
        }

        let adjustedRecord: WorkoutSessionRecord = {
            let todayStr = WorkoutCalendar.formatDate(Date())
            guard sessionDate != todayStr,
                  WorkoutCalendar.localDate(from: finalRecord.startedAt) != sessionDate,
                  let targetDay = WorkoutCalendar.parseDate(sessionDate) else {
                return finalRecord
            }
            let cal = Calendar(identifier: .gregorian)
            let timeZone = TimeZone.current
            let targetComps = cal.dateComponents(in: timeZone, from: targetDay)

            func adjustIsoDate(_ isoString: String) -> String {
                guard let origDate = WorkoutCalendar.parseIsoTimestamp(isoString) else { return isoString }
                var origComps = cal.dateComponents(in: timeZone, from: origDate)
                origComps.year = targetComps.year
                origComps.month = targetComps.month
                origComps.day = targetComps.day
                guard let newDate = cal.date(from: origComps) else { return isoString }
                let formatter = ISO8601DateFormatter()
                return formatter.string(from: newDate)
            }

            return WorkoutSessionRecord(
                id: finalRecord.id,
                programId: finalRecord.programId,
                workoutId: finalRecord.workoutId,
                workoutTitle: finalRecord.workoutTitle,
                startedAt: adjustIsoDate(finalRecord.startedAt),
                completedAt: adjustIsoDate(finalRecord.completedAt),
                durationSeconds: finalRecord.durationSeconds,
                totalVolumeKg: finalRecord.totalVolumeKg,
                totalCompletedSets: finalRecord.totalCompletedSets,
                exerciseLogs: finalRecord.exerciseLogs,
                isComplete: finalRecord.isComplete,
                scheduledDate: finalRecord.scheduledDate,
                workoutSnapshot: finalRecord.workoutSnapshot
            )
        }()

        var newHistory = state.history
        newHistory.removeAll { $0.id == adjustedRecord.id }
        newHistory.insert(adjustedRecord, at: 0)

        var newCompleted = state.completed
        let key = "\(finalRecord.programId):\(finalRecord.workoutId)"
        if isComplete && PersonalRecordTracker.isRecordInWeek(adjustedRecord, targetWeekKey: state.currentWeekKey)
            && !newCompleted.contains(key) {
            newCompleted.append(key)
        }

        if let draft = activeSession {
            cal = WorkoutCalendar.remove(history: cal, id: "session:\(draft.id)")
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
        guard saveState(newState, durable: true) else { return }

        if ProAccessManager.shared.isFeatureUnlocked(.cloudBackup) {
            CloudMirrorManager.shared.autoSync(backupJson: exportBackupJson())
        }
        
        saveActiveSession(nil)
        self.activeSession = nil
        self.isSessionPresented = false

        showNotice(LanguageManager.t("notice.workoutRecorded", [
            "sets": finalRecord.totalCompletedSets,
            "volume": Int(finalRecord.totalVolumeKg)
        ]))
    }

    // MARK: - Program Management

    @discardableResult
    public func switchProgram(to programId: String) -> Bool {
        guard let prog = state.programs.first(where: { $0.id == programId }) else { return false }
        var next = state
        next.activeProgramId = prog.id
        guard saveState(refreshCalendarState(next), durable: true) else { return false }
        selectedWorkoutId = nil
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programApplied", ["name": prog.displayName]))
        return true
    }

    @discardableResult
    public func addProgram(_ program: Program, activate: Bool = true) -> Bool {
        do { try ProgramEditing.validate(program) }
        catch { showErrorNotice(error.localizedDescription); return false }
        var next = state
        if let index = next.programs.firstIndex(where: { $0.id == program.id }) {
            guard activeSession?.programId != program.id else {
                showErrorNotice(LanguageManager.t("history.finishActiveFirst")); return false
            }
            next.programs[index] = program
        } else {
            guard next.programs.count < ProgramEditing.maxPrograms else {
                showErrorNotice(LanguageManager.t("builder.programLimit")); return false
            }
            next.programs.append(program)
        }
        let validKeys = Set(next.programs.flatMap { p in p.workouts.map { "\(p.id):\($0.id)" } })
        next.completed = next.completed.filter { validKeys.contains($0) }
        if activate || state.programs.isEmpty { next.activeProgramId = program.id }
        guard saveState(refreshCalendarState(next), durable: true) else { return false }
        selectedWorkoutId = nil
        refreshCatalogue()
        showNotice(LanguageManager.t(activate ? "notice.programApplied" : "notice.programCreated", ["name": program.displayName]))
        return true
    }

    @discardableResult
    public func updateProgram(_ program: Program, expected: Program? = nil) -> Bool {
        do { try ProgramEditing.validate(program) }
        catch { showErrorNotice(error.localizedDescription); return false }
        guard let index = state.programs.firstIndex(where: { $0.id == program.id }) else { return false }
        if let expected, state.programs[index] != expected {
            showErrorNotice(LanguageManager.t("builder.draftConflict")); return false
        }
        if let active = activeSession, active.programId == program.id,
           !program.workouts.contains(where: { $0.id == active.workout.id }) {
            showErrorNotice(LanguageManager.t("history.finishActiveFirst")); return false
        }
        var next = state
        next.programs[index] = program
        let validKeys = Set(next.programs.flatMap { p in p.workouts.map { "\(p.id):\($0.id)" } })
        next.completed = next.completed.filter { validKeys.contains($0) }
        guard saveState(refreshCalendarState(next), durable: true) else { return false }
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programUpdated"))
        return true
    }

    @discardableResult
    public func deleteProgram(withId id: String) -> Bool {
        guard state.programs.contains(where: { $0.id == id }) else { return false }
        if activeSession?.programId == id {
            showErrorNotice(LanguageManager.t("history.finishActiveFirst")); return false
        }
        var next = state
        next.programs.removeAll { $0.id == id }
        if next.activeProgramId == id { next.activeProgramId = next.programs.first?.id ?? "" }
        next.completed = next.completed.filter { !$0.hasPrefix("\(id):") }
        guard saveState(refreshCalendarState(next), durable: true) else { return false }
        selectedWorkoutId = nil
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.programDeleted"))
        return true
    }

    /// Moves the chosen program onto the user's days and selects it; the calendar follows its workout days.
    public func completeOnboarding(preferences: OnboardingPreferences, targetProgramId: String? = nil) {
        let chosenProgramId = targetProgramId
            ?? OnboardingRecommender.recommendProgram(preferences: preferences, availablePrograms: state.programs).targetProgramId
        guard let index = state.programs.firstIndex(where: { $0.id == chosenProgramId }) else {
            setOnboardingCompleted(true)
            return
        }

        var newState = state
        newState.programs[index] = OnboardingRecommender.schedule(newState.programs[index], preferences: preferences)
        newState.activeProgramId = chosenProgramId
        newState = refreshCalendarState(newState)
        saveState(newState)
        selectedWorkoutId = nil
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
            weekdays: WorkoutCalendar.weekdays(state: state),
            programs: state.programs,
            sessions: state.history
        )
        var statuses = WorkoutCalendar.statuses(history: refreshed, today: todayStr)

        func hasLoggedSets(for dateStr: String) -> Bool {
            if let active = activeSession {
                let activeDate = active.assignedCalendarDate
                    ?? curCal.entries.first(where: { $0.id == "session:\(active.id)" })?.date
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
                let activeDate = active.assignedCalendarDate
                    ?? curCal.entries.first(where: { $0.id == "session:\(active.id)" })?.date
                    ?? WorkoutCalendar.localDate(from: active.startedAt) ?? todayStr
                if (statuses[activeDate]?.priority ?? -1) < WorkoutDayStatus.unfinished.priority {
                    statuses[activeDate] = .unfinished
                }
            }
        }

        // 1. Today with no logged sets -> neutral (no status)
        if statuses[todayStr] == .unfinished && !hasLoggedSets(for: todayStr) {
            statuses.removeValue(forKey: todayStr)
        }

        // 2. Passed days with no logged sets -> red (.missed), and verify completed days
        for (dateStr, status) in statuses {
            if dateStr < todayStr && status == .unfinished && !hasLoggedSets(for: dateStr) {
                statuses[dateStr] = .missed
            } else if status == .completed {
                let records = state.history.filter { record in
                    let date = curCal.entries.first(where: { $0.id == "session:\(record.id)" })?.date
                        ?? WorkoutCalendar.localDate(from: record.startedAt) ?? WorkoutCalendar.localDate(from: record.completedAt)
                    return date == dateStr
                }
                let hasCompletionMark = curCal.entries.contains {
                    $0.date == dateStr && $0.status == .completed && !$0.id.hasPrefix("session:")
                }
                if !hasCompletionMark && !records.isEmpty
                    && !records.contains(where: { WorkoutCalendar.isSessionComplete(session: $0, workout: nil) }) {
                    statuses[dateStr] = .unfinished
                }
            }
        }

        // Only a recorded scheduled origin can neutralize a missed day. A mutable plan cannot relabel history.
        var origins = WorkoutCalendar.scheduledOriginsWithActivity(sessions: state.history, entries: curCal.entries)
        if let active = activeSession, let origin = active.scheduledDate, WorkoutCalendar.parseDate(origin) != nil,
           active.setsByExercise.values.flatMap({ $0 }).contains(where: { $0.isCompleted }) {
            let performed = active.assignedCalendarDate
                ?? curCal.entries.first(where: { $0.id == "session:\(active.id)" })?.date
                ?? WorkoutCalendar.localDate(from: active.startedAt)
            if performed != nil && performed != origin { origins.insert(origin) }
        }
        for origin in origins where statuses[origin] == .missed { statuses.removeValue(forKey: origin) }

        return statuses
    }

    public func refreshForCurrentDate(now: Date = Date()) {
        let rotated = Self.rotateWeek(state, now: now)
        let refreshed = refreshCalendarState(rotated, now: now)
        guard refreshed.currentWeekKey != state.currentWeekKey || refreshed.calendarHistory != state.calendarHistory else { return }
        saveState(refreshed, now: now)
    }

    /// Recover current-week completions from history when upgrading a store whose week key was frozen.
    static func rotateWeek(_ state: StoredAppState, now: Date, timeZone: TimeZone = .current) -> StoredAppState {
        let weekKey = currentWeekIsoKeyStatic(now: now, timeZone: timeZone)
        guard state.currentWeekKey != weekKey else { return state }
        var next = state
        if !state.completed.isEmpty && !state.currentWeekKey.isEmpty {
            next.weeklyArchives.insert(WeeklyArchive(
                weekKey: state.currentWeekKey,
                completed: state.completed,
                archivedAt: ISO8601DateFormatter().string(from: now)
            ), at: 0)
        }
        next.currentWeekKey = weekKey
        next.completed = Array(Set(state.history.filter { record in
            guard PersonalRecordTracker.isRecordInWeek(record, targetWeekKey: weekKey, timeZone: timeZone) else { return false }
            if let isComplete = record.isComplete { return isComplete }
            let workout = state.programs.first { $0.id == record.programId }?.workouts.first { $0.id == record.workoutId }
            return WorkoutCalendar.isSessionComplete(session: record, workout: workout)
        }.map { "\($0.programId):\($0.workoutId)" })).sorted()
        return next
    }

    private func refreshCalendarState(_ st: StoredAppState, now: Date = Date()) -> StoredAppState {
        let weekdays = WorkoutCalendar.weekdays(state: st)
        let today = now
        let todayStr = WorkoutCalendar.formatDate(today)
        let curCal = st.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(for: today),
            scheduledWeekdays: weekdays
        )
        let refreshed = WorkoutCalendar.refresh(
            history: curCal,
            today: todayStr,
            weekdays: weekdays,
            programs: st.programs,
            sessions: st.history
        )
        var copy = st
        copy.calendarHistory = refreshed
        return copy
    }

    public struct ProgramFileEnvelope: Codable {
        public var format: String?
        public var schemaVersion: Int?
        public var program: Program

        public func encode(to encoder: Encoder) throws {
            let value = try JSONDecoder().decode(ProgramFileJSONValue.self, from: ProgramFileCodec.encode(program))
            try value.encode(to: encoder)
        }

        public init(format: String? = "form.program", schemaVersion: Int? = 5, program: Program) {
            self.format = format
            self.schemaVersion = schemaVersion
            self.program = program
        }
    }

    public enum ProgramImportError: LocalizedError {
        case fileTooLarge
        case notAnObject
        case fullBackup
        case invalidFormat(String)
        case unsupportedVersion(Int)
        case missingProgram
        case invalidProgramName
        case invalidWorkoutDays
        case duplicateWorkoutDays
        case duplicateWorkoutIds

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge:
                return "Program file is too large (maximum 5MB)."
            case .notAnObject:
                return "The selected file must be a JSON object."
            case .fullBackup:
                return "This is a full backup. Use Restore backup in Settings, not Import program."
            case .invalidFormat(let fmt):
                return "Invalid format \"\(fmt)\". Expected \"form.program\"."
            case .unsupportedVersion(let v):
                return "Unsupported program schemaVersion: \(v). Supported versions are 1–5."
            case .missingProgram:
                return "File does not contain a program."
            case .invalidProgramName:
                return "Program name must be non-blank."
            case .invalidWorkoutDays:
                return "Workout days must be weekdays 1 to 7 (Monday = 1)."
            case .duplicateWorkoutDays:
                return "Only one workout per weekday is supported."
            case .duplicateWorkoutIds:
                return "Workouts within a program must have unique IDs."
            }
        }
    }

    public static func decodeProgram(from data: Data) throws -> Program {
        try ProgramFileCodec.decode(data)
    }

    public func previewProgramImport(jsonData: Data) throws -> ProgramImportPreview {
        guard activeSession == nil else { throw ProgramEditing.ValidationError(message: LanguageManager.t("history.finishActiveFirst")) }
        let program = try ProgramFileCodec.decode(jsonData, defaultRest: defaultRestSeconds)
        return ProgramImportPreview(incoming: program, existing: state.programs.first { $0.id == program.id })
    }

    @discardableResult
    public func applyProgramImport(_ preview: ProgramImportPreview) throws -> Program {
        guard activeSession == nil else { throw ProgramEditing.ValidationError(message: LanguageManager.t("history.finishActiveFirst")) }
        guard state.programs.first(where: { $0.id == preview.incoming.id }) == preview.existing else {
            throw ProgramEditing.ValidationError(message: LanguageManager.t("builder.draftConflict"))
        }
        guard addProgram(preview.incoming) else { throw ProgramEditing.ValidationError(message: LanguageManager.t("builder.saveFailed")) }
        return preview.incoming
    }

    public func importProgram(jsonData: Data) throws -> Program {
        try applyProgramImport(previewProgramImport(jsonData: jsonData))
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

    public func showNotice(_ message: String, style: ToastStyle = .info, duration: Double = 3.0) {
        self.noticeMessage = message
        self.currentToast = ToastItem(message: message, style: style, duration: duration)
    }

    public func showErrorNotice(_ message: String, duration: Double = 2.5) {
        self.noticeMessage = message
        self.currentToast = ToastItem(message: message, style: .error, duration: duration)
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
        let isKnown = state.programs.contains { prog in
            prog.id == draft.programId && prog.workouts.contains { $0.id == draft.workout.id }
        }
        if !isKnown {
            abandonActiveSession()
            showErrorNotice(LanguageManager.t("notice.orphanedSessionCleared"))
            return true
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let startedDate = WorkoutCalendar.localDate(from: draft.startedAt) ?? WorkoutCalendar.formatDate(Date())
        let todayStr = WorkoutCalendar.formatDate(Date())
        let lastActivity = draft.lastActivityEpochMillis > 0 ? draft.lastActivityEpochMillis : draft.startedAtEpochMillis

        let isStartedOnPreviousDay = startedDate < todayStr && (now - lastActivity) > (2 * 3600 * 1000)
        let isInactive = (now - lastActivity) > (4 * 3600 * 1000)
        let isOverMaxDuration = draft.currentDurationSeconds(nowEpochMillis: now) >= (6 * 3600)

        let isStale = isStartedOnPreviousDay || isInactive || isOverMaxDuration
        guard isStale else { return false }

        let allSets = draft.setsByExercise.values.flatMap { $0 }
        let hasCompleted = allSets.contains { $0.isCompleted }
        if hasCompleted {
            let elapsedActivitySeconds = draft.currentDurationSeconds(nowEpochMillis: now)
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
        return activeSession == nil
    }

    @discardableResult
    func saveState(_ newState: StoredAppState, now: Date = Date(), durable: Bool = false) -> Bool {
        guard persistenceEnabled else {
            showErrorNotice(LanguageManager.t("notice.storageFailed"))
            return false
        }
        let normalized = Self.rotateWeek(newState, now: now)
        if durable {
            do { try statePersistence.saveAndWait(normalized) }
            catch {
                showErrorNotice(LanguageManager.t("notice.storageFailed"))
                return false
            }
        } else {
            statePersistence.save(normalized) { [weak self] error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.showErrorNotice(LanguageManager.t("notice.storageFailed")) }
            }
        }
        if normalized.currentWeekKey != state.currentWeekKey { selectedWorkoutId = nil }
        self.state = normalized
        return true
    }

    func flushPendingState() {
        do { try statePersistence.flush() }
        catch { showErrorNotice(LanguageManager.t("notice.storageFailed")) }
    }

    public func exportBackupJson() -> String {
        refreshForCurrentDate()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(FullBackupDocument(state: state, weightUnit: weightUnit))
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
            let backup = try decoder.decode(FullBackupDocument.self, from: data)
            var decodedState = Self.rotateWeek(backup.state, now: Date())
            decodedState.calendarHistory = WorkoutCalendar.restore(
                raw: decodedState.calendarHistory,
                sessions: decodedState.history,
                today: WorkoutCalendar.formatDate(Date()),
                weekdays: WorkoutCalendar.weekdays(state: decodedState),
                activeSessionId: activeSession?.id,
                programs: decodedState.programs
            )
            guard saveState(refreshCalendarState(decodedState), durable: true) else { return false }
            // Metadata restores the display preference, never the numeric weights.
            // The property observer also rebases the live workout we preserve.
            if let restoredUnit = backup.weightUnit { weightUnit = restoredUnit }
            if let earliest = WorkoutCalendar.earliestWorkoutMonth(history: backup.state.calendarHistory, sessions: backup.state.history) {
                updateCalendarStartMonthIfEarlier(earliest)
            }
            return true
        } catch {
            print("Failed to restore backup: \(error)")
            return false
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

    private static func clearActiveSession() {
        UserDefaults.standard.removeObject(forKey: "active_session_v1")
    }

    private static func loadStoredState(persistence: AppStatePersistence) -> (state: StoredAppState, canPersist: Bool, hasSavedState: Bool) {
        let defaults = UserDefaults.standard
        let hasLegacy = defaults.data(forKey: "stored_app_state") != nil
        var legacy: StoredAppState?
        do {
            if hasLegacy {
                let restored = loadLegacyState()
                legacy = restored
                try persistence.migrate(restored, defaults: defaults, legacyKey: "stored_app_state")
                return (restored, true, true)
            }
            if var stored = try persistence.load() {
                stored.programs = enrichStandardizedTechniqueCues(stored.programs, bundled: loadBundledStarterPrograms())
                return (stored, true, true)
            }
            return (loadLegacyState(), true, false)
        } catch {
            // Preserve the database and legacy blob. Never overwrite unreadable storage with defaults.
            print("[AppStore] Workout persistence unavailable; recovery data retained.")
            return (legacy ?? loadLegacyState(), false, hasLegacy)
        }
    }

    private static func loadLegacyState() -> StoredAppState {
        let bundled = loadBundledStarterPrograms()
        if let data = UserDefaults.standard.data(forKey: "stored_app_state") {
            do {
                var stored = try JSONDecoder().decode(StoredAppState.self, from: data)
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
            } catch {
                let quarantineKey = "quarantine_corrupt_state_\(Int(Date().timeIntervalSince1970 * 1000))"
                UserDefaults.standard.set(data, forKey: quarantineKey)
                print("[AppStore] CRITICAL: Failed to decode stored_app_state: \(error). Quarantined in \(quarantineKey)")

                // Attempt emergency rescue of history from raw JSON dictionary
                if let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rawHistory = rawDict["history"],
                   let rawHistoryData = try? JSONSerialization.data(withJSONObject: rawHistory),
                   let rescuedHistory = try? JSONDecoder().decode([WorkoutSessionRecord].self, from: rawHistoryData) {
                    print("[AppStore] Rescued \(rescuedHistory.count) historical sessions from corrupt state.")
                    let activeId = bundled.first?.id ?? UUID().uuidString
                    return StoredAppState(
                        schemaVersion: 4,
                        programs: bundled,
                        activeProgramId: activeId,
                        completed: [],
                        currentWeekKey: currentWeekIsoKeyStatic(),
                        weeklyArchives: [],
                        history: rescuedHistory,
                        calendarHistory: nil
                    )
                }
            }
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
                        if updatedE.exerciseId == nil {
                            updatedE.exerciseId = std.exerciseId
                        }
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

    private static func currentWeekIsoKeyStatic(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
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
    // Swift initializes static lets once, including simultaneous first access.
    public static let canonicalExercises = AppStore.loadBundledExercises()

    private static func normalizeForLookup(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let canonicalLookup: [String: String] = {
        let loaded = canonicalExercises
        var lookup: [String: String] = [:]
        for def in loaded.values {
            let id = def.id
            lookup[id] = id
            lookup[id.lowercased()] = id

            let normName = normalizeForLookup(def.name)
            if !normName.isEmpty {
                lookup[normName] = id
                let slugName = normName.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
                lookup[slugName] = id
            }
            let slugId = id.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
            lookup[slugId] = id
        }
        return lookup
    }()

    public static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Stable IDs win; legacy records fall back to exact normalized catalog names, then slugs.
    public static func resolveCanonicalId(stableId: String?, name: String) -> String? {
        if let stable = stableId?.trimmingCharacters(in: .whitespacesAndNewlines), !stable.isEmpty {
            return stable
        }
        let normalized = normalizeForLookup(name)
        guard !normalized.isEmpty else { return nil }
        let lookup = canonicalLookup
        if let direct = lookup[normalized] { return direct }
        let slug = normalized.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
        return lookup[slug]
    }

    /// Compare stable catalog identities first; use names for legacy/custom logs.
    public static func sameExercise(leftId: String?, leftName: String, rightId: String?, rightName: String) -> Bool {
        let left = resolveCanonicalId(stableId: leftId, name: leftName)
        let right = resolveCanonicalId(stableId: rightId, name: rightName)
        if let left, let right { return left.caseInsensitiveCompare(right) == .orderedSame }
        return key(leftName) == key(rightName)
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
                if ex.movementType == nil { ex.movementType = def.movementType }
                if ex.movementAssetId == nil { ex.movementAssetId = def.movementAssetId }
            } else if let std = std {
                if ex.exerciseId == nil { ex.exerciseId = std.exerciseId }
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
        if merged.videos.isEmpty { merged.videos = fallback.videos }
        if merged.sets == nil { merged.sets = fallback.sets }
        if merged.reps == nil { merged.reps = fallback.reps }
        if merged.restSeconds == nil { merged.restSeconds = fallback.restSeconds }
        if merged.movementType == nil { merged.movementType = fallback.movementType }
        if merged.movementAssetId == nil { merged.movementAssetId = fallback.movementAssetId }
        return merged
    }
}

/// Flat, backward-compatible full-backup document. `weightUnit` is the preferred
/// display/input unit; numeric fields named `weightKg`/`totalVolumeKg` stay in kg.
/// Plain program exports and on-device StoredAppState persistence are unaffected.
struct FullBackupDocument: Codable {
    let state: StoredAppState
    let weightUnit: WeightUnit?
    private enum MetadataKeys: String, CodingKey { case weightUnit }

    init(state: StoredAppState, weightUnit: WeightUnit) {
        self.state = state
        self.weightUnit = weightUnit
    }

    init(from decoder: Decoder) throws {
        state = try StoredAppState(from: decoder)
        let metadata = try decoder.container(keyedBy: MetadataKeys.self)
        if let code = try metadata.decodeIfPresent(String.self, forKey: .weightUnit) {
            guard let unit = WeightUnit(rawValue: code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                throw DecodingError.dataCorruptedError(forKey: .weightUnit, in: metadata, debugDescription: "Backup weight unit must be kg or lbs")
            }
            weightUnit = unit
        } else {
            weightUnit = nil // Old backups preserve this device's preference without guessing.
        }
    }

    func encode(to encoder: Encoder) throws {
        try state.encode(to: encoder)
        var metadata = encoder.container(keyedBy: MetadataKeys.self)
        try metadata.encodeIfPresent(weightUnit, forKey: .weightUnit)
    }
}
