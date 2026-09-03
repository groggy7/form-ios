import SwiftUI

public struct ActiveSessionView: View {
    @ObservedObject var store: AppStore
    let draft: ActiveSessionDraft

    @State private var nowEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    @State private var showExitConfirmation: Bool = false
    @State private var showSummary: Bool = false
    @State private var finishedAt: Int64? = nil
    @State private var restMuted: Bool = false

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public init(store: AppStore, draft: ActiveSessionDraft) {
        self.store = store
        self.draft = draft
    }

    public var body: some View {
        let effectiveNow = showSummary ? (finishedAt ?? nowEpochMillis) : nowEpochMillis
        let progress = SessionProgress.from(draft: draft, nowEpochMillis: effectiveNow)
        let exercises = draft.workout.exercises
        let currentIndex = min(max(0, draft.currentExerciseIndex), max(0, exercises.count - 1))
        let currentExercise = exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
        let currentSets = currentExercise.map { draft.setsByExercise[$0.id] ?? [] } ?? []
        let restTimer = draft.restTimer

        ZStack {
            AppColors.background.ignoresSafeArea()

            if showSummary {
                SessionSummaryView(
                    workoutTitle: draft.workout.title,
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
                        let record = SessionProgress.from(draft: draft, nowEpochMillis: completedAt)
                            .record(draft: draft, completedAtEpochMillis: completedAt)
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
                            Text(draft.workout.title)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppColors.text)
                                .lineLimit(1)
                            Text(RestTimerUtils.formatSecondsToTime(progress.durationSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppColors.accent)
                        }

                        Spacer()

                        Button(action: {
                            FormAudioPlayer.playWorkoutStartSound()
                            finishedAt = Int64(Date().timeIntervalSince1970 * 1000)
                            showSummary = true
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
                                            let sets = draft.setsByExercise[ex.id] ?? []
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
                                                            name: ex.name,
                                                            size: 48,
                                                            movementType: ex.resolvedMovement,
                                                            movementAssetId: ex.movementAssetId
                                                        )

                                                        Text("\(idx + 1). \(ex.name)")
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
                                .onChange(of: currentIndex) { newIdx in
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
                                            Text(exercise.name)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundColor(AppColors.text)
                                            if !exercise.displayPrescription.isEmpty {
                                                Text(exercise.displayPrescription)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(AppColors.accent)
                                            }
                                        }
                                        Spacer()
                                        MovementIcon(
                                            name: exercise.name,
                                            size: 56,
                                            movementType: exercise.resolvedMovement,
                                            movementAssetId: exercise.movementAssetId
                                        )
                                    }

                                    SetLoggingTable(
                                        sets: currentSets,
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
                                        finishedAt = Int64(Date().timeIntervalSince1970 * 1000)
                                        showSummary = true
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Text(LanguageManager.t(currentIndex < exercises.count - 1 ? "session.nextExercise" : "session.review"))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
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
                            }
                            .padding(.horizontal, 20)

                            Spacer().frame(height: 120) // Space for floating rest timer
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
                isCompleted: sets[index].isCompleted
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
            let willComplete = !sets[index].isCompleted
            sets[index].isCompleted = willComplete
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
            }
            return copy
        }
    }

    private func addSet(exerciseId: String) {
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[exerciseId] ?? []
            let last = sets.last
            sets.append(ExerciseSetLog(
                setNumber: sets.count + 1,
                weightInput: last?.weightInput ?? "",
                repsInput: last?.repsInput ?? "",
                weightKg: last?.weightKg,
                completedReps: last?.completedReps,
                isCompleted: false
            ))
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
                    isCompleted: sets[i].isCompleted
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
        guard let rest = draft.restTimer, rest.isRunning, let end = rest.endsAtEpochMillis else { return }
        if nowEpochMillis >= end {
            FormAudioPlayer.playRestCompleteSound()
            skipRest()
        }
    }
}
