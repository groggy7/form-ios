import SwiftUI

public struct WeeklyPlanView: View {
    @ObservedObject var store: AppStore
    var onOpenToday: () -> Void
    var onOpenPrograms: () -> Void
    var onOpenSettings: () -> Void

    public init(
        store: AppStore,
        onOpenToday: @escaping () -> Void,
        onOpenPrograms: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.onOpenToday = onOpenToday
        self.onOpenPrograms = onOpenPrograms
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        guard let program = store.activeProgram else {
            return AnyView(EmptyView())
        }

        let calendar = store.weekCalendar
        let completedKeys = store.state.completed
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let activeWorkout = store.activeWorkout

        return AnyView(
            ScrollView {
                VStack(spacing: 20) {
                    // Header row
                    HStack(alignment: .top) {
                        Button(action: onOpenPrograms) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LanguageManager.t("weekly.title"))
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundColor(AppColors.text)

                                HStack(spacing: 4) {
                                    Text(program.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppColors.accent)
                                        .lineLimit(1)

                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        FormHeaderIconButton(
                            icon: "gearshape.fill",
                            contentDescription: LanguageManager.t("settings.title"),
                            onClick: onOpenSettings
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // 7 Weekday cards
                    VStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { index in
                            let workout = program.workouts.first(where: { $0.day == index + 1 })
                            let selected = workout?.id == activeWorkout?.id
                            let workoutKey = workout.map { "\(program.id):\($0.id)" } ?? ""
                            let isCompleted = !workoutKey.isEmpty && completedKeys.contains(workoutKey)
                            let isUnfinished = !workoutKey.isEmpty && !isCompleted && unfinishedKeys.contains(workoutKey)
                            let isToday = index == calendar.today
                            let dayName = LanguageManager.workoutDays.indices.contains(index)
                                ? LanguageManager.workoutDays[index]
                                : ""
                            let dayNumber = calendar.numbers.indices.contains(index)
                                ? calendar.numbers[index]
                                : (index + 1)

                            Button(action: {
                                if let w = workout {
                                    store.selectedWorkoutId = w.id
                                    onOpenToday()
                                }
                            }) {
                                HStack(spacing: 14) {
                                    // Day short & date number column
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(String(dayName.prefix(3)).uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(isToday ? AppColors.accent : (isUnfinished ? Color(hex: 0xFDE8CC) : AppColors.muted))

                                        Text("\(dayNumber)")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                    }
                                    .frame(width: 46, alignment: .leading)

                                    // Workout title & subtitle
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workout?.title ?? LanguageManager.t("plan.recover"))
                                            .font(.system(size: 15, weight: selected ? .bold : .semibold))
                                            .foregroundColor(workout == nil ? AppColors.muted : AppColors.text)
                                            .lineLimit(1)

                                        Text(workoutSubtitle(workout: workout, isUnfinished: isUnfinished))
                                            .font(.system(size: 12))
                                            .foregroundColor(isUnfinished ? Color(hex: 0xFDE8CC).opacity(0.8) : AppColors.muted)
                                    }

                                    Spacer()

                                    if isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(AppColors.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(minHeight: workout == nil ? 56 : 64)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(AppColors.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(
                                            isToday ? AppColors.accent.opacity(0.8) : (isUnfinished ? Color(hex: 0x664923) : AppColors.border),
                                            lineWidth: isToday ? 2 : 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Change program outlined button
                    Button(action: onOpenPrograms) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 14, weight: .semibold))
                            Text(LanguageManager.t("weekly.changeProgram"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(AppColors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    Spacer().frame(height: 90) // Bottom dock spacing
                }
            }
        )
    }

    private func workoutSubtitle(workout: Workout?, isUnfinished: Bool) -> String {
        if isUnfinished {
            return LanguageManager.t("history.unfinished")
        }
        if let w = workout {
            return LanguageManager.t("weekly.exerciseCount", ["count": w.exercises.count])
        }
        return LanguageManager.t("weekly.restDay")
    }
}
