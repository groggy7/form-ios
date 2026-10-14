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
        let isDark = themeManager.currentTheme.isDark
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
                            if isCompleted { return glass.completedLight }
                            if isUnfinished { return glass.unfinishedLight }
                            if isMissed { return glass.missedLight }
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
                                    .font(.system(size: labelSize, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(textColor)
                                    .lineLimit(1)

                                Text("\(dayNumber)")
                                    .font(.system(size: numberSize, weight: .bold))
                                    .foregroundStyle(textColor)
                                    .shadow(color: isDark ? (statusTint ?? glass.neutralRim).opacity(0.35) : .clear, radius: 5)
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
                                HomeDayGlassSurface(glass: glass, statusTint: statusTint, isDark: isDark,
                                    selected: selected, today: isToday, accent: AppColors.accent)
                                    .padding(-HomeDayGlassSurface.margin)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: HomeDayGlassSurface.radius, style: .continuous))
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
            .scrollClipDisabled()
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

// MARK: - Home day tile glass
//
// Static optical layers shared with Android's `dayTileGlass` (WorkoutWeekStrip.kt): keep geometry, stops
// and alphas in sync. Draw order: outer bloom, tinted body, edge glow, corner lights, sheens, sweep rim.
// Every light fades to the same colour at alpha 0 so interpolation never shifts hue.
// See docs/design/form-design-system.md, "Home day tile glass".
private struct HomeGlassRecipe {
    /// Radial light; `radius` is a fraction of the tile width.
    struct Light { let alpha: Double; let radius: Double }
    struct Rim { let base: Double; let slope: Double; let whiteStart: Double; let whiteScale: Double }

    let body: Double
    let diagonal: Double
    let edgeAlpha: Double
    let edgeDecay: Double
    let topLeft: Light
    let topRight: Light
    let bottomLeft: Light
    let bottomRight: Light
    let sheenTop: Light
    let sheenBottom: Light
    let sheenWhite: Double
    let bloom: Double
    let rim: Rim

    static let status = HomeGlassRecipe(
        body: 0.055, diagonal: 0.06, edgeAlpha: 0.19, edgeDecay: 0.10,
        topLeft: Light(alpha: 0.54, radius: 0.260), topRight: Light(alpha: 0.545, radius: 0.215),
        bottomLeft: Light(alpha: 0.72, radius: 0.260), bottomRight: Light(alpha: 0.25, radius: 0.170),
        sheenTop: Light(alpha: 0.57, radius: 0.39), sheenBottom: Light(alpha: 0.13, radius: 0.53),
        sheenWhite: 0.58, bloom: 0.14,
        rim: Rim(base: 0.613, slope: 1.079, whiteStart: 0.602, whiteScale: 0.826))

    static let neutral = HomeGlassRecipe(
        body: 0.07, diagonal: 0.04, edgeAlpha: 0.17, edgeDecay: 0.078,
        topLeft: Light(alpha: 0.52, radius: 0.275), topRight: Light(alpha: 0.64, radius: 0.255),
        bottomLeft: Light(alpha: 0.38, radius: 0.225), bottomRight: Light(alpha: 0.20, radius: 0.130),
        sheenTop: Light(alpha: 0.39, radius: 0.435), sheenBottom: Light(alpha: 0.12, radius: 0.57),
        sheenWhite: 0.25, bloom: 0.09,
        rim: Rim(base: 0.30, slope: 1.182, whiteStart: 0.62, whiteScale: 0.956))

    /// Rim brightness by angle (degrees clockwise from 3 o'clock) for a 46.7° corner angle.
    static let rimLevels: [(angle: Double, level: Double)] = [
        (0, 0.86), (20, 0.75), (40, 0.51), (46.7, 0.70), (59, 0.62), (70, 0.48), (90, 0.50), (109, 0.46),
        (119, 0.72), (133.3, 0.93), (149, 0.55), (160, 0.47), (180, 0.53), (200, 0.71), (219, 0.71),
        (226.7, 0.97), (239, 0.85), (260, 0.54), (270, 0.46), (290, 0.56), (299, 0.72), (313.3, 0.98),
        (330, 0.69), (350, 0.84), (360, 0.86)
    ]
    static let referenceCornerAngle = 46.7

