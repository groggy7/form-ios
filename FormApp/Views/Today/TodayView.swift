import SwiftUI

public struct TodayView: View {
    @ObservedObject var store: AppStore
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
        let program = store.activeProgram
        let workout = store.activeWorkout
        let isToday = workout?.day == store.currentWeekDayNumber()
        let workoutKey = workout.map { "\(program?.id ?? ""):\($0.id)" } ?? ""
        let isCompleted = store.state.completed.contains(workoutKey)
        let isAvailable = workout.map { store.canStartWorkout($0) } ?? false

        ScrollView {
            VStack(spacing: 20) {
                AppHeader(
                    title: LanguageManager.t("today.title"),
                    subtitle: program?.name,
                    onSubtitleClick: onOpenPrograms,
                    onSettingsClick: onOpenSettings
                )

                WeekStripView(store: store) { workoutId in
                    store.selectedWorkoutId = workoutId
                }

                TodayHeroCard(
                    workout: workout,
                    isToday: isToday,
                    isCompleted: isCompleted,
                    isAvailable: isAvailable,
                    onStart: {
                        if let w = workout, let p = program {
                            _ = store.startActiveSession(programId: p.id, workout: w)
                        }
                    }
                )

                if let workout = workout, !workout.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LanguageManager.t("today.exercises"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .padding(.horizontal, 20)

                        VStack(spacing: 8) {
                            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                                Button(action: { onSelectExercise(exercise) }) {
                                    HStack(spacing: 14) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(AppColors.muted)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(exercise.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppColors.text)
                                                .lineLimit(1)

                                            Text(exercise.displayPrescription)
                                                .font(.system(size: 13))
                                                .foregroundColor(AppColors.muted)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppColors.muted.opacity(0.6))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(AppColors.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer().frame(height: 100) // Padding for dock
            }
        }
    }
}
