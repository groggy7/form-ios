import SwiftUI
import Combine

public struct ActiveSessionView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    /// Set edits publish here rather than on the store, which would redraw the tabs under this cover.
    @ObservedObject private var liveSession: LiveSession
    let draft: ActiveSessionDraft

    // Event handlers read actual time; ticking display state belongs to child views.
    private var nowEpochMillis: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    @State private var showExitConfirmation: Bool = false
    @State private var showSummary: Bool = false
    @State private var finishedAt: Int64? = nil
    @State private var warningNoticeMessage: String? = nil
    @State private var isWarningVisible: Bool = false
    @State private var celebratoryNoticeMessage: String? = nil
    @State private var isCelebrationVisible: Bool = false
    @State private var inspectingExerciseId: String? = nil
    @State private var sessionSpread: TwoPageLayout?
    @StateObject private var sessionMedia = SessionExerciseMedia()
    @State private var reportingExercise: Exercise? = nil
    @State private var pendingReport: ExerciseIssueReport? = nil
    @State private var showProgressionInfo: Bool = false
    /// Exercises whose mid-workout adjustment the lifter chose to keep: hidden for the rest of this workout.
    @State private var keptAdjustments: Set<String> = []
    @State private var showWarmupPlateSheet: Bool = false
    @State private var warmupModalTab: WarmupPlateTab = .warmupRamp
    @State private var selectedPlateWeight: Double? = nil
    @State private var paywallFeature: ProFeature? = nil
    @State private var openWarmupAfterUnlock = false
    /// The exercise whose locked Replace opened the paywall; buying reopens Replace for it.
    @State private var swapAfterUnlockId: String? = nil
    @State private var openSwapAfterUnlock = false
    @State private var pendingAnomalousSet: PendingAnomalousSet? = nil
    @State private var swappingExercise: Exercise? = nil
    @State private var pendingSwap: (exerciseId: String, substituteId: String)? = nil
    @ObservedObject private var tour = TourController.shared
    @State private var compactHeight = false
    /// While a note's keyboard is up, the exercise strip and navigation make way for a Done bar and a one-line rest.
    @State private var keyboardVisible = false
    /// The session's own number pad replaces the system keyboard for set entry.
    @State private var keypad = SessionKeypad()
    /// The exercise whose notes panel is open.
    @State private var notesOpenFor: String?

    /// Workout tours start only while no sheet, detail or summary covers the exercise screen.
    private var tourIdle: Bool {
        !showSummary && !showExitConfirmation && inspectingExerciseId == nil && reportingExercise == nil &&
            pendingReport == nil && !showProgressionInfo && !showWarmupPlateSheet && paywallFeature == nil &&
            swappingExercise == nil && pendingAnomalousSet == nil
    }
    @ObservedObject private var proManager = ProAccessManager.shared

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public init(store: AppStore, draft: ActiveSessionDraft, keypad: SessionKeypad? = nil) {
        self.store = store
        self.liveSession = store.liveSession
        self.draft = draft
        if let keypad { _keypad = State(initialValue: keypad) }
    }

    private var currentDraft: ActiveSessionDraft {
        // After the workout ends, the closing screen keeps its latest draft rather than the one it opened with.
        liveSession.draft ?? liveSession.lastDraft.flatMap { $0.id == draft.id ? $0 : nil } ?? draft
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        let activeDraft = currentDraft
        let effectiveNow = showSummary ? (finishedAt ?? nowEpochMillis) : nowEpochMillis
        let progress = SessionProgress.from(draft: activeDraft, nowEpochMillis: effectiveNow)
        let exercises = activeDraft.workout.exercises
        let currentIndex = min(max(0, activeDraft.currentExerciseIndex), max(0, exercises.count - 1))
        let currentExercise = exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
        let mediaKey = SessionExerciseMedia.Key(workoutId: activeDraft.workout.id,
            rows: exercises.map { .init(id: $0.id, exerciseId: $0.exerciseId) }, summary: showSummary)
        let currentSets = currentExercise.map { activeDraft.setsByExercise[$0.id] ?? [] } ?? []
        let supportsBarbellWarmup = currentExercise.map {
            WarmupPlateEngine.supportsExercise(equipmentCategory: EquipmentCatalog.shared.categoryId($0.exerciseId))
        } ?? false
        let workingWeightKg = currentSets.filter { !$0.isWarmup }.compactMap { set -> Double? in
            let weight = (WarmupPlateEngine.hasWorkingLoad(set.weightKg) ? set.weightKg : nil)
                ?? Double(set.weightInput.replacingOccurrences(of: ",", with: ".")).map {
                store.weightUnit.toCanonicalKg($0)
            }
            return WarmupPlateEngine.hasWorkingLoad(weight) ? weight : nil
        }.first
        let restTimer = activeDraft.restTimer

        let historyInsights = currentExercise.map {
            store.sessionHistoryInsights.get(exercise: $0, history: store.state.history, unit: store.weightUnit,
                scope: .init(sessionId: activeDraft.id, programId: activeDraft.programId, workoutId: activeDraft.workout.id),
                steps: store.progressionLoadSteps)
        }
        let previousWorkingSets = historyInsights?.previousWorkingSets ?? []

        let ghostTargets: [Int: GhostTarget] = {
            guard let exercise = currentExercise else { return [:] }
            var map: [Int: GhostTarget] = [:]
            var workingIdx = 0
            for (idx, set) in currentSets.enumerated() {
                if !set.isWarmup {
                    let target = WorkoutSessionUtils.computeGhostTarget(
                        previousSets: previousWorkingSets,
                        workingSetIndex: workingIdx,
                        exercise: exercise,
                        unit: store.weightUnit,
                        steps: store.progressionLoadSteps
                    )
                    workingIdx += 1
                    map[idx] = target
                }
            }
            return map
        }()

        // The previous occurrence's exact working position, independently of progression suggestions.
        let previousSetsByIndex: [Int: SessionSetLog] = {
            var map: [Int: SessionSetLog] = [:]
            var workingIdx = 0
            for (idx, set) in currentSets.enumerated() where !set.isWarmup {
                workingIdx += 1
                map[idx] = previousWorkingSets.first { $0.setNumber == workingIdx }
            }
            return map
        }()

        let logbookBeatenSets: [Int: LogbookBeatResult] = {
            var map: [Int: LogbookBeatResult] = [:]
            for (idx, set) in currentSets.enumerated() {
                if set.isCompleted, !set.isWarmup, let target = ghostTargets[idx] {
                    let weightKg = set.weightKg ?? (Double(set.weightInput.replacingOccurrences(of: ",", with: ".")).map { WeightUnit.toCanonicalKg($0, unit: store.weightUnit) } ?? 0.0)
                    let reps = set.completedReps ?? (Int(set.repsInput) ?? 0)
                    if let beat = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: weightKg, loggedReps: reps, target: target) {
                        map[idx] = beat
                    }
                }
            }
            return map
        }()

        let program = store.state.programs.first(where: { $0.id == activeDraft.programId })
            ?? store.state.programs.first(where: { $0.id == store.state.activeProgramId })
        let programName = program?.displayName ?? ""
        let programLabel: String = {
            if !programName.isEmpty && activeDraft.workout.day > 0 {
                return "\(programName) D\(activeDraft.workout.day)"
            } else if !programName.isEmpty {
                return programName
            } else if activeDraft.workout.day > 0 {
                return "D\(activeDraft.workout.day)"
            } else {
                return ""
            }
        }()

        ZStack {
            AppColors.background.ignoresSafeArea()

            if showSummary {
                SessionSummaryView(
                    workoutTitle: activeDraft.workout.title,
                    durationSeconds: progress.durationSeconds,
                    totalCompletedSets: progress.completedSets,
                    totalVolumeKg: progress.volumeKg,
                    exerciseLogs: progress.exerciseLogs,
                    onBack: {
                        showSummary = false
                        finishedAt = nil
                    },
                    onSaveAndClose: {
                        let completedAt = finishedAt ?? Int64(Date().timeIntervalSince1970 * 1000)
                        let record = SessionProgress.from(draft: activeDraft, nowEpochMillis: completedAt)
                            .record(draft: activeDraft, completedAtEpochMillis: completedAt)
                        store.completeActiveSession(record, suggestSharingAfterSave: true)
                    },
                    onDiscard: {
                        showSummary = false
                        finishedAt = nil
                        if progress.hasProgress {
                            showExitConfirmation = true
                        } else {
                            store.abandonActiveSession()
                        }
                    },
                    weightUnit: store.weightUnit,
                    workoutNote: workoutNoteBinding
                )
            } else {
                let sessionColumn = VStack(spacing: 0) {
                    // Top Bar
                    SessionHeader(title: activeDraft.workout.displayTitle(programId: activeDraft.programId),
                        programLabel: programLabel, draft: activeDraft,
                        onExit: {
                            if progress.hasProgress {
                                showExitConfirmation = true
                            } else {
                                store.abandonActiveSession()
                            }
                        },
                        onFinish: presentWorkoutSummary)

                    // The strip stays pinned above the sets, like Android, unless the window is too short for both.
                    // A note's keyboard needs the room more than switching exercises does; the set keypad leaves it.
                    if !compactHeight && !keyboardVisible { exerciseStrip }

                    // Main Content
                    ScrollViewReader { tourProxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            if compactHeight { exerciseStrip }

                            // Current Exercise Card
                            if let exercise = currentExercise {
                                VStack(alignment: .leading, spacing: 12) {
                                    // A substitute replaces the exercise only until one of its working sets is completed.
                                    let setupNote = exercise.setupNote ?? ""
                                    ExerciseTitleRow(name: (Supersets.label(activeDraft.workout, exercise.id).map { "\($0) · " } ?? "") + exercise.displayName,
                                        action: exerciseMenu(for: exercise,
                                            hasNotes: !setupNote.isEmpty || !(activeDraft.note ?? "").isEmpty,
                                            canReplace: !currentSets.contains(where: { $0.isCompleted && !$0.isWarmup })))

                                    if notesOpenFor == exercise.id {
                                        notesPanel(for: exercise)
                                    } else if !setupNote.isEmpty {
                                        // The setup is read before the first set, so a saved one sits under the name.
                                        Button { openNotes(for: exercise) } label: {
                                            Text(setupNote)
                                                .font(.app(size: 13)).foregroundStyle(AppColors.secondaryText)
                                                .multilineTextAlignment(.leading).lineLimit(3)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(LanguageManager.t("notes.setup")): \(setupNote)")
                                        .accessibilityIdentifier("session-setup-note")
                                    }

                                    // A block week sets the effort target, the mid-workout window and the muscle questions.
                                    let block = store.state.trainingBlock.flatMap { $0.id == activeDraft.blockId ? $0 : nil }
                                    let blockWeek = block == nil ? nil : activeDraft.blockWeek
                                    let plannedTarget = blockWeek.flatMap { TrainingBlockRules.target(length: block!.length, week: $0) }
                                    // A lighter day the lifter chose can add one rep in reserve to the week's target.
                                    let blockTarget = Readiness.target(plannedTarget, check: activeDraft.readiness)
                                    let blockDeload = block != nil && blockWeek.map { TrainingBlockRules.isDeload(length: block!.length, week: $0) } == true
                                    let blockQuestions = block == nil ? nil : TrainingBlocks.feedbackPlan(activeDraft.workout)
                                    // Asked before the workout's first working set; it leaves once one is ticked.
                                    if store.readinessCheck && proManager.isFeatureUnlocked(.autoProgression)
                                        && !activeDraft.setsByExercise.values.joined().contains(where: { $0.isCompleted && !$0.isWarmup }) {
                                        ReadinessCard(check: activeDraft.readiness,
                                                      options: Readiness.options(blockTarget: plannedTarget, deload: blockDeload),
                                                      lighterTarget: blockTarget.map { SetEffort.tag($0, scale: store.effortScale) },
                                                      onAnswer: { store.setReadiness($0) }, onChoose: { store.chooseReadiness($0) })
                                    }
                                    if blockDeload {
                                        Text(LanguageManager.t("block.session.deload")).appFont(.footnote).foregroundStyle(AppColors.purple)
                                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                            .accessibilityIdentifier("block-deload-hint")
                                    }
                                    let recommendation = historyInsights?.recommendation
                                    let showsProgressionCard = recommendation != nil && store.showProgressionTargets

                                    if let recommendation, showsProgressionCard {
                                        ProgressionCoachCard(
                                            recommendation: recommendation,
                                            weightUnit: store.weightUnit,
                                            canApplyTarget: !recommendation.applicableTargets(sets: currentSets).isEmpty,
                                            sessionSets: currentSets,
                                            onApplyTarget: {
                                                applyProgressionTargets(recommendation.applicableTargets(sets: currentSets), exerciseId: exercise.id)
                                            },
                                            onOpenInfo: {
                                                showProgressionInfo = true
                                            },
                                            onLockedClick: {
                                                paywallFeature = .autoProgression
                                            },
                                            onDismissLocked: {
                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                    store.showProgressionTargets = false
                                                }
                                            }
                                        )
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                    }

                                    let currentWarmups = currentSets.filter { $0.isWarmup }
                                    let showsWarmupCard = (supportsBarbellWarmup || !currentWarmups.isEmpty) && store.showWarmupCalculator
                                    if showsWarmupCard {
                                        WarmupPlateCard(
                                            warmupSets: currentWarmups,
                                            hasWorkingLoad: workingWeightKg != nil,
                                            supportsBarbellWarmup: supportsBarbellWarmup,
                                            onGenerateWarmup: {
                                                guard workingWeightKg != nil else { return }
                                                warmupModalTab = .warmupRamp
                                                selectedPlateWeight = nil
                                                showWarmupPlateSheet = true
                                            },
                                            onOpenPlates: {
                                                guard workingWeightKg != nil else { return }
                                                warmupModalTab = .plateLoader
                                                selectedPlateWeight = nil
                                                showWarmupPlateSheet = true
                                            },
                                            onClearWarmups: {
                                                store.clearWarmupSets(exerciseId: exercise.id)
                                            },
                                            onLockedClick: {
                                                paywallFeature = .warmupCalculator
                                            },
                                            onDismissLocked: {
                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                    store.showWarmupCalculator = false
                                                }
                                            }
                                        )
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                    }

                                    let isRestActive = (activeDraft.restTimer?.secondsRemaining(nowEpochMillis: nowEpochMillis) ?? 0) > 0
                                    let isRestForCurrentExercise = isRestActive && activeDraft.restTimer?.exerciseName == exercise.name
                                    let workingRows = currentSets.filter { !$0.isWarmup }
                                    let workingSetsDone = !workingRows.isEmpty && workingRows.allSatisfy(\.isCompleted)
                                    let asksEffort = proManager.isFeatureUnlocked(.autoProgression) && store.showProgressionTargets &&
                                        workingSetsDone && ProgressionEngine.parseRepRange(exercise: exercise) != nil
                                    let asksJointStress = store.jointStressRatings && WorkoutSessionUtils.offersJointStressRating(currentSets)
                                    // The first working set's reps in reserve can offer a load step for the rest (Premium coach).
                                    let effortOn = store.repsInReserve || activeDraft.blockId != nil
                                    let loadAdjustment = proManager.isFeatureUnlocked(.autoProgression) && store.showProgressionTargets &&
                                        effortOn && !keptAdjustments.contains(exercise.id) && !blockDeload
                                        ? ProgressionEngine.loadAdjustment(exercise: exercise, sets: currentSets, unit: store.weightUnit,
                                                                           steps: store.progressionLoadSteps,
                                                                           window: blockTarget.map { TrainingBlockRules.window(target: $0) } ?? SetEffort.targetWindow)
                                        : nil
                                    // Soreness is asked before a muscle's first exercise, pump and workload after its last.
                                    let exerciseIndex = activeDraft.workout.exercises.firstIndex { $0.id == exercise.id } ?? -1
                                    let sorenessMuscles = currentSets.contains { $0.isCompleted && !$0.isWarmup } ? []
                                        : blockQuestions?.sorenessBefore[exerciseIndex] ?? []
                                    let pumpMuscles = workingSetsDone ? blockQuestions?.pumpAfter[exerciseIndex] ?? [] : []
                                    if !sorenessMuscles.isEmpty {
                                        BlockFeedbackCard(muscles: sorenessMuscles, answers: activeDraft.muscleFeedback ?? [:], questions: .soreness) {
                                            store.setMuscleFeedback(muscle: $0, feedback: $1)
                                        }
                                    }

                                    SetLoggingTable(
                                        sets: currentSets,
                                        prescription: exercise.displayPrescription,
                                        isRestActive: isRestActive,
                                        isRestForCurrentExercise: isRestForCurrentExercise,
                                        previousSets: previousSetsByIndex,
                                        onUpdateSet: { setIdx, weight, reps in
                                            updateSet(exerciseId: exercise.id, index: setIdx, weight: weight, reps: reps)
                                        },
                                        onToggleCompleteSet: { setIdx in
                                            toggleSet(exercise: exercise, index: setIdx, ghostTarget: ghostTargets[setIdx])
                                        },
                                        onAddSet: {
                                            addSet(exerciseId: exercise.id)
                                        },
                                        onRemoveSet: { setIdx in
                                            removeSet(exerciseId: exercise.id, index: setIdx)
                                        },
                                        onRestWarning: {
                                            showRestWarning()
                                        },
                                        onInspectPlates: supportsBarbellWarmup ? { weightVal in
                                            warmupModalTab = .plateLoader
                                            selectedPlateWeight = weightVal
                                            showWarmupPlateSheet = true
                                        } : nil,
                                        onToggleWarmup: { setIdx in
                                            store.toggleWarmup(exerciseId: exercise.id, index: setIdx)
                                        },
                                        weightUnit: store.weightUnit,
                                        allowsZeroWeight: WorkoutSessionUtils.allowsZeroWeight(exercise),
                                        isAssisted: WorkoutSessionUtils.isAssisted(exercise),
                                        isBodyweight: WorkoutSessionUtils.usesBodyweightResistance(exercise),
                                        logbookBeatenSets: logbookBeatenSets,
                                        intensity: store.showIntensityTechniques ? intensityActions(exercise: exercise, previousSets: previousSetsByIndex) : nil,
                                        effort: effortOn ? EffortActions(scale: store.effortScale) { setIdx, rir in
                                            store.setEffort(exerciseId: exercise.id, index: setIdx, rir: rir)
                                        } : nil,
                                        adjustment: loadAdjustment.map { offer in
                                            AdjustmentSlot(afterIndex: offer.setIndex, content: AnyView(LoadAdjustmentCard(
                                                adjustment: offer, scale: store.effortScale, weightUnit: store.weightUnit,
                                                onUse: { applyProgressionTargets(offer.targets, exerciseId: exercise.id) },
                                                onKeep: { keptAdjustments.insert(exercise.id) })))
                                        },
                                        // The ratings sit right under the last set, where the exercise ends.
                                        prescriptionSuffix: blockDeload ? LanguageManager.t("block.setup.deload")
                                            : blockTarget.map { SetEffort.tag($0, scale: store.effortScale) },
                                        ratings: asksEffort || asksJointStress || !pumpMuscles.isEmpty ? AnyView(VStack(spacing: 8) {
                                            ExerciseRatingsCard(
                                                effort: activeDraft.effortByExercise?[exercise.id].flatMap(ProgressionEffort.init(rawValue:)),
                                                onEffort: asksEffort ? { setEffort($0, exerciseId: exercise.id) } : nil,
                                                jointStress: activeDraft.jointStressByExercise?[exercise.id].flatMap(JointStress.init(rawValue:)),
                                                onJointStress: asksJointStress ? { setJointStress($0, exerciseId: exercise.id) } : nil
                                            )
                                            BlockFeedbackCard(muscles: pumpMuscles, answers: activeDraft.muscleFeedback ?? [:], questions: .pumpAndWorkload) {
                                                store.setMuscleFeedback(muscle: $0, feedback: $1)
                                            }
                                        }) : nil,
                                        keypad: keypad,
                                        weightStep: WorkoutSessionUtils.loadStep(exercise, unit: store.weightUnit, steps: store.progressionLoadSteps),
                                        barbellPlates: WorkoutSessionUtils.usesBarbellPlates(exercise),
                                        warmupToolsUnlocked: proManager.isFeatureUnlocked(.warmupCalculator)
                                    )
                                    .tourTarget("workout.sets", cornerRadius: 12, flags: [store.weightUnit.rawValue])
                                    .padding(.top, showsProgressionCard || showsWarmupCard ? 8 : 0)
                                }
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppColors.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, compactHeight ? 0 : 10)
                        .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // A revealed set keeps 20pt of room above the keypad.
                    .safeAreaPadding(.bottom, keypad.isOpen ? 20 : 0)
                    .tourScrollable(tourProxy)
                    }

                    if keypad.isOpen {
                        // While a set field is selected the keypad takes the navigation's place and a running rest is one line.
                        restBar(restTimer, compact: true)
                        LoggingKeypadView(keypad: keypad)
                    } else if keyboardVisible {
                        restBar(restTimer, compact: true)
                        keyboardBar
                    } else {
                        // Keep exercise navigation outside the scrolling content.
                        HStack(spacing: 10) {
                            Button(action: {
                                if currentIndex > 0 {
                                    sessionMedia.freezeActive()
                                    store.updateActiveSession { d in
                                        var copy = d
                                        copy.currentExerciseIndex = currentIndex - 1
                                        return copy
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(currentIndex > 0 ? AppColors.text : AppColors.muted.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(AppColors.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                    .stroke(AppColors.border, lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(currentIndex <= 0)
                            .accessibilityLabel(LanguageManager.t("session.prevExercise"))

                            Button(action: {
                                if let nextIndex = Supersets.nextIndex(currentDraft) {
                                    sessionMedia.freezeActive()
                                    store.updateActiveSession { d in
                                        var copy = d
                                        copy.currentExerciseIndex = Supersets.nextIndex(d) ?? nextIndex
                                        return copy
                                    }
                                } else {
                                    presentWorkoutSummary()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Text(LanguageManager.t(Supersets.nextIndex(activeDraft) != nil ? "session.nextExercise" : "session.review"))
                                        .font(.app(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.background)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.background)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppColors.accent)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(AppColors.background)

                        restBar(restTimer, compact: false)
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.size.height < 480 } action: { compactHeight = $0 }
                // Beside a vertical bar (iPhone Duo) the header has no status bar above it.
                .verticalBarHeadroom(12)

                // One view, so the hold and its fade span the switch from the single column to the spread.
                ZStack {
                    if let sessionSpread, let currentExercise {
                        // Open foldable: logging on the left; the exercise's demonstration and cues stay open on the right.
                        TwoPageSpread(layout: sessionSpread) {
                            sessionColumn
                        } trailing: {
                            SessionExerciseDetailContent(exercise: currentExercise, media: sessionMedia,
                                                         onReportIssue: { reportIssue(for: currentExercise) })
                                .background(AppColors.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                                .verticalBarHeadroom(20)
                                .id(currentExercise.id)
                        }
                    } else {
                        sessionColumn
                    }
                }
                .holdsUntilFold()
            }

            if isCelebrationVisible, let msg = celebratoryNoticeMessage, !isWarningVisible {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                        Text(msg)
                            .font(.app(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.surfaceRaised)
                            .overlay(Capsule().stroke(AppColors.accent.opacity(0.5), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, restTimer != nil ? 162 : 90)
                }
                .animation(.easeInOut(duration: 0.25), value: isCelebrationVisible)
            }

            if isWarningVisible, let warning = warningNoticeMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.danger)
                        Text(warning)
                            .font(.app(size: 13, weight: .bold))
                            .foregroundStyle(AppColors.danger)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.surfaceRaised)
                            .overlay(Capsule().stroke(AppColors.danger.opacity(0.35), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, restTimer != nil ? 162 : 90)
                }
                .animation(.easeInOut(duration: 0.25), value: isWarningVisible)
            }

            if let inspectingId = inspectingExerciseId,
               let inspectingExercise = exercises.first(where: { $0.id == inspectingId }) {
                MiniExerciseDetailModal(
                    exercise: inspectingExercise,
                    media: sessionMedia,
                    onDismiss: { sessionMedia.freezeActive(); inspectingExerciseId = nil },
                    onReportIssue: {
                        sessionMedia.freezeActive()
                        inspectingExerciseId = nil
                        reportIssue(for: inspectingExercise)
                    }
                )
                .transition(.opacity)
            }

            ToastOverlay(item: store.currentToast, bottomPadding: restTimer != nil ? 162 : 102)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: TwoPageLayout.resolve(in: proxy), initial: true) { _, spread in sessionSpread = spread }
            }
        }
        .tourOverlay(.workout)
        .tourTrigger(.workout, enabled: true)
        .tourTrigger(.restTimer, enabled: tour.hasTarget("workout.rest") && !tour.progress.shouldStart(.workout))
        .onChange(of: tourIdle, initial: true) { _, idle in tour.setIdle(idle, host: .workout) }
        // The first rest's notification prompt follows its tip instead of covering it.
        .onChange(of: tour.activeTour) { previous, active in
            if previous == .restTimer && active != .restTimer { RestAlertScheduler.shared.resumeDeferredPrompt() }
        }
        .task(id: mediaKey) {
            await sessionMedia.prepare(key: mediaKey, initialRowId: currentExercise?.id)
        }
        .onDisappear {
            sessionMedia.close()
            tour.setIdle(false, host: .workout)
            if let active = tour.activeTour, TourHost.host(for: active) == .workout { tour.skip() }
        }
        .sheet(item: $reportingExercise) { exercise in
            ExerciseReportSheet(
                exercise: exercise,
                onDismiss: { reportingExercise = nil },
                onSubmitNotice: { msg in
                    reportingExercise = nil
                    store.showNotice(msg)
                }
            )
        }
        .sheet(item: $pendingReport) { pending in
            PendingReportSheet(
                report: pending,
                onDismiss: { pendingReport = nil },
                onSendNow: {
                    pendingReport = nil
                    Task {
                        let res = await ExerciseReportStore.shared.submitReport(pending)
                        await MainActor.run {
                            switch res {
                            case .success:
                                store.showNotice(LanguageManager.t("report.received"))
                            case .offlineSaved:
                                store.showNotice(LanguageManager.t("report.savedOffline"))
                            case .rateLimited(let isDaily, let nextAllowedAt, _):
                                let toastMsg = isDaily
                                    ? LanguageManager.t("report.toastDaily", ["dateTime": ExerciseReportStore.formatLocalDateTime(nextAllowedAt)])
                                    : LanguageManager.t("report.toastHourly", ["time": ExerciseReportStore.formatLocalTime(nextAllowedAt)])
                                store.showErrorNotice(toastMsg, duration: 2.5)
                            case .error(let msg):
                                store.showErrorNotice(msg, duration: 5.0)
                            }
                        }
                    }
                },
                onDiscard: {
                    _ = try? ExerciseReportStore.shared.deleteReport(id: pending.id)
                    pendingReport = nil
                }
            )
        }
        .sheet(isPresented: $showProgressionInfo) {
            ProgressionInfoSheet()
        }
        .sheet(isPresented: $showWarmupPlateSheet) {
            if let exercise = currentExercise, supportsBarbellWarmup {
                let baseWeight = (WarmupPlateEngine.hasWorkingLoad(selectedPlateWeight) ? selectedPlateWeight : nil)
                    ?? workingWeightKg ?? 0.0

                WarmupPlateSheet(
                    exerciseName: exercise.displayName,
                    initialWorkingWeightKg: baseWeight,
                    initialBarType: store.barType,
                    initialPlates: store.weightUnit == .lbs ? store.availablePlatesLbs : store.availablePlatesKg,
                    unit: store.weightUnit,
                    initialTab: warmupModalTab,
                    onInsertWarmupSets: { sets in
                        store.insertWarmupSets(exerciseId: exercise.id, warmupSets: sets)
                    },
                    onSaveBarType: { bar in
                        store.setBarType(bar)
                    },
                    onSavePlates: { plates in
                        store.setAvailablePlates(plates, unit: store.weightUnit)
                    }
                )
            }
        }
        .sheet(item: $swappingExercise, onDismiss: {
            // Replace once the sheet has gone, so the notice is not hidden behind it.
            guard let swap = pendingSwap else { return }
            pendingSwap = nil
            if let replaced = store.replaceExercise(exerciseId: swap.exerciseId, substituteId: swap.substituteId) {
                store.showNotice(LanguageManager.t("session.replace.done", ["name": replaced.displayName]))
            }
        }) { target in
            ExerciseSwapSheet(
                exercise: target,
                excludedIds: Set(currentDraft.workout.exercises.compactMap(\.exerciseId)),
                onReplace: { substituteId in
                    pendingSwap = (target.id, substituteId)
                    swappingExercise = nil
                }
            )
        }
        .sheet(item: $paywallFeature, onDismiss: {
            if openWarmupAfterUnlock && supportsBarbellWarmup {
                selectedPlateWeight = nil
                warmupModalTab = .warmupRamp
                showWarmupPlateSheet = true
            }
            openWarmupAfterUnlock = false
            if openSwapAfterUnlock, let id = swapAfterUnlockId {
                swappingExercise = currentDraft.workout.exercises.first { $0.id == id }
            }
            openSwapAfterUnlock = false
            swapAfterUnlockId = nil
        }) { feat in
            ProPaywallSheet(
                feature: feat,
                onDismiss: { paywallFeature = nil },
                onUnlocked: {
                    openWarmupAfterUnlock = feat == .warmupCalculator
                    openSwapAfterUnlock = feat == .exerciseSwaps
                }
            )
        }
        .onReceive(timer) { _ in
            checkRestTimerAlarm()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // A note's system keyboard and the set keypad never share the screen.
            keypad.dismiss()
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
        }
        .alert(LanguageManager.t("session.exit"), isPresented: $showExitConfirmation) {
            Button(LanguageManager.t("modal.cancel"), role: .cancel) {}
            Button(LanguageManager.t("session.exit"), role: .destructive) {
                store.abandonActiveSession()
            }
        } message: {
            Text(LanguageManager.t("session.exitConfirm"))
        }
        .alert(
            LanguageManager.t("session.anomalous_weight.title"),
            isPresented: Binding(
                get: { pendingAnomalousSet != nil },
                set: { if !$0 { pendingAnomalousSet = nil } }
            ),
            presenting: pendingAnomalousSet
        ) { pending in
            Button(LanguageManager.t("session.anomalous_weight.edit"), role: .cancel) {
                pendingAnomalousSet = nil
                keypad.resync()
            }
            Button(LanguageManager.t("session.anomalous_weight.confirm")) {
                let exercise = pending.exercise
                let index = pending.index
                let target = pending.ghostTarget
                pendingAnomalousSet = nil
                let sets = currentDraft.setsByExercise[exercise.id] ?? []
                guard sets.indices.contains(index), sets[index].id == pending.setId else { return }
                if let weight = pending.editWeight, let reps = pending.editReps {
                    executeUpdateSet(exerciseId: exercise.id, index: index, weight: weight, reps: reps, expectedSetId: pending.setId)
                } else {
                    executeToggleSet(exercise: exercise, index: index, ghostTarget: target)
                }
            }
        } message: { pending in
            let weightStr = "\(store.weightUnit.formatDisplayWeight(pending.weightKg)) \(store.weightUnit.label)"
            if let prev = pending.prevTopKg, prev > 0 {
                let prevStr = "\(store.weightUnit.formatDisplayWeight(prev)) \(store.weightUnit.label)"
                Text(LanguageManager.t("session.anomalous_weight.message_with_previous", ["weight": weightStr, "previous": prevStr]))
            } else {
                Text(LanguageManager.t("session.anomalous_weight.message_standalone", ["weight": weightStr]))
            }
        }
    }

    /// The session's exercise cards; the grabber collapses them to compact rows (docs/design/form-design-system.md).
    private var exerciseStrip: some View {
        let activeDraft = currentDraft
        let exercises = activeDraft.workout.exercises
        let currentIndex = min(max(0, activeDraft.currentExerciseIndex), max(0, exercises.count - 1))
        // With two pages the exercise's detail is already open on the right, and only that video plays.
        let pinnedId = sessionSpread != nil && exercises.indices.contains(currentIndex) ? exercises[currentIndex].id : nil
        return SessionExerciseStrip(exercises: exercises, currentIndex: currentIndex, setsByExercise: activeDraft.setsByExercise,
            media: sessionMedia, inspectingExerciseId: inspectingExerciseId ?? pinnedId, collapsed: $store.sessionStripCollapsed,
            dragsFromCards: !compactHeight) { idx in
            sessionMedia.freezeActive()
            if idx == currentIndex {
                if pinnedId == nil { inspectingExerciseId = exercises[idx].id }
            } else {
                store.updateActiveSession { d in
                    var copy = d
                    copy.currentExerciseIndex = idx
                    return copy
                }
            }
        }
    }

    private func reportIssue(for exercise: Exercise) {
        let preflight = ExerciseReportStore.shared.checkPreflight()
        switch preflight {
        case .allowed:
            reportingExercise = exercise
        case .cooldown(let isDaily, let nextAllowedAt, _):
            let toastMsg = isDaily
                ? LanguageManager.t("report.toastDaily", ["dateTime": ExerciseReportStore.formatLocalDateTime(nextAllowedAt)])
                : LanguageManager.t("report.toastHourly", ["time": ExerciseReportStore.formatLocalTime(nextAllowedAt)])
            store.showErrorNotice(toastMsg, duration: 2.5)
        case .pending(let report):
            pendingReport = report
        }
    }

    /// The title line's exercise menu: a compact outlined ⋯ pill inside a full 48pt touch target, so it can
    /// share the exercise name's line. It holds Notes, mint once either note has text, and Replace exercise
    /// until a working set is completed.
    private func exerciseMenu(for exercise: Exercise, hasNotes: Bool, canReplace: Bool) -> some View {
        let unlocked = proManager.isFeatureUnlocked(.exerciseSwaps)
        return Menu {
            Button { openNotes(for: exercise) } label: {
                Label { Text(LanguageManager.t("notes.button")) } icon: { menuGlyph("note.text", color: hasNotes ? AppColors.accent : nil) }
            }
            .accessibilityIdentifier("session-notes")
            if canReplace {
                Button {
                    if unlocked { swappingExercise = exercise } else { swapAfterUnlockId = exercise.id; paywallFeature = .exerciseSwaps }
                } label: {
                    // Locked, the purple lock of the session's other locked cards stands in for the PREMIUM badge.
                    Label { Text(LanguageManager.t("session.replace.title")) } icon: {
                        unlocked ? menuGlyph("arrow.left.arrow.right") : menuGlyph("lock.fill", color: AppColors.purple)
                    }
                }
                .accessibilityLabel(unlocked ? LanguageManager.t("session.replace.title")
                    : "\(LanguageManager.t("session.replace.title")), \(LanguageManager.t("pro.premium_required"))")
                .accessibilityIdentifier("session-replace-exercise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .frame(width: 16, height: 16)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
                .frame(minWidth: 48, minHeight: 48)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("\(LanguageManager.t("builder.exerciseActions")) \(exercise.displayName)")
        .accessibilityIdentifier("session-exercise-menu")
    }

    /// Menus draw their glyphs in the label color; a colored glyph has to carry its own color.
    private func menuGlyph(_ name: String, color: Color? = nil) -> Image {
        guard let color, let symbol = UIImage(systemName: name) else { return Image(systemName: name) }
        return Image(uiImage: symbol.withTintColor(UIColor(color), renderingMode: .alwaysOriginal))
    }

    /// The running rest under the exercise: the full bar, or one line while the keypad or a keyboard is up.
    @ViewBuilder
    private func restBar(_ restTimer: RestTimerState?, compact: Bool) -> some View {
        if let rest = restTimer {
            TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                let remaining = rest.secondsRemaining(nowEpochMillis: Int64(timeline.date.timeIntervalSince1970 * 1000))
                if remaining > 0 {
                    RestTimerBar(
                        secondsRemaining: remaining,
                        totalSeconds: rest.totalSeconds,
                        exerciseName: rest.exerciseName,
                        isRunning: rest.isRunning,
                        onTogglePause: { toggleRest() },
                        onAddSeconds: { adjustRest(seconds: $0) },
                        onSetDuration: { setRestDuration(seconds: $0) },
                        onSkip: { skipRest() },
                        // The rest chime and its notification follow the app sound setting, as on Android.
                        isMuted: !store.soundEnabled,
                        onToggleMute: { store.soundEnabled.toggle() },
                        compact: compact
                    )
                    .tourTarget("workout.rest", cornerRadius: compact ? 14 : 18)
                    .padding(.bottom, compact ? 0 : 16)
                }
            }
        }
    }

    /// Sits on a note's keyboard like the system's input bar, with Done to put it away.
    private var keyboardBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 8)
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: {
                Text(LanguageManager.t("common.done")).font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 12).frame(minWidth: 64, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keyboard-done")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(AppColors.surfaceRaised)
        .accessibilityIdentifier("keyboard-bar")
    }

    private var workoutNoteBinding: Binding<String> {
        Binding(
            get: { currentDraft.note ?? "" },
            set: { text in store.updateActiveSession { current in
                var copy = current; copy.note = text.isEmpty ? nil : text; return copy
            } })
    }

    private func openNotes(for exercise: Exercise) {
        withAnimation(.easeInOut(duration: 0.2)) { notesOpenFor = exercise.id }
    }

    /// Both notes, opened from the title line: this occurrence's setup, then the note for the whole workout.
    private func notesPanel(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NoteEditor(titleKey: "notes.setup", text: Binding(
                get: { exercise.setupNote ?? "" },
                set: { store.updateSetupNote(exerciseId: exercise.id, text: $0) }))
                .id("setup-note-\(exercise.id)")
            NoteEditor(titleKey: "notes.workout", text: workoutNoteBinding)
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.easeInOut(duration: 0.2)) { notesOpenFor = nil }
            } label: {
                Text(LanguageManager.t("common.done")).font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.accent)
                    .frame(minWidth: 48, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("session-notes-done")
        }
        .padding(12)
        .background(AppColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("session-notes-panel")
    }

    // MARK: - Actions

    private func showRestWarning() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        warningNoticeMessage = LanguageManager.t("notice.restActiveWarning")
        withAnimation(.easeOut(duration: 0.28)) {
            isWarningVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeIn(duration: 0.24)) {
                isWarningVisible = false
            }
        }
    }

    private func updateSet(exerciseId: String, index: Int, weight: String, reps: String) {
        let sets = currentDraft.setsByExercise[exerciseId] ?? []
        guard sets.indices.contains(index), let exercise = currentDraft.workout.exercises.first(where: { $0.id == exerciseId }) else { return }
        let previous = WorkoutSessionUtils.findPreviousSessionWorkingSets(history: store.state.history.filter { $0.id != currentDraft.id }, exercise: exercise)
        let prevTopKg = previous.compactMap { $0.weightKg }.filter { $0 > 0 }.max()
        if WorkoutSessionUtils.completedSetEditNeedsWeightConfirmation(sets[index], weightInput: weight, unit: store.weightUnit, previousTopWeightKg: prevTopKg),
           let normalized = WorkoutSessionUtils.sanitizedWeightInput(weight, unit: store.weightUnit), let displayWeight = Double(normalized) {
            let weightKg = store.weightUnit.toCanonicalKg(displayWeight)
            pendingAnomalousSet = PendingAnomalousSet(
                exercise: exercise, index: index, setId: sets[index].id, weightKg: weightKg, prevTopKg: prevTopKg,
                ghostTarget: nil, editWeight: weight, editReps: reps
            )
            return
        }
        executeUpdateSet(exerciseId: exerciseId, index: index, weight: weight, reps: reps)
    }

    /// Saves or clears the optional effort rating for one exercise.
    private func setEffort(_ effort: ProgressionEffort?, exerciseId: String) {
        store.updateActiveSession { d in
            var copy = d
            guard copy.workout.exercises.contains(where: { $0.id == exerciseId }) else { return copy }
            var ratings = copy.effortByExercise ?? [:]
            ratings[exerciseId] = effort?.rawValue
            copy.effortByExercise = ratings.isEmpty ? nil : ratings
            return copy
        }
    }

    /// Saves or clears the optional joint-stress rating for one exercise.
    private func setJointStress(_ rating: JointStress?, exerciseId: String) {
        store.updateActiveSession { d in
            var copy = d
            guard copy.workout.exercises.contains(where: { $0.id == exerciseId }) else { return copy }
            var ratings = copy.jointStressByExercise ?? [:]
            ratings[exerciseId] = rating?.rawValue
            copy.jointStressByExercise = ratings.isEmpty ? nil : ratings
            return copy
        }
    }

    /// Writes the coach's canonical targets in one update against the latest draft.
    private func applyProgressionTargets(_ targets: [Int: ProgressionSetTarget], exerciseId: String) {
        let unit = store.weightUnit
        store.updateActiveSession { d in
            var copy = d
            guard let sets = copy.setsByExercise[exerciseId] else { return copy }
            copy.setsByExercise[exerciseId] = WorkoutSessionUtils.applyingProgressionTargets(targets, to: sets, unit: unit)
            return copy
        }
    }

    private func executeUpdateSet(exerciseId: String, index: Int, weight: String, reps: String, expectedSetId: String? = nil) {
        guard let weight = WorkoutSessionUtils.sanitizedWeightInput(weight, unit: store.weightUnit),
              let reps = WorkoutSessionUtils.sanitizedRepsInput(reps) else { return }
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            guard sets.indices.contains(index) else { return copy }
            if let expectedSetId, sets[index].id != expectedSetId { return copy }
            guard let exercise = copy.workout.exercises.first(where: { $0.id == exerciseId }) else { return copy }
            sets[index] = WorkoutSessionUtils.editedSet(sets[index], weight: weight, reps: reps, exercise: exercise, unit: store.weightUnit)
            copy.setsByExercise[exerciseId] = sets
            return copy
        }
    }

    private func toggleSet(exercise: Exercise, index: Int, ghostTarget: GhostTarget? = nil) {
        let currentSets = currentDraft.setsByExercise[exercise.id] ?? []
        guard currentSets.indices.contains(index) else { return }
        let currentSet = currentSets[index]
        if !currentSet.isCompleted {
            let weightKg = currentSet.weightKg ?? (Double(currentSet.weightInput.replacingOccurrences(of: ",", with: ".")).map { WeightUnit.toCanonicalKg($0, unit: store.weightUnit) } ?? 0.0)
            let prevSets = WorkoutSessionUtils.findPreviousSessionWorkingSets(history: store.state.history.filter { $0.id != currentDraft.id }, exercise: exercise)
            let prevTopKg = prevSets.filter { !$0.isWarmup }.compactMap { $0.weightKg }.filter { $0 > 0 }.max()
            if WorkoutSessionUtils.isAnomalousWeight(weightKg: weightKg, previousTopWeightKg: prevTopKg) {
                pendingAnomalousSet = PendingAnomalousSet(exercise: exercise, index: index, setId: currentSet.id, weightKg: weightKg, prevTopKg: prevTopKg, ghostTarget: ghostTarget)
                return
            }
        }
        executeToggleSet(exercise: exercise, index: index, ghostTarget: ghostTarget)
    }

    private func executeToggleSet(exercise: Exercise, index: Int, ghostTarget: GhostTarget? = nil) {
        let currentSets = currentDraft.setsByExercise[exercise.id] ?? []
        if currentSets.indices.contains(index) {
            let currentSet = currentSets[index]
            if !currentSet.isCompleted && !currentSet.isWarmup, let target = ghostTarget {
                let weightKg = currentSet.weightKg ?? (Double(currentSet.weightInput.replacingOccurrences(of: ",", with: ".")).map { WeightUnit.toCanonicalKg($0, unit: store.weightUnit) } ?? 0.0)
                let reps = currentSet.completedReps ?? (Int(currentSet.repsInput) ?? 0)
                if let beat = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: weightKg, loggedReps: reps, target: target) {
                    celebratoryNoticeMessage = WorkoutSessionUtils.formatLogbookBeatNotice(result: beat, unit: store.weightUnit)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCelebrationVisible = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCelebrationVisible = false
                            }
                        }
                    }
                }
            }
        }
        store.updateActiveSession { d in
            let updated = WorkoutSessionUtils.toggledSet(d, exerciseId: exercise.id, index: index,
                prefillNextSet: store.prefillNextSet, unit: store.weightUnit, now: nowEpochMillis)
            if updated != d {
                if d.setsByExercise[exercise.id]?[index].isCompleted == true { FormAudioPlayer.playSetUndoSound() }
                else { FormAudioPlayer.playSetCompleteSound() }
            }
            return updated
        }
    }

    // MARK: Drop sets, rest-pause and partials

    private func intensityActions(exercise: Exercise, previousSets: [Int: SessionSetLog]) -> IntensityActions {
        IntensityActions(
            exercise: exercise,
            previousSets: previousSets,
            onAddExtension: { index, technique in
                let previous = previousSets[index]
                changeSet(exercise: exercise, index: index) { set in
                    let next = set.extensions?.count ?? 0
                    let prefill = store.prefillNextSet && technique == .drop && previous?.setTechnique == .drop
                        ? previous?.setExtensions[safe: next]?.weightKg : nil
                    return IntensitySets.addingExtension(technique, to: set, prefillWeightKg: prefill, unit: store.weightUnit,
                                                         barbell: WorkoutSessionUtils.usesBarbellPlates(exercise))
                }
            },
            onUpdateExtension: { index, extensionIndex, weight, reps in
                guard let weight = WorkoutSessionUtils.sanitizedWeightInput(weight, unit: store.weightUnit),
                      let reps = WorkoutSessionUtils.sanitizedRepsInput(reps) else { return }
                changeSet(exercise: exercise, index: index) {
                    IntensitySets.editingExtension($0, at: extensionIndex, weight: weight, reps: reps, exercise: exercise, unit: store.weightUnit)
                }
            },
            onToggleExtension: { index, extensionIndex in toggleExtension(exercise: exercise, index: index, extensionIndex: extensionIndex) },
            onAddPartials: { index in changeSet(exercise: exercise, index: index, IntensitySets.addingPartials(to:)) },
            onUpdatePartials: { index, extensionIndex, input in
                changeSet(exercise: exercise, index: index) { IntensitySets.editingPartials($0, extensionIndex: extensionIndex, input: input) }
            },
            onRemoveLastPart: { index in changeSet(exercise: exercise, index: index, IntensitySets.removingLastPart) },
            onEndExercise: { index in
                store.updateActiveSession { IntensitySets.endingExercise(in: $0, exerciseId: exercise.id, at: index) }
            }
        )
    }

    private func changeSet(exercise: Exercise, index: Int, _ change: @escaping (ExerciseSetLog) -> ExerciseSetLog) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exercise.id] ?? []
            guard sets.indices.contains(index), !sets[index].isWarmup else { return copy }
            sets[index] = change(sets[index])
            copy.setsByExercise[exercise.id] = sets
            return copy
        }
    }

    /// Ticking an extension of the set that started the running rest restarts that rest.
    private func toggleExtension(exercise: Exercise, index: Int, extensionIndex: Int) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exercise.id] ?? []
            guard sets.indices.contains(index) else { return copy }
            let wasTicked = sets[index].extensions?[safe: extensionIndex]?.isCompleted ?? false
            sets[index] = IntensitySets.togglingExtension(sets[index], at: extensionIndex, exercise: exercise, unit: store.weightUnit)
            let isTicked = sets[index].extensions?[safe: extensionIndex]?.isCompleted ?? false
            copy.setsByExercise[exercise.id] = sets
            if !wasTicked && isTicked {
                FormAudioPlayer.playSetCompleteSound()
                copy.restTimer = IntensitySets.restAfterTickingExtension(in: copy, setId: sets[index].id, exercise: exercise, nowEpochMillis: nowEpochMillis)
            } else if wasTicked && !isTicked {
                FormAudioPlayer.playSetUndoSound()
            }
            return copy
        }
    }

    private func presentWorkoutSummary() {
        sessionMedia.freezeActive()
        FormAudioPlayer.playWorkoutCompleteSound()
        finishedAt = Int64(Date().timeIntervalSince1970 * 1000)
        showSummary = true
    }

    private func addSet(exerciseId: String) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            let workingCount = sets.filter { !$0.isWarmup }.count
            guard let exercise = copy.workout.exercises.first(where: { $0.id == exerciseId }) else { return copy }
            let newSet = WorkoutSessionUtils.newSet(exercise: exercise, number: workingCount + 1)
            let lastWorking = sets.filter { !$0.isWarmup }.last
            sets.append(store.prefillNextSet ? WorkoutSessionUtils.prefillSet(newSet, from: lastWorking, unit: store.weightUnit,
                barbell: WorkoutSessionUtils.usesBarbellPlates(exercise)) : newSet)
            copy.setsByExercise[exerciseId] = AppStore.reindexSets(sets)
            return copy
        }
    }

    private func removeSet(exerciseId: String, index: Int) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            guard sets.indices.contains(index) else { return copy }
            sets.remove(at: index)
            copy.setsByExercise[exerciseId] = AppStore.reindexSets(sets)
            return copy
        }
    }

    private func toggleRest() {
        store.updateActiveSession { d in
            var copy = d
            guard let timer = copy.restTimer else { return copy }
            copy.restTimer = timer.isRunning ? timer.paused(nowEpochMillis: nowEpochMillis) : timer.resumed(nowEpochMillis: nowEpochMillis)
            return copy
        }
    }

    private func adjustRest(seconds: Int) {
        store.updateActiveSession { d in
            var copy = d
            copy.restTimer = copy.restTimer?.adjusted(by: seconds, nowEpochMillis: nowEpochMillis)
            return copy
        }
    }

    private func setRestDuration(seconds: Int) {
        store.updateActiveSession { d in
            var copy = d
            let exercises = copy.workout.exercises
            let idx = copy.currentExerciseIndex
            let exName = copy.restTimer?.exerciseName ?? (exercises.indices.contains(idx) ? exercises[idx].name : "")
            let endEpoch = nowEpochMillis + Int64(seconds * 1000)
            copy.restTimer = RestTimerState(
                exerciseName: exName,
                totalSeconds: seconds,
                isRunning: true,
                endsAtEpochMillis: endEpoch,
                pausedSecondsRemaining: seconds
            )
            return copy
        }
    }

    private func skipRest() {
        store.updateActiveSession { d in
            var copy = d
            copy.restTimer = nil
            return copy
        }
    }

    private func checkRestTimerAlarm() {
        // A backgrounded workout leaves its rest to the notification; returning clears it silently.
        guard !store.isSceneBackgrounded else { return }
        guard let rest = currentDraft.restTimer, rest.isRunning, let end = rest.endsAtEpochMillis else { return }
        if nowEpochMillis >= end {
            FormAudioPlayer.playRestCompleteSound()
            skipRest()
        }
    }
}

