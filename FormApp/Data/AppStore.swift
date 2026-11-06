import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// The workout in progress. Its publisher emits on every set edit, like a `@Published` property.
public final class LiveSession: ObservableObject {
    @Published public fileprivate(set) var draft: ActiveSessionDraft? {
        didSet { if let draft { lastDraft = draft } }
    }
    /// The last draft, which the workout screen keeps showing while it closes after the workout ends.
    public private(set) var lastDraft: ActiveSessionDraft?
}

/// What the tabs show of a workout while the workout cover hides them.
private struct CoveredSessionFacts: Equatable {
    let id: String
    let programId: String
    let workoutId: String
    let hasCompletedSets: Bool
    let assignedCalendarDate: String?
    let scheduledDate: String?

    init?(_ draft: ActiveSessionDraft?) {
        guard let draft else { return nil }
        id = draft.id
        programId = draft.programId
        workoutId = draft.workout.id
        hasCompletedSets = draft.setsByExercise.values.contains { $0.contains(where: \.isCompleted) }
        assignedCalendarDate = draft.assignedCalendarDate
        scheduledDate = draft.scheduledDate
    }
}

public final class AppStore: ObservableObject {
    public static let shared = AppStore()

    private let stateKey = "stored_app_state"
    let statePersistence: AppStatePersistence
    private var persistenceEnabled = true
    private let activeSessionKey = "active_session_v1"
    private let soundKey = "sound_enabled"
    private let defaultRestKey = "default_rest_seconds"
    private let prefillNextSetKey = "prefill_next_set"
    private let homeGlowTilesKey = "home_reference_tiles_v2"
    private let historyCalendarTilesKey = "history_calendar_tiles"
    private let sessionStripCollapsedKey = "session_strip_collapsed"
    private let weightUnitKey = "weight_unit"
    private let barTypeKey = "bar_type"
    private let availablePlatesKey = "available_plates_kg"
    private let availablePlatesLbsKey = "available_plates_lbs"
    private let onboardingCompletedKey = "is_onboarding_completed"
    private let showProgressionTargetsKey = "show_progression_targets"
    private let showIntensityTechniquesKey = "show_intensity_techniques"
    private let jointStressRatingsKey = "joint_stress_ratings"
    private let repsInReserveKey = "reps_in_reserve"
    private let effortScaleKey = SetEffort.scaleDefaultsKey
    private let recordWatchWorkoutsKey = "record_watch_workouts"
    private static let dumbbellStepKgKey = "progression_dumbbell_step_kg"
    private static let dumbbellStepLbsKey = "progression_dumbbell_step_lbs"
    private static let machineStepKgKey = "progression_machine_step_kg"
    private static let machineStepLbsKey = "progression_machine_step_lbs"
    private let showWarmupCalculatorKey = "show_warmup_calculator"
    private let progressionCardDismissedKey = "pro_progression_card_dismissed"
    private let warmupCardDismissedKey = "pro_warmup_card_dismissed"
    private let calendarStartMonthKey = "calendar_start_month"

