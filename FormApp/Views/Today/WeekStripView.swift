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

        return AnyView(WorkoutDayStrip(
            program: program, workouts: workouts, calendar: calendar,
            activeWorkoutId: activeWorkout?.id, completedKeys: completedKeys,
            unfinishedKeys: unfinishedKeys, onSelectWorkout: onSelectWorkout
        ))
    }
}

struct WorkoutDayStrip: View {
    let program: Program
    let workouts: [Workout]
    let calendar: WeekCalendar
    let activeWorkoutId: String?
    let completedKeys: [String]
    let unfinishedKeys: Set<String>
    let onSelectWorkout: (String) -> Void

    @ScaledMetric(relativeTo: .caption2) private var minimumTileWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .caption2) private var minimumTileHeight: CGFloat = 108
    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 25

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workouts, id: \.id) { workout in
                        let dayIndex = workout.day - 1
                        let selected = workout.id == activeWorkoutId
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
                                    .font(.system(size: labelSize, weight: .medium))
                                    .foregroundColor(textColor)
                                    .lineLimit(1)

                                Text("\(dayNumber)")
                                    .font(.system(size: numberSize, weight: .semibold))
                                    .foregroundColor(textColor)
                                    .lineLimit(1)

                                Text(workout.displayTitle(programId: program.id))
                                    .font(.system(size: labelSize))
                                    .foregroundColor(textColor)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                max(minimumTileWidth, (width - 40 - CGFloat(workouts.count - 1) * 8) / CGFloat(max(workouts.count, 1)))
                            }
                            .frame(minHeight: minimumTileHeight, alignment: .top)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(surfaceColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(borderColor, lineWidth: (isToday && !selected) ? 2 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .id(workout.id)
                        .accessibilityIdentifier("today-day-\(workout.id)")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onChange(of: activeWorkoutId, initial: true) { _, selectedId in
                if let selectedId { proxy.scrollTo(selectedId) }
            }
        }
    }
}