private struct MiniExerciseDetailModal: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let exercise: Exercise
    @ObservedObject var media: SessionExerciseMedia
    var onDismiss: () -> Void
    var onReportIssue: (() -> Void)? = nil

    var body: some View {
        let _ = themeManager.currentTheme
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            SessionExerciseDetailContent(exercise: exercise, media: media, onDismiss: onDismiss, onReportIssue: onReportIssue)
                .frame(maxWidth: 360, maxHeight: 560)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                .padding(24)
                .accessibilityIdentifier("mini-exercise-detail-modal")
        }
    }
}

/// An exercise's demonstration, linked videos, cues and mistakes: a modal during a session, or pinned beside it on an open foldable.
private struct SessionExerciseDetailContent: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let exercise: Exercise
    @ObservedObject var media: SessionExerciseMedia
    var onDismiss: (() -> Void)? = nil
    var onReportIssue: (() -> Void)? = nil
    @State private var watchingLinkedVideo = false

    var body: some View {
        let _ = themeManager.currentTheme
        VStack(spacing: 0) {
            // Header: Title, category, and close button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.displayName)
                        .font(.app(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(2)
                    Text(exercise.metadataSubtitle)
                        .font(.app(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                }

                Spacer()

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(LanguageManager.t("common.close"))
                    .accessibilityIdentifier("mini-exercise-detail-close")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(AppColors.border)

            // Scrollable Content: Video + Linked videos + Cues + Avoid
            ScrollView {
                VStack(spacing: 14) {
                    SessionExerciseDetailVideo(media: media, rowId: exercise.id, exerciseId: exercise.exerciseId,
                                               active: !watchingLinkedVideo)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.exerciseVideoSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppColors.border, lineWidth: 1)
                        )

                    // The exercise's linked YouTube videos; the movement animation pauses while one plays.
                    if !exercise.videos.isEmpty {
                        ExerciseVideosView(exercise: exercise, onPlayerShownChange: { shown in
                            if shown { media.freezeActive() }
                            watchingLinkedVideo = shown
                        })
                    }

                    let cuesText = exercise.displayCues.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cuesText.isEmpty {
                        TechniqueSectionView(
                            title: LanguageManager.t("modal.exercise.cues"),
                            text: cuesText,
                            accent: AppColors.accent,
                            isAvoid: false,
                            initiallyExpanded: false
                        )
                    }

                    let avoidText = exercise.displayAvoid.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !avoidText.isEmpty {
                        TechniqueSectionView(
                            title: LanguageManager.t("modal.exercise.avoid"),
                            text: avoidText,
                            accent: AppColors.danger,
                            isAvoid: true,
                            initiallyExpanded: false
                        )
                    }

                    if let onReportIssue = onReportIssue {
                        HStack {
                            Spacer()
                            Button(action: onReportIssue) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(LanguageManager.t("report.action"))
                                        .font(.app(size: 13, weight: .medium))
                                }
                                .foregroundStyle(AppColors.danger)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 40)
                                .background(AppColors.danger.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppColors.danger.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct PendingAnomalousSet: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let index: Int
    let setId: String
    let weightKg: Double
    let prevTopKg: Double?
    let ghostTarget: GhostTarget?
    var editWeight: String? = nil
    var editReps: String? = nil
}


/// The active session's top bar: the exit square, the centered title and live status, and the outlined Finish pill.
struct SessionHeader: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let title: String
    let programLabel: String
    let draft: ActiveSessionDraft
    let onExit: () -> Void
    let onFinish: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        SessionHeaderLayout { parts }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppColors.background)
    }

    /// The exit button, title, live dot and timer, optional program name and Finish pill, in `SessionHeaderLayout` order.
    @ViewBuilder var parts: some View {
        Button(action: onExit) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColors.text)
                .frame(width: 38, height: 38)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LanguageManager.t("session.exit"))

        Text(title)
            .font(.app(size: 16, weight: .bold))
            .foregroundStyle(AppColors.text)
            .lineLimit(1)

        HStack(spacing: 6) {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let cycleDuration = 1.4
                let cycleTime = time.truncatingRemainder(dividingBy: cycleDuration)
                let progress = cycleTime / cycleDuration
                let (scale, alpha): (CGFloat, Double) = {
                    if progress < 0.75 {
                        let fraction = progress / 0.75
                        // cubic-bezier(0, 0, 0.2, 1): x(u) = 0.6 u^2 + 0.4 u^3, y(u) = 3 u^2 - 2 u^3
                        var u = min(1.0, max(0.0, sqrt(fraction / 0.6)))
                        for _ in 0..<4 {
                            let xu = 0.6 * u * u + 0.4 * u * u * u
                            let dxdu = 1.2 * u + 1.2 * u * u
                            if abs(dxdu) < 1e-6 { break }
                            u -= (xu - fraction) / dxdu
                            u = min(1.0, max(0.0, u))
                        }
                        let eased = min(1.0, max(0.0, 3.0 * u * u - 2.0 * u * u * u))
                        return (CGFloat(1.0 + eased * 1.0), 1.0 - eased)
                    } else {
                        return (2.0, 0.0)
                    }
                }()

                ZStack {
                    if alpha > 0.001 {
                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [
                                        .init(color: AppColors.accent.opacity(alpha), location: 0.0),
                                        .init(color: AppColors.accent.opacity(alpha * 0.85), location: 0.75),
                                        .init(color: Color.clear, location: 1.0)
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 4.0
                                )
                            )
                            .frame(width: 8, height: 8)
                            .scaleEffect(scale)
                    }
                }
                .frame(width: 8, height: 8)
            }

            SessionElapsedTime(draft: draft)
        }

        if !programLabel.isEmpty {
            HStack(spacing: 6) {
                Text("·")
                    .font(.app(size: 12))
                    .foregroundStyle(AppColors.muted)

                Text(programLabel)
                    .font(.app(size: 12))
                    .foregroundStyle(AppColors.muted)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
        }

        Button(action: onFinish) {
            Text(LanguageManager.t("session.finishBtn"))
                .font(.app(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.clear)
                .overlay(
                    Capsule()
                        .stroke(AppColors.accent, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .tourTarget("workout.finish", cornerRadius: 18)
    }
}

/// Lays out the session header: exit button, title, live dot and timer, optional program name and Finish pill, in
/// that order. The title and live status are centered with the same inset on both sides: 72pt, or the wider button
/// plus an 8pt gap once a localized Finish label outgrows that. Only when the live dot and timer cannot fit there does
/// the column use the whole space between the buttons, sliding off center as little as it needs. The title and program
/// name truncate; nothing overlaps a button. Matches Android's `SessionHeaderBar`.
struct SessionHeaderLayout: Layout {
    static let minimumInset: CGFloat = 72
    static let gap: CGFloat = 8
    static let lineSpacing: CGFloat = 2

    private struct Frames {
        var size: CGSize
        var exit: CGRect, title: CGRect, clock: CGRect, program: CGRect?, finish: CGRect
        // Subviews are placed with the widths they were measured with, so truncation stays the same.
        var finishProposal: CGFloat, clockProposal: CGFloat, columnMax: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(width: proposal.width, subviews: subviews).size
    }

    /// Where `placeSubviews` puts each subview, in subview order, relative to the layout's origin.
    func subviewFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let frames = frames(width: width, subviews: subviews)
        return [frames.exit, frames.title, frames.clock] + [frames.program].compactMap { $0 } + [frames.finish]
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(width: bounds.width, subviews: subviews)
        func place(_ subview: LayoutSubview, _ frame: CGRect, width: CGFloat? = nil) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width ?? frame.width, height: nil))
        }
        place(subviews[0], frames.exit)
        place(subviews[1], frames.title, width: frames.columnMax)
        place(subviews[2], frames.clock, width: frames.clockProposal)
        if let program = frames.program { place(subviews[3], program, width: max(0, frames.columnMax - frames.clock.width)) }
        place(subviews[subviews.count - 1], frames.finish, width: frames.finishProposal)
    }

    private func frames(width proposedWidth: CGFloat?, subviews: Subviews) -> Frames {
        let exit = subviews[0], title = subviews[1], clock = subviews[2], finish = subviews[subviews.count - 1]
        let program = subviews.count > 4 ? subviews[3] : nil
        let gap = Self.gap
        let exitSize = exit.sizeThatFits(.unspecified)
        let finishIdeal = finish.sizeThatFits(.unspecified)
        let width = proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? {
            let status = clock.sizeThatFits(.unspecified).width + (program?.sizeThatFits(.unspecified).width ?? 0)
            return 2 * max(Self.minimumInset, max(exitSize.width, finishIdeal.width) + gap)
                + max(title.sizeThatFits(.unspecified).width, status)
        }()
        let finishProposal = max(0, width - exitSize.width - gap)
        let finishSize = finish.sizeThatFits(ProposedViewSize(width: finishProposal, height: nil))
        let inset = max(Self.minimumInset, max(exitSize.width, finishSize.width) + gap)
        let centered = max(0, width - 2 * inset)
        let between = max(width - exitSize.width - finishSize.width - 2 * gap, centered)
        let clockSize = clock.sizeThatFits(ProposedViewSize(width: between, height: nil))
        let columnMax = clockSize.width <= centered ? centered : between
        let titleSize = title.sizeThatFits(ProposedViewSize(width: columnMax, height: nil))
        let programSize = program?.sizeThatFits(ProposedViewSize(width: max(0, columnMax - clockSize.width), height: nil))
        let statusWidth = clockSize.width + (programSize?.width ?? 0)
        let statusHeight = max(clockSize.height, programSize?.height ?? 0)
        let columnWidth = max(titleSize.width, statusWidth)
        let columnHeight = titleSize.height + Self.lineSpacing + statusHeight
        let columnX = max(exitSize.width + gap, min((width - columnWidth) / 2, width - finishSize.width - gap - columnWidth))
        let height = max(exitSize.height, columnHeight, finishSize.height)
        let columnY = (height - columnHeight) / 2
        let statusX = columnX + (columnWidth - statusWidth) / 2
        let statusY = columnY + columnHeight - statusHeight
        return Frames(
            size: CGSize(width: width, height: height),
            exit: CGRect(origin: CGPoint(x: 0, y: (height - exitSize.height) / 2), size: exitSize),
            title: CGRect(origin: CGPoint(x: columnX + (columnWidth - titleSize.width) / 2, y: columnY), size: titleSize),
            clock: CGRect(origin: CGPoint(x: statusX, y: statusY + (statusHeight - clockSize.height) / 2), size: clockSize),
            program: programSize.map { CGRect(origin: CGPoint(x: statusX + clockSize.width,
                y: statusY + (statusHeight - $0.height) / 2), size: $0) },
            finish: CGRect(origin: CGPoint(x: width - finishSize.width, y: (height - finishSize.height) / 2), size: finishSize),
            finishProposal: finishProposal, clockProposal: between, columnMax: columnMax)
    }
}