    /// Maps a reference rim angle onto this tile's aspect ratio, anchoring corners and edge midpoints.
    static func rimFraction(_ angle: Double, width: Double, height: Double) -> Double {
        let corner = atan2(height, width) * 180 / Double.pi
        let reference = [0, referenceCornerAngle, 90, 180 - referenceCornerAngle, 180,
                         180 + referenceCornerAngle, 270, 360 - referenceCornerAngle, 360]
        let actual = [0, corner, 90, 180 - corner, 180, 180 + corner, 270, 360 - corner, 360]
        for index in 1..<reference.count where angle <= reference[index] {
            let t = (angle - reference[index - 1]) / (reference[index] - reference[index - 1])
            return (actual[index - 1] + (actual[index] - actual[index - 1]) * t) / 360
        }
        return 1
    }

    /// Distances from a tile side, as fractions of the tile width, where the edge glow is sampled.
    /// Alpha is `edgeAlpha * exp(-distance / edgeDecay)`, reaching 0 at the last stop.
    static let edgeStops: [Double] = [0, 0.012, 0.03, 0.06, 0.10, 0.16, 0.25]

    /// Outward inflation factors (0...~1.2) for equal-alpha bloom layers.
    static func bloomInflations(peak: Double, alpha: Double, kappa: Double) -> [Double] {
        var inflations: [Double] = []
        for layer in 1...40 {
            let total = 1 - pow(1 - alpha, Double(layer))
            if total >= peak { break }
            inflations.append(log(peak / total) / kappa)
        }
        return inflations
    }
}

private struct HomeDayGlassSurface: View {
    static let radius: CGFloat = 14
    /// Room around the tile for the outer bloom; callers extend this view outward by the same amount.
    static let margin: CGFloat = 10

    let glass: AppColors.HomeDayGlassColors
    let statusTint: Color?
    let isDark: Bool
    let selected: Bool
    let today: Bool
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let edge = Self.margin
            let w = size.width - 2 * edge
            let h = size.height - 2 * edge
            guard w > 0, h > 0 else { return }
            let radius = Self.radius
            let tile = CGRect(x: edge, y: edge, width: w, height: h)
            func rounded(_ rect: CGRect, _ cornerRadius: CGFloat) -> Path {
                Path(roundedRect: rect, cornerRadius: max(0, cornerRadius), style: .continuous)
            }
            func insetPath(_ amount: CGFloat) -> Path {
                rounded(tile.insetBy(dx: amount, dy: amount), radius - amount)
            }
            let shape = insetPath(0)
            let hasStatus = statusTint != nil
            let recipe = hasStatus ? HomeGlassRecipe.status : HomeGlassRecipe.neutral
            let light = statusTint ?? glass.neutralRim
            let lightScale = isDark ? 1.0 : 0.55

            // 1. Bloom: faint light outside the rim; selection lights an otherwise neutral tile.
            let selectedNeutral = selected && !hasStatus
            let bloomColor = selectedNeutral ? accent : light
            let bloomPeak = recipe.bloom * lightScale * (selectedNeutral ? 1.3 : 1.0)
            let bloomX = min(0.04 * Double(w), 4)
            let bloomY = min(0.075 * Double(w), 8)
            var outside = context
            outside.clip(to: shape, options: .inverse)
            for inflation in HomeGlassRecipe.bloomInflations(peak: bloomPeak, alpha: 0.01, kappa: 2) {
                let rect = tile.insetBy(dx: -CGFloat(inflation * bloomX), dy: -CGFloat(inflation * bloomY))
                outside.fill(rounded(rect, radius + CGFloat(inflation * (bloomX + bloomY) / 2)),
                             with: .color(bloomColor.opacity(0.01)))
            }

            var glassContext = context
            glassContext.clip(to: shape)

            // 2. Body: dark suites tint the canvas with the tile's light; Oat keeps milky glass.
            if isDark {
                glassContext.fill(shape, with: .color(light.opacity(recipe.body)))
                glassContext.fill(shape, with: .linearGradient(
                    Gradient(colors: [light.opacity(0), light.opacity(recipe.diagonal)]),
                    startPoint: CGPoint(x: tile.minX, y: tile.minY), endPoint: CGPoint(x: tile.maxX, y: tile.maxY)))
            } else {
                glassContext.fill(shape, with: .color(glass.base))
            }

