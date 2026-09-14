import SwiftUI

public struct ActiveSessionView: View {
    @ObservedObject var store: AppStore
    let draft: ActiveSessionDraft

    @State private var nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    @State private var showExitConfirmation: Bool = false
    @State private var showSummary: Bool = false
    @State private var finishedAt: Int64? = nil
    @State private var restMuted: Bool = false
    @State private var warningNoticeMessage: String? = nil
    @State private var isWarningVisible: Bool = false

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public init(store: AppStore, draft: ActiveSessionDraft) {
        self.store = store
        self.draft = draft
    }

    private var currentDraft: ActiveSessionDraft {
        store.activeSession ?? draft
    }

    public var body: some View {
        let activeDraft = currentDraft
        let effectiveNow = showSummary ? (finishedAt ?? nowEpochMillis) : nowEpochMillis
        let progress = SessionProgress.from(draft: activeDraft, nowEpochMillis: effectiveNow)
        let exercises = activeDraft.workout.exercises
        let currentIndex = min(max(0, activeDraft.currentExerciseIndex), max(0, exercises.count - 1))
        let currentExercise = exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
        let currentSets = currentExercise.map { activeDraft.setsByExercise[$0.id] ?? [] } ?? []
        let restTimer = activeDraft.restTimer

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
                        store.completeActiveSession(record)
                    }
                )
            } else {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button(action: {
                            if progress.hasProgress {
                                showExitConfirmation = true
                            } else {
                                store.abandonActiveSession()
                            }
                        }) {
                            Image(systemName: "arrow.backward")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeDraft.workout.displayTitle(programId: activeDraft.programId))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppColors.text)
                                .lineLimit(1)
                            Text(RestTimerUtils.formatSecondsToTime(progress.durationSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.accent)
                        }

                        Spacer()

                        Button(action: {
                            presentWorkoutSummary()
                        }) {
                            Text(LanguageManager.t("session.finish"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.todaySelectionText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(AppColors.accent)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.surface)

                    // Main Content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Exercise horizontal card carousel
                            ScrollViewReader { scrollProxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, ex in
                                            let isSel = idx == currentIndex
                                            let sets = activeDraft.setsByExercise[ex.id] ?? []
                                            let isAllDone = !sets.isEmpty && sets.allSatisfy { $0.isCompleted }

                                            Button(action: {
                                                store.updateActiveSession { d in
                                                    var copy = d
                                                    copy.currentExerciseIndex = idx
                                                    return copy
                                                }
                                            }) {
                                                ZStack(alignment: .topTrailing) {
                                                    VStack(spacing: 4) {
                                                        MovementIcon(
                                                            exerciseId: ex.exerciseId,
                                                            size: 48
                                                        )

                                                        Text("\(idx + 1). \(ex.displayName)")
                                                            .font(.system(size: 10, weight: isSel ? .bold : .medium))
                                                            .foregroundColor(isSel ? AppColors.text : AppColors.muted)
                                                            .lineLimit(2)
                                                            .multilineTextAlignment(.center)
                                                            .frame(maxWidth: .infinity, minHeight: 26)
                                                    }
                                                    .padding(7)
                                                    .frame(width: 86)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                            .fill(AppColors.surface)
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                                    .stroke(isSel ? AppColors.accent : AppColors.border, lineWidth: 1)
                                                            )
                                                    )

                                                    if isAllDone {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 14))
                                                            .foregroundColor(AppColors.accent)
                                                            .padding(4)
                                                    }
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .id(ex.id)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                                }
                                .onChange(of: currentIndex) { _, newIdx in
                                    if exercises.indices.contains(newIdx) {
                                        withAnimation {
                                            scrollProxy.scrollTo(exercises[newIdx].id, anchor: .center)
                                        }
                                    }
                                }
                            }

                            // Current Exercise Card
                            if let exercise = currentExercise {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(exercise.displayName)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(AppColors.text)
                                        }
                                        Spacer()
                                        MovementIcon(
                                            exerciseId: exercise.exerciseId,
                                            size: 56
                                        )
                                    }

                                    let isRestActive = (activeDraft.restTimer?.secondsRemaining(nowEpochMillis: nowEpochMillis) ?? 0) > 0

                                    SetLoggingTable(
                                        sets: currentSets,
                                        prescription: exercise.displayPrescription,
                                        isRestActive: isRestActive,
                                        onUpdateSet: { setIdx, weight, reps in
                                            updateSet(exerciseId: exercise.id, index: setIdx, weight: weight, reps: reps)
                                        },
                                        onToggleCompleteSet: { setIdx in
                                            toggleSet(exercise: exercise, index: setIdx)
                                        },
                                        onAddSet: {
                                            addSet(exerciseId: exercise.id)
                                        },
                                        onRemoveSet: { setIdx in
                                            removeSet(exerciseId: exercise.id, index: setIdx)
                                        },
                                        onEmptyWarning: {
                                            showEmptyWarning()
                                        },
                                        onRestWarning: {
                                            showRestWarning()
                                        }
                                    )
                                }
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppColors.surface)
                                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                                )
                                .padding(.horizontal, 20)
                            }

                            // Navigation Row: Previous & Next Exercise buttons
                            HStack(spacing: 10) {
                                Button(action: {
                                    if currentIndex > 0 {
                                        store.updateActiveSession { d in
                                            var copy = d
                                            copy.currentExerciseIndex = currentIndex - 1
                                            return copy
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.left")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(currentIndex > 0 ? AppColors.text : AppColors.muted.opacity(0.3))
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

                                Button(action: {
                                    if currentIndex < exercises.count - 1 {
                                        store.updateActiveSession { d in
                                            var copy = d
                                            copy.currentExerciseIndex = currentIndex + 1
                                            return copy
                                        }
                                    } else {
                                        presentWorkoutSummary()
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Text(LanguageManager.t(currentIndex < exercises.count - 1 ? "session.nextExercise" : "session.review"))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.black)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.black)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(AppColors.accent)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 20)

                            Spacer().frame(height: 148) // Space for floating rest timer
                        }
                    }

                    // Floating Rest Timer Bar
                    if let rest = restTimer {
                        let remaining = rest.secondsRemaining(nowEpochMillis: nowEpochMillis)
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
                                isMuted: restMuted,
                                onToggleMute: { restMuted.toggle() }
                            )
                            .padding(.bottom, 16)
                        }
                    }
                }
            }

            if isWarningVisible, let warning = warningNoticeMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppColors.danger)
                        Text(warning)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppColors.danger)
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
                    .padding(.bottom, restTimer != nil ? 96 : 24)
                }
                .animation(.easeInOut(duration: 0.25), value: isWarningVisible)
            }

            ToastOverlay(message: store.noticeMessage)
        }
        .onReceive(timer) { _ in
            nowEpochMillis = Int64(Date().timeIntervalSince1970 * 1000)
            checkRestTimerAlarm()
        }
        .alert(LanguageManager.t("session.exit"), isPresented: $showExitConfirmation) {
            Button(LanguageManager.t("modal.cancel"), role: .cancel) {}
            Button(LanguageManager.t("session.exit"), role: .destructive) {
                store.abandonActiveSession()
            }
        } message: {
            Text(LanguageManager.t("session.exitConfirm"))
        }
    }

    // MARK: - Actions

    private func showEmptyWarning() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        warningNoticeMessage = LanguageManager.t("notice.emptySetWarning")
        withAnimation(.easeOut(duration: 0.28)) {
            isWarningVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeIn(duration: 0.24)) {
                isWarningVisible = false
            }
        }
    }

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
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            guard sets.indices.contains(index) else { return copy }
            let wKg = Double(weight)
            let rInt = Int(reps).flatMap { $0 > 0 ? $0 : nil }
            sets[index] = ExerciseSetLog(
                id: sets[index].id,
                setNumber: sets[index].setNumber,
                weightInput: weight,
                repsInput: reps,
                weightKg: wKg,
                completedReps: rInt,
                isCompleted: sets[index].isCompleted,
                inputTouched: true
            )
            copy.setsByExercise[exerciseId] = sets
            return copy
        }
    }

    private func toggleSet(exercise: Exercise, index: Int) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exercise.id] ?? []
            guard sets.indices.contains(index) else { return copy }
            let currentSet = sets[index]
            let isRestActive = (copy.restTimer?.secondsRemaining(nowEpochMillis: nowEpochMillis) ?? 0) > 0
            if !currentSet.isCompleted && (isRestActive || !WorkoutSessionUtils.canCompleteSet(currentSet) || !WorkoutSessionUtils.isSetEnabled(sets: sets, index: index)) {
                return copy
            }
            let willComplete = !currentSet.isCompleted
            sets[index].isCompleted = willComplete
            if willComplete, sets.indices.contains(index + 1) {
                sets[index + 1] = WorkoutSessionUtils.prefillSet(sets[index + 1], from: currentSet)
            }
            copy.setsByExercise[exercise.id] = sets

            if willComplete {
                FormAudioPlayer.playSetCompleteSound()
                let restSecs = RestTimerUtils.restSeconds(for: exercise)
                if restSecs > 0 {
                    let endEpoch = nowEpochMillis + Int64(restSecs * 1000)
                    copy.restTimer = RestTimerState(
                        exerciseName: exercise.name,
                        totalSeconds: restSecs,
                        isRunning: true,
                        endsAtEpochMillis: endEpoch,
                        pausedSecondsRemaining: restSecs
                    )
                }
            } else {
                FormAudioPlayer.playSetUndoSound()
            }
            return copy
        }
    }

    private func presentWorkoutSummary() {
        FormAudioPlayer.playWorkoutCompleteSound()
        finishedAt = Int64(Date().timeIntervalSince1970 * 1000)
        showSummary = true
    }

    private func addSet(exerciseId: String) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            sets.append(WorkoutSessionUtils.prefillSet(ExerciseSetLog(
                setNumber: sets.count + 1,
                isCompleted: false
            ), from: sets.last))
            copy.setsByExercise[exerciseId] = sets
            return copy
        }
    }

    private func removeSet(exerciseId: String, index: Int) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            guard sets.indices.contains(index) else { return copy }
            sets.remove(at: index)
            for i in 0..<sets.count {
                sets[i] = ExerciseSetLog(
                    id: sets[i].id,
                    setNumber: i + 1,
                    weightInput: sets[i].weightInput,
                    repsInput: sets[i].repsInput,
                    weightKg: sets[i].weightKg,
                    completedReps: sets[i].completedReps,
                    isCompleted: sets[i].isCompleted,
                    inputTouched: sets[i].inputTouched
                )
            }
            copy.setsByExercise[exerciseId] = sets
            return copy
        }
    }

    private func toggleRest() {
        store.updateActiveSession { d in
            var copy = d
            guard var timer = copy.restTimer else { return copy }
            if timer.isRunning {
                let remaining = timer.secondsRemaining(nowEpochMillis: nowEpochMillis)
                timer.isRunning = false
                timer.endsAtEpochMillis = nil
                timer.pausedSecondsRemaining = remaining
            } else if timer.pausedSecondsRemaining > 0 {
                timer.isRunning = true
                timer.endsAtEpochMillis = nowEpochMillis + Int64(timer.pausedSecondsRemaining * 1000)
            }
            copy.restTimer = timer
            return copy
        }
    }

    private func adjustRest(seconds: Int) {
        store.updateActiveSession { d in
            var copy = d
            guard var timer = copy.restTimer else { return copy }
            let remaining = max(0, timer.secondsRemaining(nowEpochMillis: nowEpochMillis) + seconds)
            timer.totalSeconds = max(timer.totalSeconds, remaining)
            timer.pausedSecondsRemaining = remaining
            if timer.isRunning && remaining > 0 {
                timer.endsAtEpochMillis = nowEpochMillis + Int64(remaining * 1000)
            } else {
                timer.isRunning = false
                timer.endsAtEpochMillis = nil
            }
            copy.restTimer = timer
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
        guard let rest = currentDraft.restTimer, rest.isRunning, let end = rest.endsAtEpochMillis else { return }
        if nowEpochMillis >= end {
            FormAudioPlayer.playRestCompleteSound()
            skipRest()
        }
    }
}
