import SwiftUI

public struct TodayView: View {
    @State private var socialRequest: SocialShareRequest?
    @State private var blockSheet: BlockSheet?
    @State private var blockPaywall = false
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject private var proManager = ProAccessManager.shared
    @Environment(\.twoPageLayout) private var twoPageLayout
    var onOpenPrograms: () -> Void
    var onOpenSettings: () -> Void
    var onSelectExercise: (Exercise) -> Void

    public init(
        store: AppStore,
        onOpenPrograms: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSelectExercise: @escaping (Exercise) -> Void
    ) {
        self.store = store
        self.onOpenPrograms = onOpenPrograms
        self.onOpenSettings = onOpenSettings
        self.onSelectExercise = onSelectExercise
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        let workout = store.activeWorkout
        let weeklyMetrics = PersonalRecordTracker.computeWeeklyMetrics(
            program: store.activeProgram,
            completedKeys: store.state.completed,
            history: store.state.history,
            currentWeekKey: store.state.currentWeekKey,
            activeSession: store.activeSession,
            unfinishedKeys: store.unfinishedWorkoutKeys()
        )

        if let twoPageLayout {
            // Open foldable: the week strip and the day's card on the left; weekly progress and the exercises on the right.
            TwoPageSpread(layout: twoPageLayout) {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        daySections
                        Spacer().frame(height: 16)
                    }
                }
                .tourScrollable(proxy)
                }
            } trailing: {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        weekSections(weeklyMetrics: weeklyMetrics)
                        exerciseSection(workout: workout)
                        // A rest day leaves this page short; preview the next training day instead.
                        if workout == nil, let next = nextTrainingWorkout() {
                            WorkoutExercisePreview(store: store, workout: next, registersTourTargets: false,
                                                   onSelectExercise: onSelectExercise)
                        }
                        Spacer().frame(height: 16)
                    }
                    .padding(.top, 10)
                }
                .tourScrollable(proxy)
                }
            }
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    daySections
                    weekSections(weeklyMetrics: weeklyMetrics)

                    // Exercise list preview
                    exerciseSection(workout: workout)

                    Spacer().frame(height: 16)
                }
            }
            .tourScrollable(proxy)
            }
        }
    }

    @ViewBuilder
    private var daySections: some View {
        // Home header with the current week's date range
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LanguageManager.t("nav.home"))
                    .font(.app(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.text)

                Text(formattedWeekRange())
                    .font(.app(size: 12))
                    .foregroundStyle(AppColors.muted)
            }

            Spacer()

            FormHeaderIconButton(
                icon: "gearshape.fill",
                contentDescription: LanguageManager.t("settings.title"),
                onClick: onOpenSettings
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)

        // 7-day strip
        WeekStripView(store: store) { workoutId in
            if store.selectedWorkoutId == workoutId {
                store.selectedWorkoutId = nil
            } else {
                store.selectedWorkoutId = workoutId
            }
        }

        // Today card (Workout or Rest day)
        HomeWorkoutHero(store: store, workout: store.activeWorkout)
    }

    @ViewBuilder
    private func weekSections(weeklyMetrics: WeeklyGoalProgressMetrics) -> some View {
        // Weekly goal progress card
        WeeklyGoalProgressCard(
            metrics: weeklyMetrics,
            weightUnit: store.weightUnit,
            isPageVisible: store.currentView == .today && !store.isSessionPresented
        )
        .tourTarget("home.week", cornerRadius: 22)
        .padding(.horizontal, 20)

        // Training block (docs/training-blocks.md): a Premium coach feature around the active program.
        TrainingBlockCard(
            state: BlockCardState.of(block: store.state.trainingBlock, activeProgram: store.activeProgram, programs: store.state.programs,
                                     weekKey: store.state.currentWeekKey, unlocked: proManager.isFeatureUnlocked(.autoProgression)),
            scale: store.effortScale,
            onStart: { blockSheet = .setup },
            onReview: { blockSheet = .week($0) },
            onSummary: { blockSheet = .summary },
            onEnd: { store.endTrainingBlock() },
            onLocked: { blockPaywall = true }
        )
        .padding(.horizontal, 20)
        .sheet(item: $blockSheet) { sheet in blockSheetView(sheet) }
        .sheet(isPresented: $blockPaywall) { ProPaywallSheet(feature: .autoProgression, onDismiss: { blockPaywall = false }) }
        .onAppear { store.refreshTrainingBlock() }

        if let card = SocialCards.week(program: store.activeProgram, completed: store.state.completed, history: store.state.history, weekKey: store.state.currentWeekKey, unit: store.weightUnit) {
            Button { socialRequest = SocialShareRequest(cards: [card]) } label: {
                Text(LanguageManager.t("social.week") + " · " + LanguageManager.t("social.share"))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.bordered).tint(AppColors.accent).padding(.horizontal, 20)
                .accessibilityIdentifier("share-completed-week")
                .sheet(item: $socialRequest) { request in SocialCardComposer(request: request) { socialRequest = nil } }
        }
    }

    @ViewBuilder
    private func exerciseSection(workout: Workout?) -> some View {
        if let workout = workout, !workout.exercises.isEmpty {
            // In a block week Home lists that week's sets; starting still uses the program workout.
            let block = store.state.trainingBlock
            let week = TrainingBlocks.activeWeek(block, programId: store.activeProgram?.id ?? "", weekKey: store.state.currentWeekKey)
            let shown = block.flatMap { block in week.map { TrainingBlocks.sessionWorkout(block, week: $0, workout: workout) } } ?? workout
            WorkoutExercisePreview(store: store, workout: shown, registersTourTargets: true, onSelectExercise: onSelectExercise)
        }
    }

    @ViewBuilder
    private func blockSheetView(_ sheet: BlockSheet) -> some View {
        let block = store.state.trainingBlock
        let program = block.flatMap { block in store.state.programs.first { $0.id == block.programId } }
        switch sheet {
        case .setup:
            if let active = store.activeProgram {
                TrainingBlockSetupSheet(program: active, scale: store.effortScale, replacesBlock: block != nil,
                                        readinessCheck: $store.readinessCheck) { length, focus, nextWeek in
                    store.startTrainingBlock(length: length, focus: focus, nextWeek: nextWeek)
                    blockSheet = nil
                }
            }
        case .week(let week):
            if let block, let program {
                TrainingBlockWeekSheet(block: block, week: week, program: program, scale: store.effortScale) { edits in
                    store.reviewTrainingBlockWeek(week, sets: edits)
                    blockSheet = nil
                }
            }
        case .summary:
            if let block, let program {
                TrainingBlockSummarySheet(block: block, program: program, history: store.state.history, weightUnit: store.weightUnit,
                                          onStartAnother: { blockSheet = .setup },
                                          onDone: { store.endTrainingBlock(); blockSheet = nil })
            }
        }
    }

    /// The first training day after today, wrapping to the start of the week.
    private func nextTrainingWorkout() -> Workout? {
        let today = store.weekCalendar.today + 1
        let training = (store.activeProgram?.workouts ?? [])
            .filter { !$0.exercises.isEmpty }
            .sorted { $0.day < $1.day }
        return training.first { $0.day > today } ?? training.first
    }

    private func formattedWeekRange() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let now = Date()
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let monday = calendar.date(from: comps),
              let sunday = calendar.date(byAdding: .day, value: 6, to: monday) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: monday)) – \(formatter.string(from: sunday))"
    }
}

