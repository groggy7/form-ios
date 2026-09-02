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
        let completedCount = program?.workouts.filter { store.state.completed.contains("\(program?.id ?? ""):\($0.id)") }.count ?? 0
        let totalWorkouts = program?.workouts.count ?? 0

        ScrollView {
            VStack(spacing: 20) {
                // Header with "This week" and dates range
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("today.thisWeek"))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(AppColors.text)

                        Text(formattedWeekRange())
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.muted)
                    }

                    Spacer()

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 44, height: 44)
                            .background(AppColors.surface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // 7-day strip
                WeekStripView(store: store) { workoutId in
                    store.selectedWorkoutId = workoutId
                }

                // Today card (Workout or Rest day)
                TodayHeroCard(
                    workout: workout,
                    todayIndex: store.weekCalendar.today,
                    isCompleted: isCompleted,
                    isAvailable: isAvailable,
                    onStart: {
                        if let w = workout, let p = program {
                            _ = store.startActiveSession(programId: p.id, workout: w)
                        }
                    }
                )

                // Weekly progress bar
                VStack(spacing: 8) {
                    HStack {
                        Text(LanguageManager.t("today.weekProgress"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Text("\(completedCount) / \(totalWorkouts)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.surfaceRaised)
                                .frame(height: 4)
                            Capsule()
                                .fill(AppColors.accent)
                                .frame(width: totalWorkouts > 0 ? geo.size.width * CGFloat(completedCount) / CGFloat(totalWorkouts) : 0, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, 20)

                // Exercise list preview
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
                                            .font(.system(size: 13, weight: .bold))
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
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(AppColors.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 13, style: .continuous)
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

                Spacer().frame(height: 100) // Padding for bottom dock
            }
        }
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