private struct SessionElapsedTime: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let draft: ActiveSessionDraft
    var body: some View {
        let _ = themeManager.currentTheme
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(RestTimerUtils.formatSecondsToTime(draft.currentDurationSeconds(
                nowEpochMillis: Int64(timeline.date.timeIntervalSince1970 * 1000))))
                .font(.app(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
        }
    }
}

private extension VerticalAlignment {
    private enum FirstLineCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    /// The middle of a title's first line, for actions that share that line.
    static let firstLineCenter = VerticalAlignment(FirstLineCenter.self)
}

/// The exercise name with an optional trailing action. The action sits beside the name, centered on its first
/// line, while every word still fits beside it; otherwise it moves below so no word is split.
struct ExerciseTitleRow<Action: View>: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let name: String
    let action: Action?
    @State private var rowWidth: CGFloat = 0
    @State private var actionWidth: CGFloat = 0

    var body: some View {
        let _ = themeManager.currentTheme
        let font = UIFont.systemFont(ofSize: 20 * TextWidthScale.factor, weight: .bold)
        // Lines may break at spaces and after hyphens, so the widest piece between those must fit.
        let longestPiece = name.replacingOccurrences(of: "-", with: "- ").split(separator: " ").map {
            ceil((String($0) as NSString).size(withAttributes: [.font: font]).width)
        }.max() ?? 0
        let beside = rowWidth == 0 || longestPiece <= rowWidth - actionWidth - 12
        let title = Text(name)
            .font(.app(size: 20, weight: .bold))
            .foregroundStyle(AppColors.text)
        Group {
            if let action, beside {
                HStack(alignment: .firstLineCenter, spacing: 12) {
                    title
                        .alignmentGuide(.firstLineCenter) { $0[.firstTextBaseline] - font.capHeight / 2 }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    measured(action)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    if let action { measured(action) }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    private func measured(_ action: Action) -> some View {
        action
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { actionWidth = $0 }
    }
}

/// Label widths and card heights of both strip layouts. Compact names are never clipped: a name takes the
/// narrowest width that holds it in two lines, and past the widest card it wraps and every card grows taller.
struct SessionStripMetrics: Equatable {
    static let cardPadding: CGFloat = 8
    static let expandedWidth: CGFloat = 110
    static let expandedThumb: CGFloat = 72
    static let compactThumb: CGFloat = 40
    static let compactLabelGap: CGFloat = 8
    static let compactSingleLineMax: CGFloat = 120
    static let compactLabelMax: CGFloat = 220

    let compactLabelWidths: [CGFloat]
    let compactCardHeight: CGFloat
    let expandedCardHeight: CGFloat

    static func compactWidth(labelWidth: CGFloat) -> CGFloat {
        cardPadding + compactThumb + compactLabelGap + labelWidth + cardPadding
    }

    @MainActor private static var cache: [String: SessionStripMetrics] = [:]

    /// Measured with the selected (bold) weight, so selecting a card never rewraps it.
    @MainActor static func measure(_ labels: [String], scale: CGFloat = TextWidthScale.factor) -> SessionStripMetrics {
        let key = "\(scale)|" + labels.joined(separator: "\n")
        if let cached = cache[key] { return cached }
        let font = UIFont.systemFont(ofSize: 11 * scale, weight: .bold)
        let compact = labels.map { label -> (CGFloat, CGFloat) in
            let single = ceil((label as NSString).size(withAttributes: [.font: font]).width)
            let width: CGFloat
            if single <= compactSingleLineMax {
                width = single
            } else if !lineBreaks(label, font: font, width: compactLabelMax).fitsTwoLines {
                width = compactLabelMax
            } else {
                var low = ceil(single / 2), high = compactLabelMax
                while low < high {
                    let middle = floor((low + high) / 2)
                    if lineBreaks(label, font: font, width: middle).fitsTwoLines { high = middle } else { low = middle + 1 }
                }
                width = low
            }
            // SwiftUI's line breaking can differ from TextKit by a fraction of a point.
            return (width + 2, lineBreaks(label, font: font, width: width).height)
        }
        let metrics = SessionStripMetrics(
            compactLabelWidths: compact.map(\.0),
            compactCardHeight: max(compactThumb, compact.map(\.1).max() ?? 0) + 2 * cardPadding,
            expandedCardHeight: expandedThumb + 4 + max(28, ceil(2 * font.lineHeight)) + 2 * cardPadding)
        cache[key] = metrics
        return metrics
    }

    /// Lays `text` out at `width`. It fits when it takes two lines at most, broken only at spaces or after hyphens,
    /// never inside a word.
    static func lineBreaks(_ text: String, font: UIFont, width: CGFloat) -> (fitsTwoLines: Bool, lines: Int, height: CGFloat) {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var ends: [Int] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
            ends.append(NSMaxRange(layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)))
        }
        let utf16 = Array(text.utf16)
        let clean = ends.dropLast().allSatisfy { end in end > 0 && [UInt16(32), UInt16(45)].contains(utf16[end - 1]) }
        return (ends.count <= 2 && clean, ends.count, ceil(layout.usedRect(for: container).height))
    }
}

private func lerp(_ start: CGFloat, _ stop: CGFloat, _ fraction: CGFloat) -> CGFloat { start + (stop - start) * fraction }

/// The session's exercise cards above a grabber. Dragging the grabber follows the finger between the expanded tiles
/// and compact rows and snaps to the nearer one (or the fling); a tap toggles. The choice is stored in `collapsed`.
struct SessionExerciseStrip: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let exercises: [Exercise]
    let currentIndex: Int
    let setsByExercise: [String: [ExerciseSetLog]]
    @ObservedObject var media: SessionExerciseMedia
    let inspectingExerciseId: String?
    @Binding var collapsed: Bool
    /// Vertical drags on the cards also collapse the strip, unless a short window scrolls it with the sets.
    var dragsFromCards = true
    let onSelect: (Int) -> Void
    @State private var dragProgress: CGFloat? = nil
    /// Whether the current card drag is vertical; sideways drags are left to the card row's scrolling.
    @State private var cardDragIsVertical: Bool? = nil
    /// The card under a vertical drag still sees the lift as a tap; a drag must not select it.
    @State private var cardDragEndedAt = Date.distantPast

    static let grabberHeight: CGFloat = 24
    private static let snap = Animation.spring(response: 0.32, dampingFraction: 1)

    var body: some View {
        let _ = themeManager.currentTheme
        let labelWorkout = Workout(id: "strip-labels", day: 1, title: "", exercises: exercises)
        let labels = exercises.enumerated().map { (Supersets.label(labelWorkout, $0.element.id) ?? "\($0.offset + 1).") + " " + $0.element.displayName }
        // The number stays with the first word, so a long compound name breaks inside the name instead.
        let compactLabels = exercises.enumerated().map { (Supersets.label(labelWorkout, $0.element.id) ?? "\($0.offset + 1).") + "\u{00A0}" + $0.element.displayName }
        let metrics = SessionStripMetrics.measure(compactLabels)
        let progress = dragProgress ?? (collapsed ? 1 : 0)
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                            let isSel = idx == currentIndex
                            let sets = setsByExercise[ex.id] ?? []
                            Button(action: {
                                guard cardDragIsVertical != true, Date().timeIntervalSince(cardDragEndedAt) > 0.3 else { return }
                                onSelect(idx)
                            }) {
                                SessionStripCard(progress: progress, label: labels[idx], compactLabel: compactLabels[idx], selected: isSel,
                                    complete: !sets.isEmpty && sets.allSatisfy { $0.isCompleted },
                                    compactLabelWidth: metrics.compactLabelWidths[idx], metrics: metrics) { size in
                                    SessionMovementIcon(media: media, rowId: ex.id,
                                        active: isSel && inspectingExerciseId == nil, size: size)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(ex.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .tourTarget("workout.exercises", cornerRadius: 13,
                            contentInsets: EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
                .simultaneousGesture(cardDrag(metrics: metrics), including: dragsFromCards ? .all : .subviews)
                .onAppear {
                    // A short window moves the strip into the scrolling content; keep the current card in view.
                    if exercises.indices.contains(currentIndex) { scrollProxy.scrollTo(exercises[currentIndex].id, anchor: .center) }
                }
                .onChange(of: currentIndex) { _, newIdx in
                    if exercises.indices.contains(newIdx) {
                        withAnimation {
                            scrollProxy.scrollTo(exercises[newIdx].id, anchor: .center)
                        }
                    }
                }
            }
            grabber(metrics: metrics)
        }
    }

    private func range(_ metrics: SessionStripMetrics) -> CGFloat { max(1, metrics.expandedCardHeight - metrics.compactCardHeight) }

    /// Follows the finger in global coordinates: the strip shrinks under it, so local translation would cancel itself.
    private func follow(_ value: DragGesture.Value, metrics: SessionStripMetrics) {
        dragProgress = min(1, max(0, (collapsed ? 1 : 0) - value.translation.height / range(metrics)))
    }

    /// Snaps to the fling direction above 400pt/s, otherwise to the nearer state.
    private func settle(_ value: DragGesture.Value) {
        let velocity = value.velocity.height
        let target = abs(velocity) > 400 ? velocity < 0 : (dragProgress ?? (collapsed ? 1 : 0)) >= 0.5
        withAnimation(Self.snap) {
            collapsed = target
            dragProgress = nil
        }
    }

    private func cardDrag(metrics: SessionStripMetrics) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if cardDragIsVertical == nil { cardDragIsVertical = abs(value.translation.height) > abs(value.translation.width) }
                if cardDragIsVertical == true { follow(value, metrics: metrics) }
            }
            .onEnded { value in
                if cardDragIsVertical == true {
                    settle(value)
                    cardDragEndedAt = Date()
                }
                cardDragIsVertical = nil
            }
    }

    private func grabber(metrics: SessionStripMetrics) -> some View {
        Capsule()
            .fill(AppColors.border)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, minHeight: Self.grabberHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { follow($0, metrics: metrics) }
                .onEnded { value in
                    if abs(value.translation.height) < 6 && abs(value.velocity.height) < 400 {
                        withAnimation(Self.snap) {
                            collapsed.toggle()
                            dragProgress = nil
                        }
                    } else {
                        settle(value)
                    }
                })
            .accessibilityElement()
            .accessibilityLabel(LanguageManager.t(collapsed ? "session.strip.expand" : "session.strip.collapse"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation(Self.snap) { collapsed.toggle() } }
            .accessibilityIdentifier("session-strip-grabber")
    }
}

