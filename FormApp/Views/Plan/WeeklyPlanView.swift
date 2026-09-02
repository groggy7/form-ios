import SwiftUI

public struct WeeklyPlanView: View {
    @ObservedObject var store: AppStore
    var onOpenPrograms: () -> Void
    var onOpenSettings: () -> Void
    var onSelectWorkout: (String) -> Void

    public init(
        store: AppStore,
        onOpenPrograms: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSelectWorkout: @escaping (String) -> Void
    ) {
        self.store = store
        self.onOpenPrograms = onOpenPrograms
        self.onOpenSettings = onOpenSettings
        self.onSelectWorkout = onSelectWorkout
    }

    public var body: some View {
        let program = store.activeProgram
        let calendar = store.weekCalendar
        let completed = store.state.completed
        let unfinished = store.unfinishedWorkoutKeys()

        ScrollView {
            VStack(spacing: 20) {
                AppHeader(
                    title: LanguageManager.t("nav.plan"),
                    subtitle: program?.name,
                    onSubtitleClick: onOpenPrograms,
                    onSettingsClick: onOpenSettings
                )

                // 7-day cards
                VStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        let dayName = LanguageManager.workoutDays.indices.contains(index) ? LanguageManager.workoutDays[index] : ""
                        let dayNumber = calendar.numbers.indices.contains(index) ? calendar.numbers[index] : index + 1
                        let workout = program?.workouts.first { $0.day == index + 1 }
                        let workoutKey = workout.map { "\(program?.id ?? ""):\($0.id)" } ?? ""
                        let isCompleted = completed.contains(workoutKey)
                        let isUnfinished = !isCompleted && unfinished.contains(workoutKey)
                        let isToday = index == calendar.today

                        Button(action: {
                            if let w = workout {
                                onSelectWorkout(w.id)
                            }
                        }) {
                            HStack(spacing: 0) {
                                // Day column
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(String(dayName.prefix(3)).uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isToday ? AppColors.accent : (isUnfinished ? AppColors.unfinishedText : AppColors.muted))
                                    Text("\(dayNumber)")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(AppColors.text)
                                }
                                .frame(width: 46, alignment: .leading)

                                Spacer().frame(width: 14)

                                // Title and meta
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(workout?.title ?? LanguageManager.t("plan.recover"))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(workout == nil ? AppColors.muted : AppColors.text)
                                        .lineLimit(1)

                                    let subtitle: String = {
                                        if isUnfinished { return LanguageManager.t("history.unfinished") }
                                        if let w = workout { return LanguageManager.t("weekly.exerciseCount", ["count": w.exercises.count]) }
                                        return LanguageManager.t("weekly.restDay")
                                    }()

                                    Text(subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(isUnfinished ? AppColors.unfinishedText.opacity(0.8) : AppColors.muted)
                                }

                                Spacer()

                                if isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(AppColors.positive)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, workout == nil ? 10 : 12)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(AppColors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(
                                                isToday ? AppColors.accent.opacity(0.8) : (isUnfinished ? AppColors.unfinishedBorder : AppColors.border),
                                                lineWidth: isToday ? 2 : 1
                                            )
                                    )
                            )
                        }
                        .disabled(workout == nil)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // Change program button
                Button(action: onOpenPrograms) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 15, weight: .semibold))
                        Text(LanguageManager.t("weekly.changeProgram"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .foregroundColor(AppColors.accent)
                }
                .padding(.horizontal, 20)
                .buttonStyle(.plain)

                Spacer().frame(height: 100)
            }
        }
    }
}