    @Published public var state: StoredAppState
    /// The workout screen, rest alerts, Live Activity and Apple Watch observe the draft here.
    public let liveSession = LiveSession()
    /// The four tabs stay alive under the workout cover and redraw whenever the store changes.
    /// While the cover is up, a set edit reaches them only when it changes something they show
    /// before it closes; closing the cover redraws them from the current draft.
    public var activeSession: ActiveSessionDraft? {
        get { liveSession.draft }
        set {
            if !isSessionPresented || CoveredSessionFacts(newValue) != CoveredSessionFacts(liveSession.draft) {
                objectWillChange.send()
            }
            liveSession.draft = newValue
        }
    }
    @Published var reviewPromptState = ReviewPromptState.load()
    @Published public var isSessionPresented: Bool = false
    public private(set) var isSceneBackgrounded = false
    @Published public var isOnboardingCompleted: Bool
    /// Seen tours, previews and tips; a local preference outside backups and cloud sync.
    @Published public private(set) var tourProgress: TourProgress
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
        get { ThemeManager.shared.selectedThemeId }
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
    /// Drop, Rest-pause and Partials chips in session; history keeps showing logged techniques when off.
    @Published public var showIntensityTechniques: Bool
    @Published public var suggestSharing: Bool
    @Published public var socialShareRequest: SocialShareRequest?
    var socialPreferences = SocialCardPreferences.shared
    /// Opt-in joint-stress rating after an exercise's working sets (docs/design/body-and-joint-journal.md).
    @Published public var jointStressRatings: Bool
    /// Opt-in reps in reserve on each completed working set (docs/adaptive-training.md#phase-a-effort-logging-free).
    @Published public var repsInReserve: Bool
    /// How effort reads: reps in reserve or RPE. Stored values are always RIR.
    @Published public var effortScale: SetEffort.Scale
    /// Starts the Apple Watch app with each workout and records it in Apple Health there (docs/apple-watch.md).
    @Published public var recordWatchWorkouts: Bool
    /// Reference day tiles are the default; switching off retains the optional Calm material.
    @Published public var homeGlowTiles: Bool
    /// Progress calendar style: lit tiles by default; switching off restores the classic satin pills.
    @Published public var historyCalendarTiles: Bool
    /// Compact session exercise strip; a local layout choice outside backups and cloud sync.
    @Published public var sessionStripCollapsed: Bool
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
    /// Pound plates are kept apart so a pound gym never changes the kilogram inventory or its progression step.
    @Published public var availablePlatesLbs: [Double]
    /// Smart Progression load steps in each unit; the bar step comes from that unit's smallest plate and the bar.
    @Published public var dumbbellStepKg: Double
    @Published public var dumbbellStepLbs: Double
    @Published public var machineStepKg: Double
    @Published public var machineStepLbs: Double
    public var progressionLoadSteps: ProgressionLoadSteps {
        ProgressionLoadSteps.from(dumbbellKg: dumbbellStepKg, dumbbellLbs: dumbbellStepLbs,
                                  machineKg: machineStepKg, machineLbs: machineStepLbs, platesKg: availablePlatesKg,
                                  platesLbs: availablePlatesLbs, barType: barType)
    }
    /// The notice on screen. It expires after its duration, so a screen opened later (the next workout) does not
    /// show an old notice again.
    @Published public var currentToast: ToastItem? {
        didSet {
            guard let item = currentToast, item.id != oldValue?.id else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + item.duration + 0.5) { [weak self] in
                if self?.currentToast?.id == item.id { self?.currentToast = nil }
            }
        }
    }
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
        self.showIntensityTechniques = UserDefaults.standard.object(forKey: showIntensityTechniquesKey) as? Bool ?? true
        self.suggestSharing = UserDefaults.standard.object(forKey: "suggest_sharing") as? Bool ?? true
        self.jointStressRatings = UserDefaults.standard.object(forKey: jointStressRatingsKey) as? Bool ?? false
        self.repsInReserve = UserDefaults.standard.object(forKey: repsInReserveKey) as? Bool ?? false
        self.effortScale = (UserDefaults.standard.string(forKey: effortScaleKey)).flatMap(SetEffort.Scale.init(rawValue:)) ?? .rir
        self.recordWatchWorkouts = UserDefaults.standard.object(forKey: recordWatchWorkoutsKey) as? Bool ?? true
        self.homeGlowTiles = UserDefaults.standard.object(forKey: homeGlowTilesKey) as? Bool ?? true
        self.historyCalendarTiles = UserDefaults.standard.object(forKey: historyCalendarTilesKey) as? Bool ?? true
        self.sessionStripCollapsed = UserDefaults.standard.bool(forKey: sessionStripCollapsedKey)
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
        let savedPlates = UserDefaults.standard.array(forKey: availablePlatesKey) as? [Double] ?? WarmupPlateEngine.defaultPlatesKg
        if let savedLbs = UserDefaults.standard.array(forKey: availablePlatesLbsKey) as? [Double] {
            self.availablePlatesKg = savedPlates
            self.availablePlatesLbs = savedLbs
        } else if savedPlates.contains(45.0) {
            // Earlier builds saved pound plates (a 45 is never a kilogram plate) under the kilogram key.
            self.availablePlatesKg = WarmupPlateEngine.defaultPlatesKg
            self.availablePlatesLbs = savedPlates
        } else {
            self.availablePlatesKg = savedPlates
            self.availablePlatesLbs = WarmupPlateEngine.defaultPlatesLbs
        }
        func savedStep(_ key: String, _ fallback: Double) -> Double {
            UserDefaults.standard.object(forKey: key) != nil ? UserDefaults.standard.double(forKey: key) : fallback
        }
        self.dumbbellStepKg = savedStep(Self.dumbbellStepKgKey, ProgressionLoadSteps.defaultDumbbellKg)
        self.dumbbellStepLbs = savedStep(Self.dumbbellStepLbsKey, ProgressionLoadSteps.defaultDumbbellLbs)
        self.machineStepKg = savedStep(Self.machineStepKgKey, ProgressionLoadSteps.defaultMachineKg)
        self.machineStepLbs = savedStep(Self.machineStepLbsKey, ProgressionLoadSteps.defaultMachineLbs)
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
        // Plans added after the v9 refresh arrive once each; markers wait for a successful save below.
        let pendingStarterAdditions = loaded.canPersist ? Self.starterAdditions.filter { !UserDefaults.standard.bool(forKey: $0.key) } : []
        if !pendingStarterAdditions.isEmpty {
            let bundled = Self.loadBundledStarterPrograms()
            for addition in pendingStarterAdditions {
                loadedState.programs = Self.addingMissingStarterPrograms(loadedState.programs, bundled: bundled, ids: addition.ids)
            }
        }
        // Later starter muscle tags reach saved copies once, only where the user kept the original tags.
        var starterMuscleTagsReady = false
        if loaded.canPersist && !UserDefaults.standard.bool(forKey: Self.starterMuscleTagsKey) {
            let bundled = Self.loadBundledStarterPrograms()
            if bundled.count == Self.starterProgramFiles.count {
                loadedState.programs = Self.addingNewStarterMuscleTags(loadedState.programs, bundled: bundled)
                starterMuscleTagsReady = true
            }
        }

        let hasCompleted = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        let hasExistingData = loaded.hasSavedState || UserDefaults.standard.object(forKey: stateKey) != nil || UserDefaults.standard.object(forKey: activeSessionKey) != nil || !loadedState.history.isEmpty
        // Only migrate installs that predate the flag. Automatically saved starter
        // data must not turn an unfinished first launch into completed setup.
        let completed = UserDefaults.standard.object(forKey: onboardingCompletedKey) == nil ? hasExistingData : hasCompleted
        UserDefaults.standard.set(completed, forKey: onboardingCompletedKey)
        self.isOnboardingCompleted = completed
        // Installs that finished setup before tours existed skip the screen tours and tips.
        if UserDefaults.standard.object(forKey: Self.tourStateVersionKey) == nil {
            Self.saveTourProgress(completed ? TourProgress().returningUser() : TourProgress())
        }
        self.tourProgress = Self.loadTourProgress()
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
        // A relaunch keeps the workout clock and rest deadline running, matching Android.
        let restoredDraft = activeDraft?.clearingEndedRest(nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        self.activeSession = restoredDraft
        if let restoredDraft { self.saveActiveSession(restoredDraft) }
        self.isSessionPresented = false
        self.selectedWorkoutId = nil
        if let targetView = ProcessInfo.processInfo.environment["INITIAL_VIEW"], targetView == "history" {
            self.currentView = .history
        }

        // Auto-archive stale session if from previous day or > 12 hours old
        self.checkAndArchiveStaleSession()
        self.refreshCatalogue()
        if self.saveState(self.state) {
            for addition in pendingStarterAdditions { UserDefaults.standard.set(true, forKey: addition.key) }
            if starterMuscleTagsReady { UserDefaults.standard.set(true, forKey: Self.starterMuscleTagsKey) }
        }
        if !persistenceEnabled { showErrorNotice(LanguageManager.t("notice.storageFailed")) }

        // Sync sound preferences
        $soundEnabled
            .sink { [soundKey] in UserDefaults.standard.set($0, forKey: soundKey) }
            .store(in: &cancellables)

        // The emitted values already include an in-progress rest restored at launch.
        Publishers.CombineLatest(liveSession.$draft, $soundEnabled)
            .sink { draft, soundEnabled in
                RestAlertScheduler.shared.update(for: draft, soundEnabled: soundEnabled)
                DispatchQueue.main.async { RestLiveActivityCoordinator.shared.sync(draft) }
            }
            .store(in: &cancellables)
        $isSessionPresented
            .sink { RestAlertScheduler.shared.isWorkoutVisible = $0 }
            .store(in: &cancellables)

        $defaultRestSeconds
            .sink { [defaultRestKey] in UserDefaults.standard.set($0, forKey: defaultRestKey) }
            .store(in: &cancellables)

        $prefillNextSet
            .sink { [prefillNextSetKey] in UserDefaults.standard.set($0, forKey: prefillNextSetKey) }
            .store(in: &cancellables)

        $showIntensityTechniques
            .dropFirst()
            .sink { [showIntensityTechniquesKey] in UserDefaults.standard.set($0, forKey: showIntensityTechniquesKey) }
            .store(in: &cancellables)

        $suggestSharing.dropFirst().sink { UserDefaults.standard.set($0, forKey: "suggest_sharing") }.store(in: &cancellables)
        $jointStressRatings
            .dropFirst()
            .sink { [jointStressRatingsKey] in UserDefaults.standard.set($0, forKey: jointStressRatingsKey) }
            .store(in: &cancellables)
        $repsInReserve
            .dropFirst()
            .sink { [repsInReserveKey] in UserDefaults.standard.set($0, forKey: repsInReserveKey) }
            .store(in: &cancellables)
        $effortScale
            .dropFirst()
            .sink { [effortScaleKey] in UserDefaults.standard.set($0.rawValue, forKey: effortScaleKey) }
            .store(in: &cancellables)
        $recordWatchWorkouts
            .dropFirst()
            .sink { [recordWatchWorkoutsKey] in UserDefaults.standard.set($0, forKey: recordWatchWorkoutsKey) }
            .store(in: &cancellables)

        $homeGlowTiles
            .sink { [homeGlowTilesKey] in UserDefaults.standard.set($0, forKey: homeGlowTilesKey) }
            .store(in: &cancellables)

        $historyCalendarTiles
            .dropFirst()
            .sink { [historyCalendarTilesKey] in UserDefaults.standard.set($0, forKey: historyCalendarTilesKey) }
            .store(in: &cancellables)

        $sessionStripCollapsed
            .dropFirst()
            .sink { [sessionStripCollapsedKey] in UserDefaults.standard.set($0, forKey: sessionStripCollapsedKey) }
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

        $availablePlatesLbs
            .sink { [availablePlatesLbsKey] in UserDefaults.standard.set($0, forKey: availablePlatesLbsKey) }
            .store(in: &cancellables)

        for (publisher, key) in [($dumbbellStepKg, Self.dumbbellStepKgKey), ($dumbbellStepLbs, Self.dumbbellStepLbsKey),
                                 ($machineStepKg, Self.machineStepKgKey), ($machineStepLbs, Self.machineStepLbsKey)] {
            publisher.dropFirst().sink { UserDefaults.standard.set($0, forKey: key) }.store(in: &cancellables)
        }

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
            weightInputUnit: weightUnit,
            effortByExercise: unfinishedRecord.map { WorkoutSessionUtils.restoreEffortFromHistory(workout: sessionWorkout, record: $0) }.flatMap { $0.isEmpty ? nil : $0 },
            jointStressByExercise: unfinishedRecord.map { WorkoutSessionUtils.restoreJointStressFromHistory(workout: sessionWorkout, record: $0) }.flatMap { $0.isEmpty ? nil : $0 },
            note: unfinishedRecord?.note
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

    /// Marks the scene as backgrounded. The rest notification covers a deadline reached
    /// before the scene becomes active again, so the visible workout stops completing rests.
    public func sceneDidEnterBackground() {
        isSceneBackgrounded = true
    }

    public func sceneDidBecomeActive() {
        defer { isSceneBackgrounded = false }
        RestAlertScheduler.shared.clearDelivered()
        guard isSceneBackgrounded, let active = activeSession else { return }
        let settled = active.clearingEndedRest(nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        guard settled != active else { return }
        saveActiveSession(settled)
        self.activeSession = settled
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

    public func updateSetupNote(exerciseId: String, text: String) {
        guard let draft = activeSession else { return }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(text.prefix(10_000))
        var next = state
        if let p = next.programs.firstIndex(where: { $0.id == draft.programId }),
           let w = next.programs[p].workouts.firstIndex(where: { $0.id == draft.workout.id }),
           let e = next.programs[p].workouts[w].exercises.firstIndex(where: { $0.id == exerciseId }) {
            next.programs[p].workouts[w].exercises[e].setupNote = note
            guard saveState(next, durable: true) else { return }
        }
        updateActiveSession { current in
            var copy = current
            if let e = copy.workout.exercises.firstIndex(where: { $0.id == exerciseId }) {
                copy.workout.exercises[e].setupNote = note
            }
            return copy
        }
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
            // Most edits leave the day unchanged; saving would re-encode every program per keystroke.
            guard updatedCal != cal else { return }
            var nextSt = state
            nextSt.calendarHistory = updatedCal
            saveState(nextSt)
        }
    }

    public func setBarType(_ type: BarType) {
        self.barType = type
    }

    /// Saves the inventory for `unit`; plates are in that unit.
    public func setAvailablePlates(_ plates: [Double], unit: WeightUnit) {
        if unit == .lbs { availablePlatesLbs = plates } else { availablePlatesKg = plates }
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

    /// Session-only "Machine taken?" substitute; nil when nothing changed (unknown IDs, or a working set is logged).
    @discardableResult
    public func replaceExercise(exerciseId: String, substituteId: String) -> Exercise? {
        guard let draft = activeSession,
              let original = draft.workout.exercises.first(where: { $0.id == exerciseId }),
              let replacement = ExerciseSwaps.replacement(for: original, substituteId: substituteId,
                  takenIds: Set(draft.workout.exercises.map(\.id))) else { return nil }
        guard draft.replacingExercise(exerciseId, with: replacement) != draft else { return nil }
        updateActiveSession { $0.replacingExercise(exerciseId, with: replacement) }
        return replacement
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

    /// Records or clears the lifter's reps in reserve on a completed working set.
    public func setEffort(exerciseId: String, index: Int, rir: Int?) {
        updateActiveSession { d in
            var copy = d
            guard var sets = copy.setsByExercise[exerciseId], sets.indices.contains(index),
                  rir == nil || SetEffort.canRate(sets[index]) else { return copy }
            sets[index] = SetEffort.rating(sets[index], rir: rir)
            copy.setsByExercise[exerciseId] = sets
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
                isWarmup: false,
                // Warmups above are rebuilt without techniques or effort; working sets keep theirs.
                technique: s.technique,
                partialRepsInput: s.partialRepsInput,
                extensions: s.extensions,
                rir: s.rir
            )
        }
        return warmups + working
    }

    public func abandonActiveSession() {
        if let draft = activeSession {
            let allSets = draft.setsByExercise.values.flatMap { $0 }
            let hasCompleted = allSets.contains { $0.isCompleted }
            let hasNote = !(draft.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Clearing a previously saved note must also replace its historical copy.
            let hadSavedNote = state.history.contains { $0.id == draft.id && $0.note != nil }
            if hasCompleted || hasNote || hadSavedNote {
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

    public func completeActiveSession(_ record: WorkoutSessionRecord, suggestSharingAfterSave: Bool = false) {
        refreshForCurrentDate()
        let wasComplete = state.history.first(where: { $0.id == record.id })?.isComplete == true
        let oldWeek = SocialCards.week(program: activeProgram, completed: state.completed, history: state.history, weekKey: state.currentWeekKey, unit: weightUnit)
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
            workoutSnapshot: record.workoutSnapshot ?? activeSession?.workout, note: record.note ?? activeSession?.note
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
            func adjustIsoDate(_ isoString: String) -> String { Self.movingTimestamp(isoString, to: targetDay) }

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
                workoutSnapshot: finalRecord.workoutSnapshot, note: finalRecord.note
            )
        }()

        let hasSets = finalRecord.totalCompletedSets > 0 || finalRecord.exerciseLogs.contains { log in
            log.sets.contains { ($0.reps ?? 0) > 0 || ($0.weightKg ?? 0) > 0 }
        }
        let hasNote = !(finalRecord.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var newHistory = state.history
        newHistory.removeAll { $0.id == adjustedRecord.id }
        // A note is saved session content even before the first completed set.
        if hasSets || hasNote || isComplete { newHistory.insert(adjustedRecord, at: 0) }

        var newCompleted = state.completed
        let key = "\(finalRecord.programId):\(finalRecord.workoutId)"
        if isComplete && PersonalRecordTracker.isRecordInWeek(adjustedRecord, targetWeekKey: state.currentWeekKey)
            && !newCompleted.contains(key) {
            newCompleted.append(key)
        }

        if let draft = activeSession {
            cal = WorkoutCalendar.remove(history: cal, id: "session:\(draft.id)")
        }

        let sessionDateParsed = WorkoutCalendar.parseDate(sessionDate)
        let todayDate = WorkoutCalendar.parseDate(WorkoutCalendar.formatDate(Date())) ?? Date()
        let isPast = (sessionDateParsed.map { $0 < todayDate }) ?? false

        let entryStatus: WorkoutDayStatus?
        if isComplete {
            entryStatus = .completed
        } else if hasSets || hasNote {
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
        autoSyncCloudBackup()

        saveActiveSession(nil)
        self.activeSession = nil
        self.isSessionPresented = false
        if suggestSharingAfterSave { recordReviewWorkoutSaved(adjustedRecord) }

        if suggestSharingAfterSave && suggestSharing && !wasComplete && SocialCards.canSuggest(adjustedRecord) {
            let week = SocialCards.week(program: activeProgram, completed: state.completed, history: state.history, weekKey: state.currentWeekKey, unit: weightUnit)
            if let suggestion = SocialCards.suggested(cards: SocialCards.workout(history: state.history, record: adjustedRecord, unit: weightUnit), week: week, justCompletedWeek: oldWeek == nil && week != nil),
               socialPreferences.beginSuggestion() { socialShareRequest = suggestion }
        }
        if socialShareRequest == nil {
            showNotice(WorkoutSessionUtils.workoutRecordedNotice(finalRecord.totalVolumeKg, completedSets: finalRecord.totalCompletedSets, unit: weightUnit))
        }
    }

    /// Called only after a deliberate summary save has passed its durable write.
    func recordReviewWorkoutSaved(_ record: WorkoutSessionRecord, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        let next = reviewPromptState.recording(record, now: now)
        if next != reviewPromptState, next.persist() { reviewPromptState = next }
    }

    func consumeReviewPrompt(allowed: Bool, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> Bool {
        guard allowed, reviewPromptState.canAttempt(now: now) else { return false }
        let next = reviewPromptState.attempting(now: now)
        guard next.persist() else { return false }
        reviewPromptState = next
        return true
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

    /// A generated program is added durably before setup is acknowledged. Retrying is idempotent.
    @discardableResult
    func saveGeneratedPlan(profile: TrainingProfile, program: Program, completeSetup: Bool) -> Bool {
        guard activeSession == nil else { showErrorNotice(LanguageManager.t("history.finishActiveFirst")); return false }
        do { try ProgramEditing.validate(program) } catch { return false }
        guard !program.workouts.isEmpty, program.workouts.allSatisfy({ !$0.exercises.isEmpty }) else { return false }
        var next = state
        if let existing = next.programs.first(where: { $0.id == program.id }) {
            guard existing == program else { return false }
        } else {
            guard next.programs.count < ProgramEditing.maxPrograms else { return false }
            next.programs.append(program)
        }
        next.activeProgramId = program.id
        guard saveState(refreshCalendarState(next), durable: true) else { return false }
        TrainingSetupStore.saveProfile(profile.normalized())
        if completeSetup { setOnboardingCompleted(true) }
        TrainingSetupStore.clearDraft()
        selectedWorkoutId = nil
        refreshCatalogue()
        return true
    }

    /// Skipping first-launch setup selects Balanced Build when it is still available.
    public func skipSetup() {
        if state.programs.contains(where: { $0.id == Self.skippedSetupProgramId }) {
            var next = state
            next.activeProgramId = Self.skippedSetupProgramId
            if saveState(refreshCalendarState(next), durable: true) {
                selectedWorkoutId = nil
                refreshCatalogue()
            }
        }
        setOnboardingCompleted(true)
    }

    public func setOnboardingCompleted(_ completed: Bool) {
        UserDefaults.standard.set(completed, forKey: onboardingCompletedKey)
        isOnboardingCompleted = completed
    }

    private static let tourSkipCountKey = "tour_skip_count"
    private static let tourExistingUserKey = "tour_existing_user"
    private static let tourStateVersionKey = "tour_state_version"

    private static func loadTourProgress() -> TourProgress {
        let defaults = UserDefaults.standard
        return TourProgress(
            seen: Set(TourId.allCases.filter { defaults.bool(forKey: $0.storageKey) }),
            skipCount: defaults.integer(forKey: tourSkipCountKey),
            existingUser: defaults.bool(forKey: tourExistingUserKey)
        )
    }

    private static func saveTourProgress(_ progress: TourProgress) {
        let defaults = UserDefaults.standard
        for id in TourId.allCases {
            if progress.seen.contains(id) { defaults.set(true, forKey: id.storageKey) } else { defaults.removeObject(forKey: id.storageKey) }
        }
        defaults.set(progress.skipCount, forKey: tourSkipCountKey)
        defaults.set(progress.existingUser, forKey: tourExistingUserKey)
        defaults.set(TourProgress.stateVersion, forKey: tourStateVersionKey)
    }

    public func updateTourProgress(_ transform: (TourProgress) -> TourProgress) {
        let updated = transform(tourProgress)
        guard updated != tourProgress else { return }
        Self.saveTourProgress(updated)
        tourProgress = updated
    }

    /// A backup restored from the welcome step belongs to a returning user: no questions, no screen tours.
    public func completeSetupAfterRestore() {
        updateTourProgress { $0.returningUser() }
        setOnboardingCompleted(true)
    }

    /// Settings → Replay app tour: every tour, preview and tip shows again.
    public func resetTours() {
        updateTourProgress { _ in TourProgress() }
    }

    public func calendarStatuses(today: Date = Date()) -> [String: WorkoutDayStatus] {
        let todayStr = WorkoutCalendar.formatDate(today)
        let curCal = state.calendarHistory ?? WorkoutCalendarHistory(
            nextScheduledDate: todayStr,
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

        // Resolve each record's day once. Scanning all history and entries for every calendar day
        // grew with the cube of history size.
        let entryDates = WorkoutCalendar.entryDates(curCal.entries)
        var recordsByDate: [String: [WorkoutSessionRecord]] = [:]
        for record in state.history {
            guard let date = entryDates["session:\(record.id)"]
                ?? WorkoutCalendar.localDate(from: record.startedAt) ?? WorkoutCalendar.localDate(from: record.completedAt) else { continue }
            recordsByDate[date, default: []].append(record)
        }
        let completionMarkDates = Set(curCal.entries.filter { $0.status == .completed && !$0.id.hasPrefix("session:") }.map(\.date))

        func hasLoggedSets(for dateStr: String) -> Bool {
            if let active = activeSession {
                let activeDate = active.assignedCalendarDate
                    ?? entryDates["session:\(active.id)"]
                    ?? WorkoutCalendar.localDate(from: active.startedAt) ?? todayStr
                if activeDate == dateStr {
                    let allSets = active.setsByExercise.values.flatMap { $0 }
                    if allSets.contains(where: { $0.isCompleted }) { return true }
                }
            }
            return (recordsByDate[dateStr] ?? []).contains { rec in
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
                    ?? entryDates["session:\(active.id)"]
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
                let records = recordsByDate[dateStr] ?? []
                if !completionMarkDates.contains(dateStr) && !records.isEmpty
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
                ?? entryDates["session:\(active.id)"]
                ?? WorkoutCalendar.localDate(from: active.startedAt)
            if performed != nil && performed != origin { origins.insert(origin) }
        }
        for origin in origins where statuses[origin] == .missed { statuses.removeValue(forKey: origin) }

        return statuses
    }

    /// Earlier days this week the Progress calendar marks missed. Home and Plan share it, so a plan built
    /// mid-week starts without red days.
    public func missedDaysThisWeek(now: Date = Date()) -> Set<Int> {
        WorkoutCalendar.missedWeekdays(statuses: calendarStatuses(today: now), today: now)
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
            nextScheduledDate: todayStr,
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

        public init(format: String? = "form.program", schemaVersion: Int? = 7, program: Program) {
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
                return "Unsupported program schemaVersion: \(v). Supported versions are 1–7."
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

    /// Video links are saved on program exercises; a library-only exercise has nowhere to keep them.
    public func isExerciseInAnyProgram(named exerciseName: String) -> Bool {
        let key = exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
        return !key.isEmpty && state.programs.contains { program in
            program.workouts.contains { $0.exercises.contains { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key } }
        }
    }

    /// Returns false, changing nothing, when no program contains the exercise:
    /// adding it would change that workout's plan.
    @discardableResult
    public func setExerciseVideos(exerciseName: String, videoUrls: [String]) -> Bool {
        let key = exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
        if key.isEmpty { return false }

        guard let cleanUrls = YouTubeVideo.validatedLinks(videoUrls) else {
            noticeMessage = LanguageManager.t("video.youtubeOnly")
            return false
        }

        var matched = false
        let updatedPrograms = state.programs.map { program in
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

        guard matched else {
            showErrorNotice(LanguageManager.t("video.addToProgramFirst"))
            return false
        }

        var newState = state
        newState.programs = updatedPrograms
        guard saveState(newState) else { return false }
        refreshCatalogue()
        showNotice(LanguageManager.t("notice.videosUpdated", ["name": exerciseName]))
        return true
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

    /// The same local time of day on `day`, as an ISO timestamp; unparseable input is returned unchanged.
    static func movingTimestamp(_ isoString: String, to day: Date, timeZone: TimeZone = .current) -> String {
        let cal = Calendar(identifier: .gregorian)
        let target = cal.dateComponents(in: timeZone, from: day)
        guard let original = WorkoutCalendar.parseIsoTimestamp(isoString) else { return isoString }
        var components = cal.dateComponents(in: timeZone, from: original)
        components.year = target.year
        components.month = target.month
        components.day = target.day
        guard let moved = cal.date(from: components) else { return isoString }
        return ISO8601DateFormatter().string(from: moved)
    }

    /// Android keeps real timestamps and a separate performed date for a session moved to another day.
    /// iOS saves that session on its day, as completion does here, so restored history matches.
    static func aligningToPerformedDate(_ record: WorkoutSessionRecord, timeZone: TimeZone = .current) -> WorkoutSessionRecord {
        guard let performed = record.performedDate, let day = WorkoutCalendar.parseDate(performed, timeZone: timeZone),
              WorkoutCalendar.localDate(from: record.startedAt, timeZone: timeZone) != performed else { return record }
        var aligned = record
        aligned.startedAt = movingTimestamp(record.startedAt, to: day, timeZone: timeZone)
        aligned.completedAt = movingTimestamp(record.completedAt, to: day, timeZone: timeZone)
        return aligned
    }

    func flushPendingState() {
        do { try statePersistence.flush() }
        catch { showErrorNotice(LanguageManager.t("notice.storageFailed")) }
    }

    /// Mirrors a full backup when Cloud Backup is on, so a restore brings back the latest workouts and unit.
    private func autoSyncCloudBackup() {
        guard ProAccessManager.shared.isFeatureUnlocked(.cloudBackup) else { return }
        // Encoding all history grows with use; keep it off the tap.
        let document = FullBackupDocument(state: state, weightUnit: weightUnit)
        DispatchQueue.global(qos: .utility).async {
            guard let json = Self.encodeBackup(document) else { return }
            CloudMirrorManager.shared.autoSync(backupJson: json)
        }
    }

    /// Rates or clears one exercise of a saved workout from History (docs/design/body-and-joint-journal.md). The live
    /// workout's record is left alone: its draft owns the rating and would overwrite it on finish.
    @discardableResult
    public func setHistoryJointStress(recordId: String, logIndex: Int, rating: JointStress?) -> Bool {
        guard activeSession?.id != recordId,
              let index = state.history.firstIndex(where: { $0.id == recordId }),
              let updated = JointJournal.rated(state.history[index], logIndex: logIndex, rating: rating) else { return false }
        guard updated != state.history[index] else { return true }
        var next = state
        next.history[index] = updated
        guard saveState(next, durable: true) else { return false }
        autoSyncCloudBackup()
        return true
    }

    /// Adds or replaces the body-log entry for its date (docs/design/body-and-joint-journal.md).
    @discardableResult
    public func saveBodyEntry(_ entry: BodyEntry, now: Date = Date()) -> Bool {
        entry.hasValue && applyBodyEdit(date: entry.date, stored: entry, hideHealth: false, now: now)
    }

    /// Replaces or removes a date's typed entry and can hide its Apple Health weigh-in
    /// (docs/design/body-and-joint-journal.md#merge-rules). Only typed values and hidden dates are stored.
    @discardableResult
    public func applyBodyEdit(date: String, stored: BodyEntry?, hideHealth: Bool, now: Date = Date()) -> Bool {
        if let stored {
            guard stored.date == date, let day = BodyDay.number(date), let todayNumber = BodyDay.number(BodyDay.today(now)),
                  day <= todayNumber, stored.hasValue,
                  BodyMetric.allCases.allSatisfy({ metric in stored.value(metric).map { metric.canonicalRange.contains($0) } ?? true })
            else { return false }
        }
        let edit = BodyLog.applyEdit(state.bodyEntries ?? [], hidden: state.hiddenHealthWeighIns ?? [], date: date,
                                     stored: stored, hideHealth: hideHealth)
        var next = state
        next.bodyEntries = edit.entries.isEmpty ? nil : edit.entries
        next.hiddenHealthWeighIns = edit.hidden.isEmpty ? nil : edit.hidden
        guard saveState(next, now: now, durable: true) else { return false }
        autoSyncCloudBackup()
        return true
    }

    /// Deletes the date's typed entry; `hideHealth` also hides its Apple Health weigh-in.
    @discardableResult
    public func deleteBodyEntry(date: String, hideHealth: Bool = false) -> Bool {
        applyBodyEdit(date: date, stored: nil, hideHealth: hideHealth)
    }

    /// Any logged load means a unit switch rounds converted weights, so Settings asks first.
    /// A fresh install, or one with only bodyweight sets, switches freely.
    public var hasRecordedLoads: Bool {
        let loaded: (Double?) -> Bool = { ($0 ?? 0) > 0 }
        return state.history.contains { $0.exerciseLogs.contains { $0.sets.contains { loaded($0.weightKg) } } }
            || activeSession?.setsByExercise.values.contains { $0.contains { loaded($0.weightKg) } } == true
    }

    /// The Settings unit switch. The observer rebases a live workout; the cloud copy picks up the new unit
    /// now rather than after the next finished workout.
    public func changeWeightUnit(to unit: WeightUnit) {
        guard unit != weightUnit else { return }
        weightUnit = unit
        autoSyncCloudBackup()
    }

    public func exportBackupJson() -> String {
        refreshForCurrentDate()
        return Self.encodeBackup(FullBackupDocument(state: state, weightUnit: weightUnit)) ?? "{}"
    }

    /// Snapshots on the main thread and encodes on a utility queue, since the backup holds all history.
    @MainActor
    public func exportBackupJsonAsync() async -> String {
        refreshForCurrentDate()
        let document = FullBackupDocument(state: state, weightUnit: weightUnit)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.encodeBackup(document) ?? "{}")
            }
        }
    }

    static func encodeBackup(_ document: FullBackupDocument) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return (try? encoder.encode(document)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A decoded, sanitized full backup. Preparing one never touches the store.
    struct PreparedBackup {
        let state: StoredAppState
        let weightUnit: WeightUnit?
        let earliestMonth: String?
    }

    /// Decodes, sanitizes and date-aligns a full backup. It reads no store state, so it can run off the main thread.
    static func prepareBackup(_ jsonString: String) -> PreparedBackup? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        do {
            let backup = try JSONDecoder().decode(FullBackupDocument.self, from: data)
            var restored = backup.state
            restored.history = restored.history.map { aligningToPerformedDate($0) }
            let earliest = WorkoutCalendar.earliestWorkoutMonth(history: backup.state.calendarHistory, sessions: backup.state.history)
            return PreparedBackup(state: restored, weightUnit: backup.weightUnit, earliestMonth: earliest)
        } catch {
            print("Failed to restore backup: \(error)")
            return nil
        }
    }

    @discardableResult
    public func restoreBackupJson(_ jsonString: String) -> Bool {
        guard let backup = Self.prepareBackup(jsonString) else { return false }
        return applyBackup(backup)
    }

    /// Decodes on a background queue, since the backup holds all history, then applies on the main thread.
    /// A rejected backup, or a task cancelled while decoding, changes nothing.
    @MainActor
    public func restoreBackupJsonAsync(_ jsonString: String, decodeQueue: DispatchQueue = .global(qos: .userInitiated)) async -> Bool {
        let backup = await withCheckedContinuation { continuation in
            decodeQueue.async { continuation.resume(returning: Self.prepareBackup(jsonString)) }
        }
        guard let backup, !Task.isCancelled else { return false }
        return applyBackup(backup)
    }

    private func applyBackup(_ backup: PreparedBackup) -> Bool {
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
        if let earliest = backup.earliestMonth { updateCalendarStartMonthIfEarlier(earliest) }
        return true
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
        // A draft from a newer app may hold fields this build would drop.
        return (try? JSONDecoder().decode(ActiveSessionDraft.self, from: data)).flatMap {
            $0.schemaVersion <= ActiveSessionDraft.currentSchemaVersion ? $0 : nil
        }
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
                if !defaults.bool(forKey: "seeded_starters_v9"), bundled.count == starterProgramFiles.count {
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
                        schemaVersion: StoredAppState.currentSchemaVersion,
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
            schemaVersion: StoredAppState.currentSchemaVersion,
            programs: bundled,
            activeProgramId: activeId,
            completed: [],
            currentWeekKey: currentWeekIsoKeyStatic(),
            weeklyArchives: [],
            history: [],
            calendarHistory: nil
        )
        if bundled.count == starterProgramFiles.count {
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

    static let starterProgramFiles = [
        "01_aesthetic_hypertrophy",
        "02_powerbuilding_strength",
        "03_classic_ppl",
        "04_full_body_classic",
        "05_home_forge_dumbbells",
        "06_athletic_performance",
        "07_upper_lower",
        "08_machine_foundation",
        "09_bodyweight_base",
        "10_bar_floor_calisthenics",
        "11_essentials_two_day"
    ]
    static let homeStarterProgramIds: Set<String> = ["bodyweight-base", "bar-floor-calisthenics"]
    /// Skipping setup starts on this general four-day gym plan rather than the first-listed starter.
    static let skippedSetupProgramId = "upper-lower-balanced"
    /// Plans added after the v9 refresh, oldest first. Each marker adds its plans once, so a
    /// plan the user deleted later is never re-added by a newer marker.
    static let starterAdditions: [(key: String, ids: Set<String>)] = [
        ("seeded_starters_v10", homeStarterProgramIds),
        ("seeded_starters_v11", ["essentials-2-day"]),
    ]

    static let starterMuscleTagsKey = "starter_muscle_tags_v1"
    /// Muscle IDs added to starter workout tags after the workouts first shipped.
    static let addedStarterMuscleTags: Set<String> = ["lower-back", "forearms", "adductors", "tibialis"]

    /// Adds the later muscle tags to saved starter workouts whose tags still equal the earlier
    /// bundled tags. A workout whose tags the user edited keeps them unchanged.
    public static func addingNewStarterMuscleTags(_ existing: [Program], bundled: [Program]) -> [Program] {
        var bundledTags: [String: [String]] = [:]
        for program in bundled {
            for workout in program.workouts { bundledTags["\(program.id)/\(workout.id)"] = workout.targetMuscles }
        }
        return existing.map { program in
            var program = program
            program.workouts = program.workouts.map { workout in
                guard let tags = bundledTags["\(program.id)/\(workout.id)"] else { return workout }
                let earlier = tags.filter { !addedStarterMuscleTags.contains($0) }
                guard tags != earlier, workout.targetMuscles == earlier else { return workout }
                var workout = workout
                workout.targetMuscles = tags
                return workout
            }
            return program
        }
    }

    /// Adds newly bundled plans once without replacing or reordering anything the user has.
    /// An emptied library stays empty, matching the rule that deleting every program never recreates starters.
    public static func addingMissingStarterPrograms(_ existing: [Program], bundled: [Program], ids: Set<String>) -> [Program] {
        guard !existing.isEmpty else { return existing }
        var result = existing
        for program in bundled where ids.contains(program.id) && !result.contains(where: { $0.id == program.id }) {
            guard result.count < ProgramEditing.maxPrograms else { break }
            result.append(program)
        }
        return result
    }

    public static func loadBundledStarterPrograms() -> [Program] {
        var programs: [Program] = []

        for name in starterProgramFiles {
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
/// Unchecked Sendable: an immutable snapshot whose state holds only structs, enums and collections of them.
struct FullBackupDocument: Codable, @unchecked Sendable {
    let state: StoredAppState
    let weightUnit: WeightUnit?
    private enum MetadataKeys: String, CodingKey { case weightUnit }

    init(state: StoredAppState, weightUnit: WeightUnit) {
        var current = state
        current.schemaVersion = StoredAppState.currentSchemaVersion
        self.state = current
        self.weightUnit = weightUnit
    }

    init(from decoder: Decoder) throws {
        let decoded = try StoredAppState(from: decoder)
        guard decoded.schemaVersion <= StoredAppState.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Backup was created by a newer app version"))
        }
        if let problem = BackupSanitizer.intensityProblem(in: decoded.history) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Backup contains an invalid intensity set (\(problem))"))
        }
        if let problem = BackupSanitizer.effortProblem(in: decoded.history) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Backup contains an invalid set effort (\(problem))"))
        }
        state = BackupSanitizer.sanitize(decoded)
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

/// Full-backup restore bounds, following Android's StoredDataSanitizer. A corrupt or crafted
/// file must not persist numbers that later trap in arithmetic or presentation, or identities
/// that collide; values a real backup can hold pass through unchanged.
enum BackupSanitizer {
    static let maxPrograms = 100
    static let maxArchives = 520
    static let maxHistoryRecords = 10_000
    static let maxLogsPerSession = 100
    /// Planned sets follow the editor and session range. Like Android, a value outside it falls back to the
    /// prescription's count, so a restored plan stays editable and matches the sets a session starts with.
    static let plannedSets = 1...10
    /// Numbered and logged sets, which a session can extend beyond its plan.
    static let maxSetsPerExercise = 100
    static let maxSessionSeconds = 7 * 24 * 60 * 60
    static let maxSessionSets = 10_000
    static let maxSessionVolumeKg = 100_000_000.0
    static let maxSetWeightKg = 9_999.0

    static func sanitize(_ state: StoredAppState) -> StoredAppState {
        var clean = state
        var programIds = Set<String>()
        clean.programs = state.programs.prefix(maxPrograms).map { program in
            var copy = program
            copy.id = unique(program.id, in: &programIds)
            var workoutIds = Set<String>()
            copy.workouts = program.workouts.map { sanitize($0, ids: &workoutIds) }
            return copy
        }
        var weekKeys = Set<String>()
        clean.weeklyArchives = Array(state.weeklyArchives.filter { weekKeys.insert($0.weekKey).inserted }.prefix(maxArchives))
        var sessionIds = Set<String>()
        clean.history = state.history.filter { sessionIds.insert($0.id).inserted }.prefix(maxHistoryRecords).map(sanitize)
        let body = BodyLog.sanitize(state.bodyEntries, today: BodyDay.today())
        clean.bodyEntries = body.isEmpty ? nil : body
        let hidden = BodyLog.sanitizeHidden(state.hiddenHealthWeighIns, today: BodyDay.today())
        clean.hiddenHealthWeighIns = hidden.isEmpty ? nil : hidden
        return clean
    }

    private static func sanitize(_ workout: Workout, ids: inout Set<String>) -> Workout {
        var copy = workout
        copy.id = unique(workout.id, in: &ids)
        copy.day = clamped(workout.day, 1...7)
        var exerciseIds = Set<String>()
        copy.exercises = workout.exercises.map { exercise in
            var exercise = exercise
            exercise.id = unique(exercise.id, in: &exerciseIds)
            let prescription = exercise.prescription
            exercise.sets = exercise.sets.map { plannedSets.contains($0) ? $0 : WorkoutSessionUtils.initialSetCount(prescription: prescription) }
            exercise.setupNote = exercise.setupNote.map { String($0.prefix(10_000)) }
            exercise.restSeconds = exercise.restSeconds.map { clamped($0, 0...900) }
            return exercise
        }
        copy.exercises = Supersets.normalized(copy.exercises)
        return copy
    }

    private static func sanitize(_ record: WorkoutSessionRecord) -> WorkoutSessionRecord {
        var copy = record
        copy.note = record.note.map { String($0.prefix(10_000)) }
        copy.durationSeconds = clamped(record.durationSeconds, 0...maxSessionSeconds)
        copy.totalVolumeKg = clamped(record.totalVolumeKg, 0...maxSessionVolumeKg)
        copy.totalCompletedSets = clamped(record.totalCompletedSets, 0...maxSessionSets)
        copy.exerciseLogs = record.exerciseLogs.prefix(maxLogsPerSession).map { log in
            var log = log
            log.targetSets = log.targetSets.map { clamped($0, 1...maxSetsPerExercise) }
            log.setupNote = log.setupNote.map { String($0.prefix(10_000)) }
            log.jointStress = log.jointStress.flatMap(JointStress.init(rawValue:))?.rawValue
            log.sets = log.sets.prefix(maxSetsPerExercise).map { set in
                SessionSetLog(
                    setNumber: clamped(set.setNumber, 1...maxSetsPerExercise),
                    weightKg: set.weightKg.map { clamped($0, 0...maxSetWeightKg) },
                    reps: set.reps.map { clamped($0, 0...999) },
                    isWarmup: set.isWarmup,
                    // Validated before sanitizing (intensityProblem), so these pass through unchanged.
                    partialReps: set.partialReps,
                    technique: set.technique,
                    extensions: set.extensions,
                    // Backups are validated (effortProblem); stored state drops anything the logger never writes.
                    rir: set.isWarmup ? nil : set.rir.flatMap { SetEffort.rirRange.contains($0) ? $0 : nil }
                )
            }
            return log
        }
        if let snapshot = record.workoutSnapshot {
            var ids = Set<String>()
            copy.workoutSnapshot = sanitize(snapshot, ids: &ids)
        }
        return copy
    }

    /// The first set a logger could never write: unknown technique, misordered drops and the like.
    static func intensityProblem(in history: [WorkoutSessionRecord]) -> String? {
        for record in history {
            for log in record.exerciseLogs {
                let assisted = WorkoutSessionUtils.isAssisted(exerciseId: log.exerciseId, name: log.exerciseName)
                for set in log.sets {
                    if let problem = IntensitySets.restoreError(set, assisted: assisted) { return problem }
                }
            }
        }
        return nil
    }

    /// The first saved effort a logger could never write: out of range or on a warmup.
    static func effortProblem(in history: [WorkoutSessionRecord]) -> String? {
        for record in history {
            for log in record.exerciseLogs {
                for set in log.sets {
                    if let problem = SetEffort.restoreError(set) { return problem }
                }
            }
        }
        return nil
    }

    private static func unique(_ id: String, in used: inout Set<String>) -> String {
        var candidate = id
        while !used.insert(candidate).inserted { candidate = UUID().uuidString }
        return candidate
    }

    private static func clamped<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
