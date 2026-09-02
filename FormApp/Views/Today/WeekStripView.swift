import SwiftUI

public enum WorkoutVisualRegion {
    case upper
    case lower
    case fullBody

    var daySurface: Color {
        switch self {
        case .upper: return Color(hex: 0x292539)
        case .lower: return Color(hex: 0x202D3D)
        case .fullBody: return Color(hex: 0x292F38)
        }
    }

    var dayBorder: Color {
        switch self {
        case .upper: return Color(hex: 0x494260)
        case .lower: return Color(hex: 0x37485F)
        case .fullBody: return Color(hex: 0x414C57)
        }
    }

    var dayText: Color {
        switch self {
        case .upper: return Color(hex: 0xE3DAF1)
        case .lower: return Color(hex: 0xD2E2F5)
        case .fullBody: return Color(hex: 0xDBE2E9)
        }
    }
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

        let fitsViewport = workouts.count <= 5

        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workouts, id: \.id) { workout in
                        let dayIndex = workout.day - 1
                        let selected = workout.id == activeWorkout?.id
                        let isToday = dayIndex == calendar.today
                        let workoutKey = "\(program.id):\(workout.id)"
                        let isCompleted = completedKeys.contains(workoutKey)
                        let isUnfinished = !isCompleted && unfinishedKeys.contains(workoutKey)
                        let dayNumber = calendar.numbers.indices.contains(dayIndex) ? calendar.numbers[dayIndex] : (dayIndex + 1)
                        let palette = workout.visualRegion

                        let textColor: Color = {
                            if selected { return Color(hex: 0x1A2026) }
                            if isCompleted { return Color(hex: 0xD8F3E5) }
                            if isUnfinished { return Color(hex: 0xFDE8CC) }
                            return palette.dayText
                        }()

                        let surfaceColor: Color = {
                            if selected { return Color(hex: 0xEEE8DC) }
                            if isCompleted { return Color(hex: 0x1B332B) }
                            if isUnfinished { return Color(hex: 0x332717) }
                            return palette.daySurface
                        }()

                        let borderColor: Color = {
                            if selected { return Color(hex: 0xEEE8DC) }
                            if isToday { return Color(hex: 0xEEE8DC).opacity(0.7) }
                            if isCompleted { return Color(hex: 0x2D5949) }
                            if isUnfinished { return Color(hex: 0x664923) }
                            return palette.dayBorder
                        }()

                        Button(action: {
                            onSelectWorkout(workout.id)
                        }) {
                            VStack(spacing: 6) {
                                let dayLabel = LanguageManager.workoutDays.indices.contains(dayIndex)
                                    ? String(LanguageManager.workoutDays[dayIndex].prefix(3)).uppercased()
                                    : "DAY"

                                Text(dayLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(textColor)
                                    .lineLimit(1)

                                Text("\(dayNumber)")
                                    .font(.system(size: 25, weight: .semibold))
                                    .foregroundColor(textColor)
                                    .lineLimit(1)

                                Text(workout.title)
                                    .font(.system(size: 11))
                                    .foregroundColor(textColor)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .frame(width: fitsViewport ? (UIScreen.main.bounds.width - 40 - CGFloat(workouts.count - 1) * 8) / CGFloat(workouts.count) : 72)
                            .frame(minHeight: 108)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(surfaceColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(borderColor, lineWidth: (isToday && !selected) ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        )
    }
}