            // 3. Edge glow: one linear gradient per side, fading inward over a quarter of the tile width.
            let edgeReach = 0.25 * w
            let edgeLast = HomeGlassRecipe.edgeStops.count - 1
            let edgeStops: [Gradient.Stop] = HomeGlassRecipe.edgeStops.enumerated().map { index, distance in
                let alpha: Double = index == edgeLast
                    ? 0 : recipe.edgeAlpha * lightScale * exp(-distance / recipe.edgeDecay)
                return Gradient.Stop(color: light.opacity(alpha), location: distance / HomeGlassRecipe.edgeStops[edgeLast])
            }
            let edgeGradient = Gradient(stops: edgeStops)
            let sideRamps: [(CGPoint, CGPoint)] = [
                (CGPoint(x: tile.midX, y: tile.minY), CGPoint(x: tile.midX, y: tile.minY + edgeReach)),
                (CGPoint(x: tile.midX, y: tile.maxY), CGPoint(x: tile.midX, y: tile.maxY - edgeReach)),
                (CGPoint(x: tile.minX, y: tile.midY), CGPoint(x: tile.minX + edgeReach, y: tile.midY)),
                (CGPoint(x: tile.maxX, y: tile.midY), CGPoint(x: tile.maxX - edgeReach, y: tile.midY))
            ]
            for (start, end) in sideRamps {
                glassContext.fill(shape, with: .linearGradient(edgeGradient, startPoint: start, endPoint: end))
            }

            // 4/5. Corner lights and sheens stay inside a thin bezel so the rim reads as glass thickness.
            var bezelContext = glassContext
            bezelContext.clip(to: insetPath(0.02 * w))
            func radialLight(_ spec: HomeGlassRecipe.Light, at center: CGPoint, color: Color, scale: Double, midpoint: Double, midAlpha: Double) {
                let alpha = spec.alpha * scale
                bezelContext.fill(shape, with: .radialGradient(Gradient(stops: [
                    .init(color: color.opacity(alpha), location: 0),
                    .init(color: color.opacity(alpha * midAlpha), location: midpoint),
                    .init(color: color.opacity(0), location: 1)
                ]), center: center, startRadius: 0, endRadius: CGFloat(spec.radius) * w))
            }
            let topLeft = CGPoint(x: tile.minX, y: tile.minY)
            let topRight = CGPoint(x: tile.maxX, y: tile.minY)
            let bottomLeft = CGPoint(x: tile.minX, y: tile.maxY)
            let bottomRight = CGPoint(x: tile.maxX, y: tile.maxY)
            radialLight(recipe.topLeft, at: topLeft, color: light, scale: lightScale, midpoint: 0.35, midAlpha: 0.55)
            radialLight(recipe.topRight, at: topRight, color: light, scale: lightScale, midpoint: 0.35, midAlpha: 0.55)
            radialLight(recipe.bottomLeft, at: bottomLeft, color: light, scale: lightScale, midpoint: 0.35, midAlpha: 0.55)
            radialLight(recipe.bottomRight, at: bottomRight, color: light, scale: lightScale, midpoint: 0.35, midAlpha: 0.55)
            let sheen = isDark ? Color.mix(light, glass.reflection, recipe.sheenWhite) : glass.reflection
            let sheenScale = isDark ? 1.0 : 0.9
            radialLight(recipe.sheenTop, at: topLeft, color: sheen, scale: sheenScale, midpoint: 0.4, midAlpha: 0.5)
            radialLight(recipe.sheenBottom, at: bottomRight, color: sheen, scale: sheenScale, midpoint: 0.4, midAlpha: 0.5)

            // 6. One sweep-gradient rim. Selection replaces it with a thicker, flat theme-accent stroke
            // (one colour, one alpha, no angular variation).
            let rimWidth: CGFloat = selected ? 1.75 : (today ? 1.25 : 1)
            let stops: [Gradient.Stop] = HomeGlassRecipe.rimLevels.map { entry in
                var alpha = min(1, max(0.2, recipe.rim.base + (entry.level - 0.46) * recipe.rim.slope))
                if today && !hasStatus { alpha = min(1, alpha + 0.12) }
                if !isDark { alpha *= 0.9 }
                let white = isDark
                    ? min(1, max(0, (entry.level - recipe.rim.whiteStart) / 0.30)) * recipe.rim.whiteScale : 0
                return Gradient.Stop(
                    color: Color.mix(light, .white, white).opacity(alpha),
                    location: HomeGlassRecipe.rimFraction(entry.angle, width: Double(w), height: Double(h)))
            }
            let rimShading: GraphicsContext.Shading = selected
                ? .color(accent)
                : .conicGradient(Gradient(stops: stops), center: CGPoint(x: tile.midX, y: tile.midY))
            glassContext.stroke(insetPath(rimWidth / 2), with: rimShading, lineWidth: rimWidth)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