/// One strip card at `progress` between the expanded tile (0) and the compact row (1). The thumbnail and check move
/// between both layouts; the two labels cross-fade, so neither reflows.
private struct SessionStripCard<Thumb: View>: View {
    let progress: CGFloat
    let label: String
    let compactLabel: String
    let selected: Bool
    let complete: Bool
    let compactLabelWidth: CGFloat
    let metrics: SessionStripMetrics
    @ViewBuilder let thumb: (CGFloat) -> Thumb
    private typealias M = SessionStripMetrics

    var body: some View {
        let p = progress
        let thumbSize = lerp(M.expandedThumb, M.compactThumb, p)
        let width = lerp(M.expandedWidth, M.compactWidth(labelWidth: compactLabelWidth), p)
        let height = lerp(metrics.expandedCardHeight, metrics.compactCardHeight, p)
        let thumbX = lerp((M.expandedWidth - thumbSize) / 2, M.cardPadding, p)
        let thumbY = lerp(M.cardPadding, (metrics.compactCardHeight - M.compactThumb) / 2, p)
        let font = Font.app(size: 11, weight: selected ? .bold : .medium)
        let color = selected ? AppColors.text : AppColors.muted
        ZStack(alignment: .topLeading) {
            thumb(thumbSize)
                .offset(x: thumbX, y: thumbY)
            if p < 1 {
                Text(label)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: M.expandedWidth - 2 * M.cardPadding)
                    .frame(minHeight: 28)
                    .offset(x: M.cardPadding, y: thumbY + thumbSize + 4)
                    .opacity(Double(max(0, 1 - 2 * p)))
                    .transition(.opacity)
            }
            if p > 0 {
                Text(compactLabel)
                    .font(font)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: compactLabelWidth, height: height, alignment: .leading)
                    .offset(x: thumbX + thumbSize + M.compactLabelGap)
                    .opacity(Double(min(1, max(0, 2 * p - 1))))
                    .transition(.opacity)
            }
            // Top corner of the card when expanded; the thumbnail's corner when compact, clear of the name.
            if complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 16, height: 16)
                    .offset(x: lerp(width - 20, thumbX + thumbSize - 12, p), y: lerp(4, thumbY - 4, p))
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(selected ? AppColors.accent : AppColors.border, lineWidth: 1)
                )
        )
    }
}
