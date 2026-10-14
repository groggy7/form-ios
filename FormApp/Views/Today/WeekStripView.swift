import SwiftUI

public enum WorkoutVisualRegion {
    case upper
    case lower
    case fullBody
}

public extension Workout {
    var visualRegion: WorkoutVisualRegion {
        if let first = resolvedMuscles.first?.views.first {
            switch first {
            case .back, .front: return .upper
            case .legsFront, .legsBack: return .lower
            }
        }
        var hasUpper = false
        var hasLower = false
        for ex in exercises {
            switch ex.resolvedMovement {
            case .press, .pullUp, .row, .shoulderRaise, .curl, .triceps:
                hasUpper = true
            case .squat, .hinge, .lunge, .calf:
                hasLower = true
            case .core:
                break
            case .conditioning, .boxing, .other:
                return .fullBody
            }
        }
        if hasUpper && !hasLower { return .upper }
        if hasLower && !hasUpper { return .lower }
        return .fullBody
    }
}

public struct WeekStripView: View {
    @ObservedObject var store: AppStore
    var onSelectWorkout: (String) -> Void

    public init(store: AppStore, onSelectWorkout: @escaping (String) -> Void) {
        self.store = store
        self.onSelectWorkout = onSelectWorkout
    }

    public var body: some View {
        guard let program = store.activeProgram, !program.workouts.isEmpty else {
            return AnyView(EmptyView())
        }

        let workouts = (0..<7).compactMap { dayIndex in
            program.workouts.first(where: { $0.day == dayIndex + 1 })
        }

        let calendar = store.weekCalendar
        let completedKeys = store.state.completed
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let activeWorkout = store.activeWorkout

        return AnyView(WorkoutDayStrip(
            program: program, workouts: workouts, calendar: calendar,
            activeWorkoutId: activeWorkout?.id, completedKeys: completedKeys,
            unfinishedKeys: unfinishedKeys, onSelectWorkout: onSelectWorkout
        ))
    }
}

struct WorkoutDayStrip: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let program: Program
    let workouts: [Workout]
    let calendar: WeekCalendar
    let activeWorkoutId: String?
    let completedKeys: [String]
    let unfinishedKeys: Set<String>
    let onSelectWorkout: (String) -> Void

    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 25

    private var initialScrollAnchor: UnitPoint {
        // Four tiles fit on phones. Advance the window from the third workout,
        // retaining the most recent workout's window on intervening rest days.
        let currentIndex = workouts.lastIndex { $0.day <= calendar.today + 1 } ?? -1
        let lastWindowIndex = max(0, workouts.count - 4)
        let firstIndex = min(lastWindowIndex, max(0, currentIndex - 1))
        let fraction = lastWindowIndex > 0 ? CGFloat(firstIndex) / CGFloat(lastWindowIndex) : 0
        return UnitPoint(x: fraction, y: 0)
    }

    var body: some View {
        let dayColors = AppColors.homeDayColors
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(workouts.enumerated()), id: \.element.id) { colorIndex, workout in
                        let dayIndex = workout.day - 1
                        let selected = workout.id == activeWorkoutId
                        let isToday = dayIndex == calendar.today
                        let workoutKey = "\(program.id):\(workout.id)"
                        let isCompleted = completedKeys.contains(workoutKey)
                        let isUnfinished = !isCompleted && unfinishedKeys.contains(workoutKey)
                        let isMissed = WeeklyPlanView.isMissedPlanDay(dayIndex: dayIndex, todayIndex: calendar.today,
                            hasWorkout: true, completed: isCompleted, unfinished: isUnfinished)
                        let dayNumber = calendar.numbers.indices.contains(dayIndex) ? calendar.numbers[dayIndex] : (dayIndex + 1)
                        let textColor = AppColors.text

                        let surfaceColor: Color = {
                            // The schedule slot is independent of selection and other day statuses.
                            if isCompleted { return dayColors.completed }
                            if isUnfinished { return dayColors.unfinished }
                            if isMissed { return dayColors.missed }
                            return dayColors.neutral[colorIndex % dayColors.neutral.count]
                        }()

                        let borderColor: Color = {
                            if selected { return AppColors.accent }
                            if isToday { return Color.mix(AppColors.border, AppColors.text, 0.35) }
                            if isCompleted { return Color.mix(AppColors.border, AppColors.completedGreen, 0.25) }
                            if isUnfinished { return Color.mix(AppColors.border, AppColors.unfinishedOrange, 0.25) }
                            if isMissed { return Color.mix(AppColors.border, AppColors.missedRed, 0.25) }
                            return Color.mix(AppColors.border, surfaceColor, 0.35)
                        }()
                        let statuses: [String?] = [
                            isToday ? LanguageManager.t("nav.today") : nil,
                            dayIndex > calendar.today ? LanguageManager.t("history.future") : nil,
                            isCompleted ? LanguageManager.t("history.completed") : nil,
                            isUnfinished ? LanguageManager.t("history.unfinished") : nil,
                            isMissed ? LanguageManager.t("history.missed") : nil
                        ]
                        let statusDescription = statuses.compactMap { $0 }.joined(separator: ", ")

                        Button(action: {
                            onSelectWorkout(workout.id)
                        }) {
                            VStack(spacing: 6) {
                                let dayLabel = LanguageManager.workoutDays.indices.contains(dayIndex)
                                    ? String(LanguageManager.workoutDays[dayIndex].prefix(3)).uppercased()
                                    : "DAY"

                                Text(dayLabel)
                                    .font(.system(size: labelSize, weight: .medium))
                                    .foregroundStyle(textColor)
                                    .lineLimit(1)

                                Text("\(dayNumber)")
                                    .font(.system(size: numberSize, weight: .semibold))
                                    .foregroundStyle(textColor)
                                    .lineLimit(1)

                                Text(workout.displayTitle(programId: program.id))
                                    .font(.system(size: labelSize))
                                    .foregroundStyle(textColor)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2, reservesSpace: true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                min(96, max(48, (width - 40 - 3 * 8) / 4))
                            }
                            .frame(minHeight: 108, alignment: .top)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(surfaceColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(borderColor, lineWidth: selected ? 2 : (isToday ? 1.5 : 1))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .id(workout.id)
                        .accessibilityIdentifier("today-day-\(workout.id)")
                        .accessibilityLabel("\(LanguageManager.workoutDays[dayIndex]), \(dayNumber), \(workout.displayTitle(programId: program.id))")
                        .accessibilityValue(statusDescription)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .defaultScrollAnchor(initialScrollAnchor)
            .onChange(of: activeWorkoutId, initial: true) { _, selectedId in
                if let selectedId { proxy.scrollTo(selectedId) }
            }
            .id(InitialWindowKey(programId: program.id, today: calendar.today,
                schedule: workouts.map { "\($0.id):\($0.day)" }))
        }
    }

    private struct InitialWindowKey: Hashable {
        let programId: String
        let today: Int
        let schedule: [String]
    }
}
