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
        let glass = AppColors.homeDayGlassColors
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workouts) { workout in
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

                        let statusTint: Color? = {
                            if isCompleted { return AppColors.completedGreen }
                            if isUnfinished { return AppColors.unfinishedOrange }
                            if isMissed { return AppColors.missedRed }
                            return nil
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
                                HomeDayGlassSurface(glass: glass, statusTint: statusTint,
                                    isDark: themeManager.currentTheme.isDark,
                                    selected: selected, today: isToday, accent: AppColors.accent)
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

// Static optical layers match Android's dayTileGlass without live blur or animation.
private struct HomeDayGlassSurface: View {
    let glass: AppColors.HomeDayGlassColors
    let statusTint: Color?
    let isDark: Bool
    let selected: Bool
    let today: Bool
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func rounded(_ inset: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset),
                     cornerRadius: max(0, 20 - inset))
            }
            let shape = rounded(0)
            context.clip(to: shape)
            context.fill(shape, with: .color(glass.base))
            context.fill(shape, with: .linearGradient(Gradient(stops: [
                .init(color: glass.shade.opacity(0), location: 0),
                .init(color: glass.shade.opacity(isDark ? 0.12 : 0.04), location: 0.55),
                .init(color: glass.shade.opacity(0), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))

            let light = statusTint ?? glass.neutralRim
            context.fill(shape, with: .radialGradient(Gradient(colors: [
                light.opacity(statusTint != nil ? 0.18 : 0.10), light.opacity(0)
            ]), center: CGPoint(x: w * 0.08, y: h * 0.98), startRadius: 0, endRadius: w * 0.90))
            context.fill(shape, with: .radialGradient(Gradient(colors: [
                light.opacity(statusTint != nil ? 0.08 : 0.04), light.opacity(0)
            ]), center: CGPoint(x: w * 0.95, y: h * 0.02), startRadius: 0, endRadius: w * 0.75))

            var topReflection = Path()
            topReflection.move(to: CGPoint(x: 0, y: h * 0.62))
            topReflection.addCurve(to: CGPoint(x: w, y: h * 0.02),
                control1: CGPoint(x: w * 0.10, y: h * 0.24),
                control2: CGPoint(x: w * 0.45, y: h * 0.08))
            topReflection.addLine(to: CGPoint(x: w, y: 0))
            topReflection.addLine(to: .zero)
            topReflection.closeSubpath()
            context.fill(topReflection, with: .linearGradient(Gradient(stops: [
                .init(color: glass.reflection.opacity(isDark ? 0.18 : 0.48), location: 0),
                .init(color: glass.reflection.opacity(0.03), location: 0.55),
                .init(color: glass.reflection.opacity(0), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: w * 0.85, y: h * 0.65)))

            var lowerReflection = Path()
            lowerReflection.move(to: CGPoint(x: w, y: h * 0.55))
            lowerReflection.addCurve(to: CGPoint(x: 0, y: h),
                control1: CGPoint(x: w * 0.83, y: h * 0.88),
                control2: CGPoint(x: w * 0.53, y: h * 0.96))
            lowerReflection.addLine(to: CGPoint(x: w, y: h))
            lowerReflection.closeSubpath()
            context.fill(lowerReflection, with: .color(glass.reflection.opacity(isDark ? 0.04 : 0.18)))

            // Keep the status-lit inner rim when selection or today adds an outer ring.
            let rimPath = rounded(selected || today ? 3.5 : 0.75)
            context.stroke(rimPath, with: .color(light.opacity(statusTint != nil ? 0.14 : 0.06)), lineWidth: 4)
            context.stroke(rimPath, with: .linearGradient(Gradient(stops: [
                .init(color: Color.mix(light, glass.reflection, 0.28).opacity(isDark ? 0.90 : 0.70), location: 0),
                .init(color: light.opacity(statusTint != nil ? 0.38 : 0.22), location: 0.45),
                .init(color: light.opacity(statusTint != nil ? 0.80 : 0.50), location: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)), lineWidth: 1)
            if selected {
                context.stroke(rounded(1), with: .color(accent), lineWidth: 2)
            } else if today {
                context.stroke(rounded(0.75), with: .color(glass.neutralRim.opacity(0.65)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