/// The selected day's hero card with its start/resume action; shared by Home and the open foldable's Plan.
struct HomeWorkoutHero: View {
    @ObservedObject var store: AppStore
    let workout: Workout?
    var showsRestGuidance = true

    var body: some View {
        let program = store.activeProgram
        let workoutKey = workout.map { "\(program?.id ?? ""):\($0.id)" } ?? ""
        let isCompleted = store.state.completed.contains(workoutKey)
        let isAvailable = workout.map { store.canStartWorkout($0) } ?? false
        let availableDay: String? = {
            guard let w = workout, w.day > store.weekCalendar.today + 1 else { return nil }
            return LanguageManager.workoutDays.indices.contains(w.day - 1) ? LanguageManager.workoutDays[w.day - 1] : nil
        }()

        TodayHeroCard(
            workout: workout,
            programId: program?.id,
            todayIndex: store.weekCalendar.today,
            isCompleted: isCompleted,
            isAvailable: isAvailable,
            availableDay: availableDay,
            hasUnfinishedProgress: !isCompleted && (store.activeSession?.workout.id == workout?.id || store.unfinishedWorkoutKeys().contains(workoutKey)),
            missedDays: store.missedDaysThisWeek(),
            onStart: {
                if let w = workout, let p = program {
                    if let active = store.activeSession, active.workout.id == w.id {
                        store.resumeActiveSession()
                    } else {
                        if !store.startActiveSession(programId: p.id, workout: w, allowPast: true) {
                            if store.activeSession != nil {
                                store.showErrorNotice(LanguageManager.t("history.finishActiveFirst"))
                            }
                        }
                    }
                }
            },
            showsRestGuidance: showsRestGuidance
        )
    }
}

/// A workout's exercise rows under the weekday heading. Only Home registers the tour's row targets.
struct WorkoutExercisePreview: View {
    @ObservedObject var store: AppStore
    let workout: Workout
    let registersTourTargets: Bool
    var onSelectExercise: (Exercise) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exerciseHeading(for: workout))
                .font(.app(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                .tourTargetIf(registersTourTargets ? "home.exercises.row.0" : nil,
                              contentInsets: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            VStack(spacing: 8) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                    Button(action: { onSelectExercise(exercise) }) {
                        HStack(spacing: 12) {
                            MovementIcon(
                                exerciseId: exercise.exerciseId,
                                size: 52
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.displayName)
                                    .font(.app(size: 14, weight: .medium))
                                    .lineSpacing(2)
                                    .foregroundStyle(AppColors.text)
                                    .lineLimit(2)

                                Text(exercise.displayPrescription)
                                    .font(.app(size: 12))
                                    .foregroundStyle(AppColors.muted)
                            }

                            Spacer()

                            Text(String(format: "%02d", index + 1))
                                .font(.app(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.muted)
                        }
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .tourTargetIf(registersTourTargets ? "home.exercises.row.\(index + 1)" : nil, cornerRadius: 13)
                }
            }
            .padding(.horizontal, 20)
        }
        .tourTargetIf(registersTourTargets ? "home.exercises" : nil, cornerRadius: 13)
    }

    private func exerciseHeading(for workout: Workout) -> String {
        if workout.day == store.weekCalendar.today + 1 {
            return LanguageManager.t("today.exercises")
        }
        guard LanguageManager.workoutDays.indices.contains(workout.day - 1) else {
            return LanguageManager.t("history.exercises")
        }
        return LanguageManager.t("today.dayExercises", ["day": LanguageManager.workoutDays[workout.day - 1]])
    }
}
