import SwiftUI

public struct WeeklyPlanView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @Environment(\.twoPageLayout) private var twoPageLayout
    var onOpenToday: () -> Void
    var onOpenPrograms: () -> Void
    var onOpenSettings: () -> Void
    var onSelectExercise: (Exercise) -> Void

    public init(
        store: AppStore,
        onOpenToday: @escaping () -> Void,
        onOpenPrograms: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSelectExercise: @escaping (Exercise) -> Void = { _ in }
    ) {
        self.store = store
        self.onOpenToday = onOpenToday
        self.onOpenPrograms = onOpenPrograms
        self.onOpenSettings = onOpenSettings
        self.onSelectExercise = onSelectExercise
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        guard let program = store.activeProgram else {
            return AnyView(EmptyView())
        }

        var calendar = store.weekCalendar
        calendar.missedDays = store.missedDaysThisWeek()
        let completedKeys = store.state.completed
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let activeWorkout = store.activeWorkout

        let planColumn = VStack(spacing: 20) {
            // Header row
            HStack(alignment: .center) {
                Text(LanguageManager.t("weekly.title"))
                    .font(.app(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.text)

                Spacer()

                FormHeaderIconButton(
                    icon: "gearshape.fill",
                    contentDescription: LanguageManager.t("settings.title"),
                    onClick: onOpenSettings
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Active program and 7 weekday cards
            VStack(alignment: .leading, spacing: 8) {
                Text(program.displayName)
                    .font(.app(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                ForEach(0..<7, id: \.self) { index in
                    let workout = program.workouts.first(where: { $0.day == index + 1 && !$0.exercises.isEmpty })
                    let selected = workout?.id == activeWorkout?.id
                    let workoutKey = workout.map { "\(program.id):\($0.id)" } ?? ""
                    let isCompleted = !workoutKey.isEmpty && completedKeys.contains(workoutKey)
                    let isUnfinished = !workoutKey.isEmpty && !isCompleted && unfinishedKeys.contains(workoutKey)
                    let isMissed = Self.isMissedPlanDay(dayIndex: index, todayIndex: calendar.today,
                                                       missedDays: calendar.missedDays, hasWorkout: workout != nil, completed: isCompleted, unfinished: isUnfinished)
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
                            // Two pages show the day beside the week instead of switching to Home.
                            if twoPageLayout == nil { onOpenToday() }
                        }
                    }) {
                        HStack(spacing: 14) {
                            // Day short & date number column
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(dayName.prefix(3)).uppercased())
                                    .font(.app(size: 10, weight: .bold))
                                    .foregroundStyle(isToday ? AppColors.accent : (isUnfinished ? AppColors.unfinishedText : AppColors.muted))

                                Text("\(dayNumber)")
                                    .font(.app(size: 18, weight: .bold))
                                    .foregroundStyle(AppColors.text)
                            }
                            .frame(width: 46, alignment: .leading)

                            // Workout title & subtitle
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout?.displayTitle(programId: program.id) ?? LanguageManager.t("plan.recover"))
                                    .font(.app(size: 15, weight: selected ? .bold : .semibold))
                                    .foregroundStyle(workout == nil ? AppColors.muted : AppColors.text)
                                    .lineLimit(1)

                                Text(Self.workoutSubtitle(workout: workout, isUnfinished: isUnfinished, isMissed: isMissed))
                                    .font(.app(size: 12))
                                    .foregroundStyle(isUnfinished ? AppColors.unfinishedText.opacity(0.8) : AppColors.muted)
                            }

                            Spacer()

                            if isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppColors.accent)
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
                                    isToday ? AppColors.accent.opacity(0.8)
                                        : (isCompleted && index < calendar.today ? AppColors.completedDayBorder
                                            : (isUnfinished ? AppColors.unfinishedBorder
                                                : (isMissed ? AppColors.missedDayBorder : AppColors.border))),
                                    lineWidth: isToday ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .tourTarget("plan.days", cornerRadius: 13)
            .padding(.horizontal, 20)

            // Change program outlined button
            Button(action: onOpenPrograms) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .semibold))
                    Text(LanguageManager.t("weekly.changeProgram"))
                        .font(.app(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.text)
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
            .tourTarget("plan.change", cornerRadius: 12)
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Spacer().frame(height: 16)
        }

        if let twoPageLayout {
            // Open foldable: the week on the left, the selected day's card and exercises on the right.
            return AnyView(
                TwoPageSpread(layout: twoPageLayout) {
                    ScrollViewReader { proxy in
                    ScrollView {
                        planColumn
                    }
                    .tourScrollable(proxy)
                    }
                } trailing: {
                    ScrollView {
                        VStack(spacing: 16) {
                            HomeWorkoutHero(store: store, workout: activeWorkout, showsRestGuidance: false)
                            if let activeWorkout, !activeWorkout.exercises.isEmpty {
                                WorkoutExercisePreview(store: store, workout: activeWorkout, registersTourTargets: false,
                                                       onSelectExercise: onSelectExercise)
                            }
                            Spacer().frame(height: 16)
                        }
                        .padding(.top, 10)
                    }
                }
            )
        }

        return AnyView(
            ScrollViewReader { proxy in
            ScrollView {
                planColumn
            }
            .tourScrollable(proxy)
            }
        )
    }

    /// The plan shows the current Monday–Sunday week; today's workout is never overdue. An earlier day is missed only
    /// when the Progress calendar's saved schedule says so (`missedDays`), so days before the plan existed stay neutral.
    static func isMissedPlanDay(dayIndex: Int, todayIndex: Int, missedDays: Set<Int>, hasWorkout: Bool,
                                completed: Bool, unfinished: Bool) -> Bool {
        (0..<7).contains(dayIndex) && (0..<7).contains(todayIndex) && dayIndex < todayIndex
            && missedDays.contains(dayIndex) && hasWorkout && !completed && !unfinished
    }

    static func workoutSubtitle(workout: Workout?, isUnfinished: Bool, isMissed: Bool) -> String {
        if let w = workout {
            let count = LanguageManager.t("weekly.exerciseCount", ["count": w.exercises.count])
            if isUnfinished { return "\(count) · \(LanguageManager.t("history.unfinished"))" }
            if isMissed { return "\(count) · \(LanguageManager.t("history.missed"))" }
            return count
        }
        return LanguageManager.t("weekly.restDay")
    }
}
