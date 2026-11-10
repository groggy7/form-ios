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

        var calendar = store.weekCalendar
        calendar.missedDays = store.missedDaysThisWeek()
        let completedKeys = store.state.completed
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let activeWorkout = store.activeWorkout

        // Tour wording: more than four days scroll; a coloured tile starts the day-colour tip.
        let hasStatus = workouts.contains { workout in
            let key = "\(program.id):\(workout.id)"
            let completed = completedKeys.contains(key)
            let unfinished = !completed && unfinishedKeys.contains(key)
            return completed || unfinished || WeeklyPlanView.isMissedPlanDay(dayIndex: workout.day - 1,
                todayIndex: calendar.today, missedDays: calendar.missedDays, hasWorkout: true, completed: completed, unfinished: unfinished)
        }
        var tourFlags = Set<String>()
        if workouts.count > 4 { tourFlags.insert(TourFlag.stripScrolls) }
        if hasStatus { tourFlags.insert(TourFlag.stripStatus) }

        return AnyView(WorkoutDayStrip(
            program: program, workouts: workouts, calendar: calendar,
            activeWorkoutId: activeWorkout?.id, completedKeys: completedKeys,
            unfinishedKeys: unfinishedKeys, onSelectWorkout: onSelectWorkout,
            glowTiles: store.homeGlowTiles
        )
        // The strip scrolls edge to edge; highlight its padded tiles so the outline stays on screen.
        .tourTarget("home.days", cornerRadius: 18, flags: tourFlags,
                    contentInsets: EdgeInsets(top: 0, leading: WorkoutDayStrip.edgeInset,
                                              bottom: 0, trailing: WorkoutDayStrip.edgeInset)))
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
    /// Reference material is the default; the Calm alternative remains available.
    var glowTiles: Bool = true

    /// Matches the Home header's horizontal padding.
    static let edgeInset: CGFloat = 20
    private static let gap: CGFloat = 8

    @State private var tileWidth: CGFloat = 82
    @State private var stripWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
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

    private static let maxTileWidth: CGFloat = 128
    private static let calmHeight: CGFloat = 108

    /// Four equal slots across a phone, between the 48pt touch minimum and 96pt; days beyond four scroll at it.
    static func compactTileWidth(stripWidth: CGFloat) -> CGFloat {
        min(96, max(48, (stripWidth - 2 * edgeInset - 3 * gap) / 4))
    }

    /// Gaps stay 8pt. When every day fits at the compact width, tiles grow to share the row, up to the three-across
    /// width and 128pt: three days fill any phone, and no tablet tile outgrows the widest phone's. Leftover space
    /// stays at the trailing edge; days that do not fit keep the compact width and scroll.
    static func tileWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
        let row = stripWidth - 2 * edgeInset
        let compact = compactTileWidth(stripWidth: stripWidth)
        guard count > 0, CGFloat(count) * compact + CGFloat(count - 1) * gap <= row + 0.01 else { return compact }
        let cap = max(compact, min(maxTileWidth, (row - 2 * gap) / 3))
        return min(cap, max(compact, (row - CGFloat(count - 1) * gap) / CGFloat(count)))
    }

    /// A widened tile's height and text grow by a third of its extra width, so a three-day row fills the width
    /// without outweighing the hero card: on a 393pt phone, 112pt tiles are laid out as if 92pt wide, about square
    /// at 110pt tall with a 25pt date under the hero title's 32pt. Compact tiles are unchanged.
    static func tileScale(tileWidth: CGFloat, stripWidth: CGFloat) -> CGFloat {
        guard stripWidth > 0 else { return tileWidth }
        let compact = compactTileWidth(stripWidth: stripWidth)
        return tileWidth <= compact ? tileWidth : compact + (tileWidth - compact) / 3
    }

    /// Calm text keeps its size, so a widened Calm tile grows taller with the scale instead of turning square.
    static func calmMinHeight(tileWidth: CGFloat, stripWidth: CGFloat) -> CGFloat {
        guard stripWidth > 0 else { return calmHeight }
        let scale = tileScale(tileWidth: tileWidth, stripWidth: stripWidth)
        return calmHeight * max(1, scale / compactTileWidth(stripWidth: stripWidth))
    }

    var body: some View {
        let glass = glowTiles ? AppColors.homeDayGlowColors : AppColors.homeDayGlassColors
        let isDark = themeManager.currentTheme.isDark
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.gap) {
                    ForEach(workouts) { workout in
                        let dayIndex = workout.day - 1
                        let scale = Self.tileScale(tileWidth: tileWidth, stripWidth: stripWidth)
                        let selected = workout.id == activeWorkoutId
                        let isToday = dayIndex == calendar.today
                        let workoutKey = "\(program.id):\(workout.id)"
                        let isCompleted = completedKeys.contains(workoutKey)
                        let isUnfinished = !isCompleted && unfinishedKeys.contains(workoutKey)
                        let isMissed = WeeklyPlanView.isMissedPlanDay(dayIndex: dayIndex, todayIndex: calendar.today,
                            missedDays: calendar.missedDays, hasWorkout: true, completed: isCompleted, unfinished: isUnfinished)
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
                            // The reference splits the two 0.09w gaps unevenly: the date sits closer to the weekday and
                            // the highlight is centred between date and title. Text, insets and the gaps' total are
                            // unchanged, so the tile keeps its size.
                            VStack(spacing: glowTiles ? 0 : 6) {
                                let dayLabel = LanguageManager.workoutDays.indices.contains(dayIndex)
                                    ? String(LanguageManager.workoutDays[dayIndex].prefix(3)).uppercased()
                                    : "DAY"

                                Text(dayLabel)
                                    .font(.app(size: glowTiles ? labelSize * scale / 110 : labelSize, weight: .semibold))
                                    .tracking(0.5)
                                    .foregroundStyle(glowTiles && isDark
                                        ? AppColors.homeDayGlowLabel(statusTint) : textColor)
                                    .lineLimit(1)

                                Text("\(dayNumber)")
                                    .font(.app(size: glowTiles ? numberSize * scale * 0.267 / 25 : numberSize, weight: .bold))
                                    .foregroundStyle(textColor)
                                    .shadow(color: !isDark ? .clear
                                                : Color.black.opacity(0.30),
                                            radius: glowTiles ? 0.6 : 1, x: 0, y: glowTiles ? 0.5 : 1)
                                    .lineLimit(1)
                                    .overlay(alignment: .bottom) {
                                        if glowTiles {
                                            let ink = isDark ? AppColors.homeDayGlowDivider(statusTint)
                                                : (statusTint ?? glass.neutralRim).opacity(0.65)
                                            // Whole pixels, so the core keeps the reference's full strength.
                                            let thickness = max(1, (scale * 0.0075 * displayScale).rounded())
                                            let top = (scale * 0.058 * displayScale - thickness / 2).rounded()
                                            Rectangle().fill(LinearGradient(colors: [ink.opacity(0), ink, ink.opacity(0)],
                                                startPoint: .leading, endPoint: .trailing))
                                                .frame(width: scale * 0.25, height: thickness / displayScale)
                                                .alignmentGuide(.bottom) { $0[.top] }
                                                .offset(y: top / displayScale)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .padding(.top, glowTiles ? scale * 0.04 : 0)

                                // Workout titles never drop below 10pt (scaled with Dynamic Type): phone tiles (76-96pt)
                                // would otherwise set them at 7.6-9.6pt. The narrower side inset below gives them more room.
                                Text(workout.displayTitle(programId: program.id))
                                    .font(.app(size: glowTiles ? max(labelSize * scale / 110, labelSize * 10 / 11) : labelSize))
                                    .foregroundStyle(textColor)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2, reservesSpace: true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, glowTiles ? scale * 0.14 : 0)
                            }
                            .padding(.horizontal, glowTiles ? scale * 0.06 : 8)
                            .padding(.vertical, glowTiles ? scale * 0.17 : 12)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                Self.tileWidth(stripWidth: width, count: workouts.count)
                            }
                            .frame(minHeight: glowTiles ? scale * 1.1667
                                : Self.calmMinHeight(tileWidth: tileWidth, stripWidth: stripWidth),
                                alignment: glowTiles ? .top : .center)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tileWidth = $0 }
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(
                                Group {
                                    if glowTiles {
                                        HomeDayGlassSurface(glass: glass, statusTint: statusTint, isDark: isDark,
                                            selected: selected, markerColor: isDark ? .white : AppColors.text)
                                    } else {
                                        HomeDayCalmSurface(glass: glass, statusTint: statusTint, isDark: isDark,
                                            selected: selected, today: isToday, accent: AppColors.accent)
                                    }
                                }
                                .padding(-HomeDayGlassSurface.margin)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: HomeDayGlassSurface.radius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        // Reveal the selection with the strip's screen margin, so an edge tile lines up with the
                        // header instead of sitting flush against the screen edge.
                        .background(Color.clear.id(RevealTarget(workoutId: workout.id))
                            .padding(.horizontal, -Self.edgeInset))
                        .accessibilityIdentifier("today-day-\(workout.id)")
                        .accessibilityLabel("\(LanguageManager.workoutDays[dayIndex]), \(dayNumber), \(workout.displayTitle(programId: program.id))")
                        .accessibilityValue(statusDescription)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Self.edgeInset)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .defaultScrollAnchor(initialScrollAnchor)
            .onChange(of: activeWorkoutId, initial: true) { _, selectedId in
                if let selectedId { proxy.scrollTo(RevealTarget(workoutId: selectedId)) }
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

    /// A distinct type, because ForEach already identifies each tile by its bare workout id.
    private struct RevealTarget: Hashable {
        let workoutId: String
    }
}

// MARK: - Home day tile glass
//
// Shared halo construction for the reference material and optional Calm shadow.
private enum HomeGlassRecipe {
    static let bloomLayerAlpha = 3.0 / 255.0
    static let bloomKappa = 2.0

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
    static let margin: CGFloat = 14

    let glass: AppColors.HomeDayGlassColors
    let statusTint: Color?
    let isDark: Bool
    let selected: Bool
    /// Neutral ink (white on dark suites) so the selection marker never reads as a status or accent colour.
    let markerColor: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width - Self.margin * 2
            let h = size.height - Self.margin * 2
            guard w > 0, h > 0 else { return }
            let tile = CGRect(x: Self.margin, y: Self.margin, width: w, height: h)
            let radius = w * 0.145
            let light = statusTint ?? glass.neutralRim
            let index = statusTint == glass.completedLight ? 0 : statusTint == glass.missedLight ? 1 : statusTint == glass.unfinishedLight ? 2 : 3
            func rounded(_ inset: CGFloat) -> Path {
                Path(roundedRect: tile.insetBy(dx: inset, dy: inset), cornerRadius: max(0, radius - inset))
            }
            let shape = rounded(0)
            var outside = context
            outside.clip(to: shape, options: .inverse)
            for inflation in HomeGlassRecipe.bloomInflations(peak: 0.08, alpha: HomeGlassRecipe.bloomLayerAlpha, kappa: HomeGlassRecipe.bloomKappa) {
                let spread = CGFloat(inflation) * w * 0.065
                outside.fill(rounded(-spread), with: .color(light.opacity(HomeGlassRecipe.bloomLayerAlpha)))
            }
            context.clip(to: shape)
            if isDark {
                context.draw(Image(decorative: HomeTileReferenceSurface.images[index], scale: 1), in: tile)
            } else {
                context.fill(shape, with: .color(glass.base))
                context.fill(shape, with: .linearGradient(Gradient(colors: [light.opacity(0.28), light.opacity(0.05), light.opacity(0.18)]),
                    startPoint: CGPoint(x: tile.midX, y: tile.minY), endPoint: CGPoint(x: tile.midX, y: tile.maxY)))
            }
            let colors = HomeTileReferenceSurface.rims[index]
            let stops = colors.enumerated().map { index, color in
                Gradient.Stop(color: isDark ? color : light.opacity(0.85), location: Double(index) / Double(colors.count - 1))
            }
            let rimWidth = w * 0.0075
            context.stroke(rounded(rimWidth / 2), with: .conicGradient(Gradient(stops: stops), center: CGPoint(x: tile.midX, y: tile.midY)), lineWidth: rimWidth)
            if selected {
                var marker = Path()
                marker.move(to: CGPoint(x: tile.minX + w * 0.40, y: tile.maxY - 3))
                marker.addLine(to: CGPoint(x: tile.minX + w * 0.60, y: tile.maxY - 3))
                context.stroke(marker, with: .color(markerColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Home day tile, calm glass
//
// The optional Calm Home day tile. Tinted glass with a plain one-colour border line, an inner top highlight and
// bottom shade, and a soft shadow. No glow (outer or along the border), corner lights, sheens, specular arc
// or bezel step.
// Keep geometry, stops and alphas in sync with Android's `dayTileCalmGlass` (WorkoutWeekStrip.kt).
// See docs/design/form-design-system.md, "Home day tile styles".
struct HomeDayCalmSurface: View {
    /// `tint` is the body's blend of the light; `ring` is the opacity of the uniform border line.
    private struct Look { let tint: Double; let ring: Double }
    private static let statusDark = Look(tint: 0.19, ring: 0.60)
    private static let neutralDark = Look(tint: 0.05, ring: 0.35)
    private static let statusLight = Look(tint: 0.28, ring: 0.65)
    private static let neutralLight = Look(tint: 0.05, ring: 0.45)
    /// Fractions of an edge ramp's reach (four time constants): alpha is `amp * exp(-4 * fraction)`, 0 at the end.
    private static let rampStops: [Double] = [0, 0.125, 0.25, 0.5, 0.75, 1]
    private static let warmShade = Color(hex: 0x71685C)

    let glass: AppColors.HomeDayGlassColors
    let statusTint: Color?
    let isDark: Bool
    let selected: Bool
    let today: Bool
    let accent: Color
    var cornerRadius: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let edge = HomeDayGlassSurface.margin
            let w = size.width - 2 * edge
            let h = size.height - 2 * edge
            guard w > 0, h > 0 else { return }
            let radius = cornerRadius
            let tile = CGRect(x: edge, y: edge, width: w, height: h)
            func rounded(_ rect: CGRect, _ cornerRadius: CGFloat) -> Path {
                Path(roundedRect: rect, cornerRadius: max(0, cornerRadius), style: .continuous)
            }
            func insetPath(_ amount: CGFloat) -> Path {
                rounded(tile.insetBy(dx: amount, dy: amount), radius - amount)
            }
            let shape = insetPath(0)
            let hasStatus = statusTint != nil
            let look: Look = isDark ? (hasStatus ? Self.statusDark : Self.neutralDark)
                : (hasStatus ? Self.statusLight : Self.neutralLight)
            let light = statusTint ?? glass.neutralRim
            let shade = isDark ? Color.black : Self.warmShade
            let width = Double(w)

            // 1. Soft drop shadow outside the shape (black, or warm brown on light suites); no coloured glow.
            var outside = context
            outside.clip(to: shape, options: .inverse)
            let reachX = 0.078 * width, reachY = 0.042 * width, offsetY = 0.058 * width
            for inflation in HomeGlassRecipe.bloomInflations(peak: isDark ? 0.29 : 0.20,
                                                              alpha: HomeGlassRecipe.bloomLayerAlpha,
                                                              kappa: HomeGlassRecipe.bloomKappa) {
                var rect = tile.insetBy(dx: -CGFloat(inflation * reachX), dy: -CGFloat(inflation * reachY))
                rect.origin.y += CGFloat(offsetY)
                outside.fill(rounded(rect, radius + CGFloat(inflation * (reachX + reachY) / 2)),
                             with: .color(shade.opacity(HomeGlassRecipe.bloomLayerAlpha)))
            }

            var glassContext = context
            glassContext.clip(to: shape)

            // 2. Glass body: status tint, then a top-to-bottom gloss (milky base first in light suites).
            if !isDark { glassContext.fill(shape, with: .color(glass.base)) }
            glassContext.fill(shape, with: .color(light.opacity(look.tint)))
            let gloss: [Double] = isDark ? [0.17, 0.065, 0.075] : [0.50, 0.14, 0.22]
            glassContext.fill(shape, with: .linearGradient(Gradient(stops: [
                .init(color: Color.white.opacity(gloss[0]), location: 0),
                .init(color: Color.white.opacity(gloss[1]), location: 0.38),
                .init(color: Color.white.opacity(gloss[2]), location: 1)
            ]), startPoint: CGPoint(x: tile.midX, y: tile.minY), endPoint: CGPoint(x: tile.midX, y: tile.maxY)))

            // 3. Inner depth: a thin top highlight and a bottom shade. No glow along the border.
            // `side`: 0 top, 1 bottom, 2 left, 3 right.
            func ramp(_ side: Int, _ color: Color, amp: Double, tau: Double) {
                let reach = CGFloat(4 * tau)
                let stops = Self.rampStops.map { fraction in
                    Gradient.Stop(color: color.opacity(fraction >= 1 ? 0 : amp * exp(-4 * fraction)), location: CGFloat(fraction))
                }
                let start: CGPoint, end: CGPoint
                switch side {
                case 0: start = CGPoint(x: tile.midX, y: tile.minY); end = CGPoint(x: tile.midX, y: tile.minY + reach)
                case 1: start = CGPoint(x: tile.midX, y: tile.maxY); end = CGPoint(x: tile.midX, y: tile.maxY - reach)
                case 2: start = CGPoint(x: tile.minX, y: tile.midY); end = CGPoint(x: tile.minX + reach, y: tile.midY)
                default: start = CGPoint(x: tile.maxX, y: tile.midY); end = CGPoint(x: tile.maxX - reach, y: tile.midY)
                }
                glassContext.fill(shape, with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end))
            }
            ramp(0, .white, amp: isDark ? 0.44 : 0.80, tau: 0.0106 * width)
            ramp(1, shade, amp: isDark ? 0.335 : 0.22, tau: 0.0181 * width)

            // 4. One plain border line in the status or neutral light (accent when selected): a single colour
            // and opacity all the way round.
            let rimWidth: CGFloat = selected ? 1.5 : (today ? 1.25 : 1)
            let rimPath = insetPath(rimWidth / 2)
            glassContext.stroke(rimPath, with: .color(selected ? accent.opacity(0.95) : light.opacity(look.ring)),
                                lineWidth: rimWidth)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}


/// Measured sRGB reference surfaces, with typography excluded and its surface continued harmonically.
/// Order: emerald, rose, amber, neutral silver. Text and rims remain native.
enum HomeTileReferenceSurface {
    private static let samples = [
        "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Gi4pGi0pGi0pGS0oGSwoGSwoGSwnGSwnGSsnGCsmGComGColGColGColFyklFyklFyklFyklFyolFyolGComGComGCsmGCsnGCwnGS4oGS4pGS8pGjAqGjErGjErGjIrGjQsGjYtGjkvGTovGTovIEU5IEQ5H0A2HjwzHTUvHDItGzArGi8qGi8qGi8qGi4pGS0pGSwnGCsnGCsnGSsnGComGComGComGColGCklFygkFygkFygjFycjFicjFicjFicjFicjFicjFicjFicjFigjFygkFygkFyklFyomGCsmGCwmGC0nGC4oGC8pGC8pGC8qGTErGTQrGTYtGTguGTkuH0Q4H0M4Hj41HToxHDQuGzArGi8qGi4pGS0oGS0oGCsnGComGCklGCklFyklGCklFygkGCkkFygkFygkFycjFiYiFiYiFiUhFSUhFSUhFSUhFSUhFSUhFSUhFSUhFSUhFSUhFiUiFiYiFScjFigjFygkFiklFyomFysmGCwnGC0nFy4nFy8oFzIqGDUsGDYsGDYsH0M4H0I4Hj40HTgwGzMsGi8qGi4pGSwnGCsmGComGCklFyklFygkFycjFycjFycjFicjFycjFicjFiYiFiYiFiUhFiUhFSUhFSUhFSUhFSQhFSQgFSQgFSQgFSQgFSQhFSUhFSUhFSUhFSUhFSYiFSYiFSciFikkFykkFyolFysmFy0mFy4oGDEpFzMqFzQrGDQrH0E3HkA3HTwyHDgwGjErGi8pGSwnGComGCklGCkkFygjFiciFiUhFSUhFSUhFSUhFSUhFSUhFSUhFSUhFSQgFSQhFiQgFSQgFSQgFSMfFSMgFSMfFCMfFCMfFCMfFSMgFSQgFSQgFSQgFSQhFSUhFSUhFSUhFSYiFSciFSgjFikkFikkFiokFislFi0mFi8nFzAoHj41HT41HToxHDYvGjAqGi4pGCsmGCklFygjFiYiFSUhFSUhFSUhFSQhFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSMgFSMfFSMfFSMfFCMfFCMfFCMfFSMfFSMgFSMgFSMgFSMgFSMgFSQgFSQgFSUgFSUhFSUhFSYiFSciFSkjFiskFiwlFSwlFSwlHT41HT40HDoxHDYuGjAqGC0nGCklFygkFiYiFSUhFSQgFSMgFSMgFSMgFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSQgFSMgFSMfFSMfFSMfFSMfFCMfFCMfFCMfFCMfFCMfFCMfFSMfFCMfFCIfFCIfFCIeFCIfFSMfFSMgFSUgFSUhFSUhFSgiFSkjFiskFSwlFSwlHT40HT00HDkwGzUtGi8qGCwnFyklFicjFSUhFSQgFSMfFCIeFCIeFCMfFCMfFCMfFCMfFCMfFCMfFSMfFSMfFSMfFSMfFSMfFSMfFSMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCIfFCIfFCIfFCEfFCIeFSIfFCIeFSMfFCMfFSQfFSUgFSYiFSkjFSwkFSwlFSwlHD0zHDwyHDgwGjQsGS8pGCsmFigkFiYiFSUhFSMfFCIeFCEdFCEdFCIeFCIeFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCIfFCIfFCIfFCIfFCIfFCIfFCIeFCIeFCIeFCEeFCEeFSIeFCIeFCMeFSMfFSUgFSYhFikjFiwkFSwlFSwkHDsxHDsxGzgvGjMrGC8pGComFigjFSYiFSQgFSIeFCEdEyEdEyEdFCIeFCIeFCIeFCIfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCMfFCIfFCIfFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCEeFCEeFCEeFCEeFSEeFSIeFCIeFSMfFSUgFSciFikjFSskFSwlFiwkGzsxGzoxGjcuGjMrFy4nFyolFicjFSUhFCMeFCEdEyAdEyAdEyEdEyEdFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCEeFCEdFCEdFCEeFCEeFCEeFSIeFSMfFSUgFSciFSkiFSskFSwlFS0lGzsxGzoxGjYuGTIrFy0nFyklFSciFSUhFCIeFCEdEyEdEyAdEyEdEyEdFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCEeEyEdEyEdFCEdFCEeFSEeFSEeFCMeFSQfFSUhFSciFSkiFSwkFSwkFSwkGzowGzkwGjUtGDAqFywmFikkFSYiFSQgFCIeFCEdEyAdEyAdEyEdEyEdEyEdFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCEeFCEdEyEdEyEdFCEdFCEdFCEeFSEeFCMfFSQgFSUgFSYhFSkjFSwlFSwlFSwlGjgwGjcwGjQtGDApFysmFigjFSUhFSQgFCIeFCEdFCEdEyAdFCEdFCEdFCEdFCEdFCIdFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCIeFCEeFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCEeFCIeFCMfFSQgFSUgFSciFSkiFiwlFS0mFi4mGjgvGjcvGTQrGC8pFiolFSgiFSUhFSMfFCIeFCEdFCEdFCEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCIdFCIdFCIdFCIeFCIeFCIeFCIeFCIeFCEeFCEeFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCIeFCIeFCIeFCMeFCMfFSUgFSchFSkiFiwlFTMoFTQqGjYuGjYuGTIrGC8oFikkFSciFSUhFCMfFCIeFCEdEyEdFCEdFCEdFCEdFCEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdFCEdFCEdFCEdFCEdFCEdEyEdEyEdFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCEdFCIeFCIeFCIeEyIeFCMfFCQfFSchFSokFi8nFjIpFjQpGjYuGjUtGDIqGC8oFikkFSYiFSUhFSMgFCIeEyEdEyEdEyEdFCEdFCEdFCEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdFCEdFCEdFCEdFCEdEyEdEyEdEyEdEyEdFCEdFCEdEyEdEyEdEyEdEyEdFCIeFCEdFCIeFCIeEyIeFCMeFCUgFSgiFSojFS4mFjEoFjIoGTQrGTQrGDEqFy4nFikkFSYiFSUgFSMfFCIeFCEdEyEdEyEdEyEdEyEdFCEdEyEdEyEdEyEcEyEdEyEcEyEdEyEdFCEdEyEdFCEdFCEdFCEdEyEdEyEdEyEdEyEdFCEdFCEdEyEdEyEdEyEdEyEdFCIeFCEeFCEeFCIeFCIdFCMeEyQfFSciFSkjFS4mFTAnFTEnGTIrGTIrGTApFy0mFikkFSciFSQgFCMfFCEdFCEdEyEdEyEdEyEdFCEdEyAcEyEdEyEdEyEdEyEdEyAcEyEdEyEdFCEdEyEdFCEdFCEdEyEdEyEdEyEdEyEdFCEdFCEdFCEdFCEdEyEdEyEdEyEdFCEdEyEdEyEeEyEeEyIeFCMeFCUfFCchFSkiFC0lFS8nFTAnGTIrGTIrGS8pFy0mFikjFSYiFSMfFCIeFCEdFCEdEyEdEyEdEyEdEyAcEyEdEyAcEyEdEyAcEyEdEyEcEyEdEyEdFCEdEyEdFCEdFCEdFCEdFCEdEyEdFCEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdEyEdFCEdFCEeEyEeEyIeEyMeFCUfFCchFSkiFS0lFC8mFS8nGTIrGTIrGC8pFywmFSgiFSUhFCMfEyIeFCEdFCEdEyEdEyEdEyEcEyAcEyAdEyAcEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdFCEdFCEdFCEdEyEdEyEdEyEdEyEdFCEdEyEdEyEdEyEdEyEdFCEdEyEdFCEeFCIeEyIeEyMeEyQeFSchFSkiFCwkFC8mFS8mGTEqGTEqGC8oFywmFSgiFSUhFCMeEyIeEyEdFCEdEyEdEyEdEyEcEyAcEyEdEyEcEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdFCEdFCIeFCIeEyMeEyQfFSYhFSkiFCwkFC8nFS8nGDEpGDApFy8oFywmFSgiFSUhFCMfFCIeFCEdFCEdEyEdEyEdEyEdEyAdEyEdEyEcEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEcEyEcEyEcEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdFCEdEyEdFCIeFCMfEyMfFCUfFCchFSkiFS0lFC8mFS8nGTEqGDEqFy8oFywmFSgjFSYhFCQfFCIeEyEdFCEdEyEdEyEdEyEcEyEdEyEdEyEcEyEdEyEdEyEdEyEdEyEcEyEdEyEdEyEdEyEcEyEdEyEdEyEcEyAcEyEcEyEdEyEdEyEcEyEdEyAcEyAcEyAcEyEdEyEdEyEdFCIeEyMeFSQgFCUgFSchFSkiFS0lFS8mFS8nGTMrGTMrGC8oFywmFigjFSUhFCQfFCIeFCEdFCEdEyEdEyEdEyEdEyEcEyEdEyEcEyEdEyEdFCEdEyEdEyEdEyEdEyEdEyEdEyEdEyEcEyEcEyAcEyEdEyEdEyAcEyAcEyAdEyEcEyEcEyAdEyAcEyEdEyEdFCEdFCIeFCMfFCQfFCUgFSciFSkiFS0lFS8mFS8nGzgwGjgwGC8oFy0mFigjFSUhFSUgFCQfFCMfFCMeFCMeFCMeEyIeEyIdEyIeEyIdEyIdEyIdFCIdEyIdEyIdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyEdEyIdEyIeFCIeFCMfFCQfFCUgFCYhFSciFSkiFC0lFS8mFS8nGzowGzkwGjYtGjMrFigjFSUhFSYhFSYhFSUgFCUgFCQgFCQfFCQfFCMfFCMeFCMeFCMeEyMeFCIeEyIeEyIeEyIeEyIeEyIdEyIdEyIdEyIdEyIdEyIdEyIdEyEdEyEdEyIdEyIdEyIdEyIeEyIeFCMeFCMeFCQfFCQfFCUgFCYgFSchFSgiFSojFSwlFS0lFS0mGjowGjkwGjcuGjYsGTMrFSYhFigiFSgiFSciFSchFSYhFCYgFCUgFCUfFCQfFCQfFCQfFCMfFCMeFCMeEyMeEyIeEyIeEyIeEyIeEyIdEyIdEyIdEyIdEyIdEyIeEyIeEyIeEyIeEyMeFCMeFCMeFCQfFCQfFCQfFCUgFCYgFSYhFSchFSgiFSkjFS0lFS8mFi8mGjwxGjsxGjkvGjYtGDIqGC8oFywlFiokFikjFSgjFSgiFSchFCYhFCYgFCUgFCUgFCQfFCQfFCQfFCMfFCMeEyMeEyMeEyMeEyIeEyIeEyIeEyIeEyIeEyIeEyIeEyMeEyMeFCMeFCMeFCQfFCQfFCQfFCUgFCUgFCYgFCYhFSchFSgiFSgiFSojFi4lFi8nFi8nGz40Gz4zGjwxGjctGDMrGDEoFy4nFi0mFislFiokFSkjFSgiFSgiFSchFCYhFCYgFCUgFCUfFCQfFCQfFCQfFCMeEyMeEyMeEyMeEyMeEyMeEyMeEyMeEyMeEyMeFCMeFCMeFCQfFCQfFCQfFCUfFCUgFCYgFCYhFCchFSchFSgiFSgiFSgiFiskFi8mFi8nFi8nG0I1G0E1Gz0yGjkvGTUsGDEpFzAoFy4nFi0mFiwlFiskFSojFSkjFSgiFSchFCYhFCYgFCUgFCUgFCQfFCQfFCQfFCMfEyMeEyMeEyMeEyMeEyMeEyMeFCMeFCMeFCMfFCQfFCQfFCQfFCUgFCUgFCYgFCYhFCchFSchFSgi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KRkdKBkdKBkdKRkeKRkeKRkeKBkeKBkeKBkdKBkdKBkdKBkdKBkdKBkdKBkdKBkdKBkdKBkdKBkdKRkdKRkeKRkeKRkeKhkeKhkeKxofKxkeLRofLhofLhofLxsgMBwgMhwgNBwhOB0iOh8iOx8iQSInQSInPSAmOB4jNBwhMRwhMBwhLhogKxkeKxkeKhkeKRkdKBgdJxgdJxgdJxgdJxgdJxgdJxgdJxgdJxgdJxgdJxgcJxgdJxgdJxgdJxgcJxgdJxgdJxgcJxgdJxgdJxkdKBkdKBkdKBkdKRkdKRkdKhkeKxkeKxkeLBoeLhofLhsfMBsgMhwgNx0iOB4iOB4iQCEmPyEmOh8kNx0iMhwhMBsgLhofKxkeKxkdKhkdKRkdKBgdJxgdJhgcJhgdJhgcJhgcJhccJhccJhgcJhccJRccJhcbJhccJhccJhccJhcbJhccJhccJRcbJhccJhgcJhgcJhgcJhgdJxgdKBgdKBkdKRkeKhkeKhkdKxkeLBkeLRoeLxofMRwgNR0hNx0hNx0hPSAlPSAlOR4kNR0iMBwgLhofKxkeKhkdKRgdKBgdKBgdJxgcJhgcJhccJhgcJhccJhccJhcbJhccJhcbJRcbJhcbJRcbJhccJRccJRcbJRcbJRcbJhccJhgcJRcbJhccJhccJhgcJhccJxgdJxgdKBkdKBkdKRkdKRkdKRkdKhkdKxkdLRoeMBsfNBwhNx0hNx0hOx8kOx8kNx0iMxwhLxofKxkdKhkdKBgdKBkdJxccJhccJhccJRccJhgcJhccJhccJhcbJhYbJRcbJhcbJRYbJRYaJRcbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJhccJhcbJhcbJhcbJhccJhgcJxgdJxgdKBkdKBkdKBgdKBgdKRgdKhkdLBkdLxseMxwgNh0hNx0hOh4jOh4iNhwiMRwgLRkeKxkdKBgdJxccJhgcJhccJhcbJRcbJRYbJRcbJhcbJhcbJhcbJhYbJRcbJRcbJRYbJRYbJRcbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJhcbJhcbJhcbJhcbJhccJhccJhccJhgdJxgdJxccJxgdJxgcKBkdKRkdKxkdLhoeMRwfNB0gNR0gOh4iOh4iNhwhMBsgLBkeKhkdKBgdJxgcJhcbJhYbJRYaJRYaJRYaJRYbJRcbJRcbJRcbJRcbJRcbJRcbJRYbJRYbJRYbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJhcbJhcbJhcbJhcbJhcbJhccJhccJhgcJhgcJhccJhccJxgcKBgcKRgdKxkdLRoeMRsfNR0gNR0gOh4jOR4iNhwhMBsfLRkdKxkdKBgdJhgdJhcbJhcbJRYaJBYbJBYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJRcbJRcbJhcbJhcbJhcbJhcbJhcbJhcbJhcbJhgcJhccJhgcJxgcJxkcKRgdKxkdLhseMRwfNB0hNR4gOR8iOR4iNRwhMBsfLBkeKhkdKBgdJhccJhcbJRYbJBYaJBYaJBYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJRcbJRcbJRcbJhcbJhcbJhcbJhccJhcbJhcbJhccJhgcJhgcJxgdKRkdKxkdLhseMhwfNR4gNR4gOh4iOR4iNRwhMBsfLBkdKhgdJxccJhccJhcbJRcbJRYbJBYbJBYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRcbJRcbJRcbJRcbJRcbJRcbJRcbJRcbJRYbJRYbJRYaJRcbJhcbJhgcJhgcJxgcJxgdKRkdKxkdLhseMhwgNR4hNh4gOR4jOR4iNRwhMBofLBkdKhgdJxcbJhccJhccJhYbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJhcbJhccJhgcJxkdKBkdKRkdKxkdLxseMxwgNh4hNx4hOh4iOR4iNRwhMBofKxkdKhgdKBccJhccJhcbJhYbJhYbJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRcbJhccJhgdJxgdKBkdKRkdKxkdLhseMRwfNh4gNx4hOh4jOR4iNRwhMBofLBkdKhgdKBgcJxccJhcbJhYbJhYaJhYaJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRcbJhcbJhccJxgdKBgdKBkdKRkdKxkdLxoeMhwfNh4gNx4gOx8jOh8jNRwhMBofLBkdKhgdKBgcJhccJhcbJhYbJhYbJhYbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJRYbJhcbJhccJhgcJxgdKBkdKRkdLBkdLxseMhwfNh4gOB4hOx4iOh4iNhwhMBofLBkdKhgdKBgcJxccJhccJhYbJhYbJRYaJhYbJhYbJhYbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRYcJhccJhgcJhccJxgcJxgdKRkdKxodLhseMhwfNh4hNx8hOx4jOx4iNhwhMBofLBkdKhgcKBccJhccJhccJhYbJhYbJhYbJhYbJhYbJhYbJhYbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYaJRYaJRYaJhYbJhYcJhcbJhccJxgdKBgcKRkdKxkdLhseMRwgQSIkQyMkOx4iOx4iNhwhMBofLBkdKhgdJxccJhccJhccJhcbJhcbJhcbJRYaJhYbJhYaJhYbJRYbJhYaJRYaJRYaJRYbJRYaJRYbJRYaJRcaJRcbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYaJRYaJRYbJhcbJRcbJhccJhccJhccJxgcKRgcKxkdNh0hOh8iPiEjPyEjOx0iOh0iNRwgMBofLBkdKhgdKBccJxccJhcbJhcbJhYbJhYbJhYaJhYbJhYaJhcbJRYbJhcaJRYaJRYaJhcbJRYaJhYbJRYaJRcaJhcbJRYbJRYaJRYaJBYaJRYaJBYaJRYaJhcbJRYaJRYaJRYaJRYaJhYbJhcbJhccJxccJxgcLRkdMRweNR0hOh8iPyEjQCIkOh0iOh0iNhwgMBoeKxkdKRgcJxcbJxccJhYcJhYbJhYbJhYbJRcaJhYbJhYbJRcaJhYbJRYaJRYaJRcbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJBYaJRYaJBYaJBYaJRYaJRYbJRYaJRYbJRYaJRYaJRYbJhcbJhYbJhYbJxgcLhkeMBofMhwfNRwgOh8iQCIkQiMlOh0iOR0iNhwhMBofKxgdKhgcKBccJhccJhcbJhYbJhYbJRYaJhYbJRYbJhYaJRYbJRYbJRcaJhYbJhcaJRYaJRYbJRYaJhcbJhcbJRYbJRYbJRYaJRYaJRYaJRYaJRYbJRYaJRYaJBYaJRYaJRYbJRcbJhYbJhcbJhccKxkdLRkeMBsfMxwgNh0hOh4iQCEkQSIlOh4iOh4iNRwhMBofKxkdKhgdKBccJxccJhYbJhcbJhYbJRYbJhcbJhYaJRcbJhYbJhcbJhcbJhYbJhcaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYaJRYaJRYaJRYaJRYbJRYbJRYbJRYbJRYbJRcbJRYbJhcbJhccKxgdLBkdLhkeMBseMxwgNh0hOx8iPyEkQSIkOh4iOh4iNhwhMBoeKxkdKRgdKBccJxccJhYbJhYbJhYbJRYaJRcaJRYbJhYbJhcbJhccJhcbJhcbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYbJRYbJRcaJRYbJhcbJhcbJhcbJhccKBccKxkdLBkdLhkeMBseMhwfNh0gOh8iPiAkQCIkOR4iOR4iNhwhMBoeLBkdKhgdKBccJhccJhccJhYbJhYaJhYbJRYaJRYaJhcbJRYbJhcbJhcbJhcbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJBYaJBYaJBYaJRYaJRYbJhYaJRYbJRYaJRYbJhYbJhcbKRccKxkdLBkdLxoeMBoeMxwgNh0hOh4iPyEjQCEkOR4iOR4iNhwhMRofLRkdKxgdKBccJhYcJhcbJhYbJRYaJRYaJRYaJRYbJRYaJRYaJhYbJhcbJhcbJRYaJRYaJRYaJBYaJRYaJBYaJRYaJBYaJRYaJBYaJBYaJBYaJBYaJRYbJRYaJRYaJRYbJRYbJhcbJxccKRgdKxkdKxkdLhkdMBoeMxwfNx0hOR4iPiAjPyAjOR4iOB4iNhwhMBsgLRkdKxgdKBgcJxccJhcbJRYaJRYbJRYaJRYbJRYaJRYaJRYaJRYbJRYbJRYbJRYaJRYaJBYaJRYaJBYaJBYaJBYaJBYaJRYaJBYaJRYaJRYaJRYaJRYbJRYbJRYbJhYbJhcbJhccJxccKRcdKxgdKxkdLhkdMBoeNBwgNx0iOR4iPSAjPiAjOB0iOB4iNRwhMRsgLRkdKxkdKRgcKBgcJxccJxcbJhcbJhYbJhYbJhYbJhYbJhYbJhYbJRYbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJRYaJhYbJhYbJhYbJhYbJxcbJxccKBccKRccKhgdKxgdLRkdLxoeMRsfMxwgNh0gOB4hPCAjPiAjOR4jOR4iNRwiMBsfLRkdKxkdKhgdKRgcKBccKBccJxcbJxcbJxcbJxcbJhcbJhYbJhYbJhYbJhYbJhYbJhYbJRYbJRYaJRYaJRYaJRYaJRYaJRYaJhYbJhYbJhYbJhYbJhcbJxcbJxcbKBccKBccKRgcKhgdKxgdLBkdLhkeLxoeMRsfMxwfNh0hOR8iPCAjPiAjOx8kOx8jNxwiMBsgLBkdKxgdKhgdKhgdKRgcKRgcKBccKBccKBccJxcbJxcbJxcbJxcbJhcbJhcbJhYbJhYbJhYbJhYbJhYbJhYbJhYbJhYbJhYbJhYbJhcbJhcbJxcbJxcbJxccKBccKBccKRgcKhgcKxgdLBkdLRkdLhoeLxoeMRsfMhsfNhwgOR4iPSAjPiAjPR8jPB8jOBwiMRsfLBkdKxgdKxgdKhgdKhgdKhgcKRgcKRccKBccKBccKBccJxcbJxcbJxcbJxcbJhcbJhcbJhcbJhYbJhYbJhYbJhYbJhcbJhcbJhcbJxcbJxcbJxcbKBccKBccKRccKRgcKhgcKxgdLBkdLRkdLhkeLxoeMBoeMRsfMhsfNhwgOR4iPCAiPiAiQSAlQCAlOh4jMxwhLhkeKxkdKxkdKxkdKxgdKxgdKhgdKhgcKRgcKRccKBccKBccKBccJxcbJxcbJxcbJxcbJhcbJhcbJhcbJhcbJhcbJhcbJxcbJxcbJxcbJxcbKBccKBccKRccKRgcKhgcKxgdKxgdLBkdLRkdLhkeLxoeMBoeMRsfMhsfNRwgOB4iOx8iPCAiQiEmQiAmPR8kOB0iMBofKxkdLBkdLBkdLBkdKxkdKxgdKhgdKhgdKRgcKRccKBccKBccKBccJxcbJxcbJxcbJxcbJxcbJhcbJhcbJxcbJxcbJxcbJxcbJxcbKBccKBccKRccKRgcKhgcKxgdKxgdLBkdLRkdLhkeLxoeMBoe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WygvWScuUCUrSyMoSSMnRiInPx8kOB0iOB0iNh0iNBwhMhwgMRwgMBwgMBsgMBsfLxoeLhkeLhkeLhkeLhkeLxoeMBsfMBofMBofMhsfMxsgNBwgNhwgNxwgOR0hPB4iQSAjSSElTyMnViUpWCcqWScqWScrXScrYCgsYiktYSgsXigsYiszYSoyYCsyWigvWSgvWygvWScuUiYsTCQpSyMoRyInPx8kOB0iOBwiNh0iNRwhMhwgMhwhMRwgMRsgMBsfLxoeLxkeLhkeLhkeLhkeMBofMRsfMBofMBsfMxwgNBwgNRwhNhwgOBwgOhwhPR4iQiAkSSElUiQoWycrXCcrWScqWScrXCcrYCgsYSksYSgsYSgs",
        "ZEUpY0QpY0UpYkUpYEQoXEAnWT4nVTwlUDgkTDYkSTUjSDUkRTUjQzMiQjIjQTEiQDEiPzEiPjAiPjAiPjAiPS8hPC8hPS8iPS8iPS8hPS8hPS8hPS8hPS8hPC8hPC8hOy4hPC4hPi8hQjIiQzIiQzIhRTMiSDQiSzUjUTolUjokVzwmWz8nWz4mWj4mWz8nXEAnY0QpZEUpY0UpYkUpYUQoXEAnWT4nVTwmTzgkTDYkSTUkRzUkRTQjQzMiQjIiQDEiQDEiPzEiPjAiPjAiPi8iPS8hPC8hPS8iPS8iPS8hPS8hPS8hPC8hPS8hPC8hPC8hOy4hOy4hPi8hQTIiQzIiQzIhRTMiSDQiSzUjUDolUjokVzwmWz8nWj4mWj4mXEAnXEAnYUQoYUQpZEUpY0UpYEQpW0AoVTwmUTolTTckSTQjRzQjRTQiQjIiQDEiPzAiPjAhPi8hPi8hPi8hPi8iPS8hPC8iPC8iPC8iPC8hPC8iPC8hOy4hOi4hOi0gOi4hOi4hPC8hPS8hPi8hPi8hPzAhQTEhRDMiRzQiSjUjTTcjUTkkVDwlWT0mWj4mXEAnWz8mWz8mYEMpYEMpYUQoX0IpWj8oVTwmUTolTTgkSTUjRzQiRDMiQTEiPy8hPi8hPS8hPS8hPS8hPC4hPC4hPC4hOy4hOi4hOi4hOi0hOi0hOS0hOS0hOSwgOCwfOCsfOSwgOi0gOi0gOi0gOy4hPC4hPi4gPi8gQTAhQzEiRjMiSTQjTDYjUTokVjwlWj4mWz8mWj4mWj4mX0IoX0IoXkEoWj8oVTwmUDolSzYjSTQjRTMiQzEiQDAhPi8hPS4hOy0gOiwgOSwfOCwfOCwgOCwgNywgOCwgNywgNywgNysfNiofNiofNiofNiofNiofNiofNiofNysfNisfNywfOCwgOSwgOiwfOy0fPi8gPy8gQjEhRTMiSTQjTTcjUjskVzwlWj4mWj4mWT0lXUEnXUEnW0AoVzwnUDklSzYkSDQiRTIhQTAhPi8hPS4hPC0gOSsfNysfNiofNiofNikfNiofNikfNSofNiofNikfNSkfNSkfNSkfNCkfNCkeNCkeNCkeMygeNCkeNCkeNCkeNSkfNiofNysfNysfOCsfOiwfPC4gPi8gQTAhRTIhSTQiTjcjUTokVDskUzokUzokWj4mWj4mVTwmUDklSjUkRzQjQzEhQC8gPi4gOy0fOSsfNyofNSkeNSkeMykeMigeMiceMigeMigeMigeMigeMSceMSgeMSgeMSceMSceMSceMSceMSceMSceMSceMSceMiceMygeNCkeNSkeNikeNikeNyoeOSwfPC0fPi8fQjAgRTIhSTQiTDYiTzgjTzgjTzgjVzwmVjwmUDklTDYkRjMiQzEhPy8gPS4fOywfOCoeNikeNCkeMygdMiceMSYdMCYdLyYdMCYdMCceMCcdMCYdMCYdMCYdLyYdLyUdLyYdMCYdMCUdLyYdMCYdMCYdMCYdMCYdMCYdMSceMygdNCgdNSkeNikeNyoeOiwePS0fPi8fQjAgRjIgSTQhSjUiTTYhTjchUjolUjolTDYkSDQjQzAhPy8gPC0fOisfNyoeNSkeMygdMCYdMCUdMCYdLyUdLiUcLiUcLiUdLiUdLiUcLiUcLiUcLiUcLSUcLSQcLSQcLiQcLiQcLiUcLiUcLiUcLiUcLiUcLyUcLyYdMCYdMScdMicdMygdNikdNykdOisePC0ePi8fQS8gRTMgSTQiSjUiSzUhTDckTDYjSTQjRjIiPi8hPC0fOCoeNikeNCkdMygdMCYcLyUcLyUcLiUcLSQcLSQcLCQcLCQcLCQcLCQcLCQcLCMcLCMcLCMcKyMcKyMcLCMcLCMcLCMcLCMcLCMcLCQcLSQcLSQcLiQcLiUcLyUcMCUcMiccMiccNSkcNikdOSsdPCwePy8fQzAgRTMhSTQiSzckSTUjSTUjRjIiQC8gPC0fOCoeNSgdMyccMSYcMCUcLyUcLSQcLSQbKyMbKyMbKyMbKyIbKiIbKiIbKiIbKiIbKiIbKiIbKiIbKSIbKSIbKiIbKiIbKiIbKiIbKiIbKiIbKyIbKyMbLCMbLCMbLSQbLiUbMCUbMCYcMiYcNCgcNikdOCodPS0fQC8gQjAgSDUiSTUiRTMiRTIiQS8gPS0fOCoeNSgdMSYcMCUcLiUbLiQbLCMbKyMbKiIbKSEaKSEaKSEbKSEbKSEbKCEbKCEbKCEaKCEaKCEaJyEaJyEaJyEaJyEaJyEaKCEaKCEaKCEaKCEaKCEaKSEaKSIaKiIaKiIaLCMbLSQbLiQbMCUcMSYcMygcNikdOSsePi4fQjAfRjMgSDQgQS8gQC8gPi0fOSoeNCgcMCUcLiUbLSMaLCMaKyIaKiIaKiEaKCAaJyAaJyAaJyAaJyAaJyAaJiAaJiAaJh8aJh8aJh8aJR8ZJR8ZJR8ZJR8ZJR8ZJR8ZJh8ZJiAZJiAZJiAZJyAZJyAZKCAZKSAZKiEaKiEaKyIaLSQbMCUbMSYcMygcNikcOysdQC8fQS8fRDEfPi8gPi8gOywfNikdMSYcLyUbLCMaKiIaKiIaKSAaKCAaJyAaJiAZJh8ZJh8ZJR4ZJR4ZJR4ZJR4ZJB4ZJB4ZJB4ZIx4ZIx4ZIx4ZIx4ZIx4ZIx4ZIx4ZIx4ZJB4ZJB4ZJB4ZJB4ZJR8ZJh8ZJh8ZJyAZKCAZKiEaLCIaLiQbMCUbMSYcNSgcOSsdPi4eQC8fQzEfPS0ePS0eOSoeNigdMCUbLSMaKiEaKCAZKCAZJyAZJh8ZJh8ZJR8ZJB4ZJB0ZIx0ZIx0ZIx0ZIx0ZIh0ZIh0YIhwYIRwYIR0YIR0YIR0YIRwYIRwYIR0YIR0YIh0YIh0YIR0YIh0YIx0YJB0YJR4ZJh8ZJh8ZJyAZKSAZKyIaLSQbMCUcNCccOCodPCwePi4ePy8ePC0ePCweOCoeNCccLiQbKyIaKSAZJyAZJh8ZJh8ZJR4ZJB4ZJB4ZIx0ZIx0ZIx0ZIh0ZIh0YIh0YIR0YIR0YIR0YIR0YIRwYIRwYIR0YIR0YIR0YIRwYIR0YIR0YIRwYIh0YIR0YIh0YIx0YIx0YJB0ZJh8ZJh8ZJyAZKiEaLCMaMCUbMyccNikdOisdPCwePi4dOyseOiseNikdMiYcLSMaKiAZJyAZJh4ZJR4ZJB0ZIx0ZIx0ZIh0YIh0YIh0YIh0YIh0YIh0YIR0YIR0YIRwYIR0YIRwYIR0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIR0YIh0YIh0YIh0YIh0YJB0ZJR4ZJh8ZJyAZKiEZLSMaMCUbMycbNigbOikbOisdOSsdNikdMiYcLCIaKSAZJh8ZJR0ZJB0ZIx0YIhwYIh0YIRwYIRwYIh0YIh0YIh0YIh0YIR0YIR0YIRwYIR0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIR0YIR0YIR0YIh0YIh0YIx0YJB0ZJh4YJx8ZKSAZLCIaMCUbMSUaMiYaMSUaOisdOisdNikdMSUcLCIaKSAZJh4ZJB0ZIx0YIh0YIRwYIh0YIRwYIRwYIRwYIh0YIh0YIR0YIR0YIR0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIR0YIhwYIx0YJB0YJR4ZJh8ZKSAZLCIaLyQaMSUbMiUaMiYaOiseOiseNikdMSUcKyIaKCAZJh4YIx0YIx0YIR0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwXIh0YIhwYIx0YIx0ZJR0YJh8ZKSAZLCIZLyQaMCUaMiUaMSUaOyweOiseNikdMSUcLCIaKCAZJh4ZIx0YIx0YIRwYIR0YIRwYIRsXIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIR0YIx0YIx0YJB0YJh4ZKiAZLSMaLyQbMSUaMiYaMiYaOyweOyseNikdMSUcLCIaKSAZJh8ZJB0YIx0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIR0YIx0YIx0YJB4YJh8YKSAZLCIaLyQaMSUbMycbMycbOiseOiseNikdMSUcKyIaKCAZJh4YJB0YIh0YIR0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIR0YIh0YIx0ZIx0YJB0YJx8YKiAZLCIaLyUbMiUaMyYaMyYaOiodOiodNigcMCUbKyIaKCAZJh4YJB0YIh0YIhwXIRwYIh0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIh0YIh0YIh0YIx0YJR0ZJx8ZKiAZLCIaMCUaMiUaMyYaMyYaOyseOisdNigcMSUbKyIaKB8YJh4YJB0YIh0YIhwYIRwXIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIh0YIh0YIh0ZIx0ZIx0ZJR4YJx8YKSAZLCIZLyQaMiYaNCcaNCcaOiseOisdNSgcMCUbKyIaKCAZJh4YJB0YIxwXIRwYIRwXIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIhwYIhwYIh0YIh0YIx0ZJB0YJR0YJx8YKSAZLCIaMCUaMyYbMyYaMyYaOSsdOSodNSgcMCUbKyIaKCAZJh4YIx0YIhwYIRwXIRwYIRwXIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIhwYIhwYIhwYIx0YIh0ZIx0ZJB0ZJR4ZJh8YKSAZLCIaMCUbMiYbNScbNigbOisdOSodNCccMCUbKyEZKCAYJh4YIx0YIhwXIRwXIRwYIRsXIRsYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIhwYIh0YIh0YIh0YIx0ZIx0ZJB0ZJR4YJh8YKCAYLCIZMCUaNScbNykbNykbOSodOCkdNSccMCUbKyEZKCAZJh4ZJB0YIh0XIRwYIRsXIRsXIRwXIRwXIRwXIRwYIRwYIh0YIh0YIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIhwYIRwYIhwYIhwYIhwYIh0YIx0YIx0ZJB0ZJB4YJR0YJh4YKCAYLSMZMSUaNSgbNykbNykbOSkdOCkdNSccMCQbKyEaKB8ZJh4YIx0YIhwXIRsXIRsXIRsXIRwYIRwXIRsXIRwYIRwYIh0YIh0YIRwYIh0YIRwYIRwYIRwYIRwYIRwYIh0YIRwYIRwYIRwYIRwYIhwYIR0YIhwYIRwYIhwYIh0YIh0YIx0ZIx0ZJB0ZJR0ZJh4YKSAZLCIZMCUaNSgbOCkbOCkbOSodOCkdNSccMCUbKyEaKB8ZJh4YJB0YIh0YIRsXIRsXIRsXIRsXIRsYIRwYIRwYIR0YIhwYIR0YIRwYIhwYIRwYIRwXIh0YIRwYIR0YIh0YIhwYIRwYIRwYIRwYIRwYIR0YIh0YIh0YIhwYIh0YIh0ZIx0ZJB0ZJR0ZJh4YJx8YKSAYLSMZMCUaNCgbNigbNikaOSodOCodNCccMCUbKyEaKCAZJh4YJB0YIh0YIRwYIRsXIRwXIRwYIRwYIRwXIRwXIhwYIRwYIhwYIRwYIhwYIRwYIhwYIh0YIRwYIRwYIRwYIRwYIhwYIhwXIhwYIRwYIRwYIhwYIR0YIh0YIhwYIx0ZIx0ZJB0ZJR0ZJh8YJx8YKSAYLSMZMCUaNScbNykcNykbOCodOCkdNSccMCUbKyEaKSAZJh4ZJB0YIh0YIRwYIRwYIRwYIRwYIRwYIhwYIRwYIh0YIhwYIhwYIRwYIRwYIRwYIhwYIRwYIRwYIRwYIRwYIRwYIhwYIhwXIhwYIRwYIhwYIR0YIhwYIh0YIx0YIh0YIx0ZJB0YJR0ZJh4YJx8YKSAYLSIZMCQaNCcaNigaNigaOCkdOCkdNSgcMCUbKyEaKSAZJh4ZJB0YIx0YIhwYIRwYIRwYIRwYIhwYIRwYIRwYIhwYIhwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwYIRwXIRwXIRwYIRwXIRwXIRwYIhwYIh0YIh0YIh0YIx0YJB0ZJR4ZJh4XJx8YKSAYLSIZMCQZMyYaNScaNScaOCodOCkdNCccMCUbKiEZKCAZJh4YJB0YIx0YIhwYIRwXIRwYIRwYIRwYIRwYIhwYIRwYIRwYIRwYIRwYIRwXIRsXIRsXIRsXIRsXIRwYIRsXIRsXIRsXIRsXIRwYIRwYIRsXIRwYIhwYIh0YIh0YIh0YIx0YJB0YJB0YJh4XJx8YKiAYLCIYMCQZMiUZMyYaNCYaOisdOisdNigcMCUbKiAZKB8YJh4YJB0YIx0YIhwYIRwXIhwYIRwXIRwYIRwYIRwXIRwYIRwYIRwYIRwYIRwXIRsXIRsXIRsXIRsXIRwYIRsXIRsXIRsXIRsXIRwYIRwYIRsXIRwXIRwYIRwYIh0YIhwYIh0YJB0YJB0YJh4YJx8YKiAZLCIZMCQZMyUaNCYaNCYaQS8gQS8gNikcMSUbKiEZJx4YJh0YJB0YIx0YIhwXIRwYIRwXIRwYIRwYIRwXIRwYIRwXIRwYIRwYIRwYIRwYIRsXIRwYIRwXIRwYIRsXIRsXIRwXIRsXIRwXIRsXIRsXIRsXIRsXIRwYIRwXIh0YIh0YIx0YIx0YJR0XJh0XJx8XKiAYLSIZMCUZMyUaMyUZMyYaQjEhQjEhPi4fOCkdKiAZJx8ZKB8ZJx8ZJR4YJB4YIx0YIx0YIx0YIh0YIh0YIh0YIh0YIhwYIhwYIhwYIhwYIhwYIhwYIRwXIRwYIRwXIRwXIRwXIhwXIhwXIhwXIhwXIhwXIhwXIhwYIh0YIx0YJB0YJB4YJR4YJh4YJx8YKSAYKyEYLSIZMCUaMyUaMyYaMyYaQzEhQjAhPC0fOCkdMyYcLyQbKyIaKSAZKCAZJh8ZJR8ZJR4YJB4YJB4YIx0YIx0YIx0YIx0YIh0YIh0YIh0YIhwYIhwYIhwYIhwYIhwXIhwXIhwXIhwXIhwXIhwXIhwXIxwXIx0YIx0YJB0YJB4YJR4YJh4YJh8YJx8YKSAYKiAYKyEZLSIZMCUaMiUaMyUaMyUZRDIiQzEhPS4fOCkdMyYcMCUbLSMaKyIaKiEaKCAZJyAZJh8ZJh8ZJR4ZJR4YJB4YJB4YIx0YIx0YIx0YIx0YIx0YIh0YIh0YIhwYIhwXIhwXIhwXIxwXIxwXIx0XIx0YIx0YJB0YJB0YJR4YJR4YJh8YJx8YKB8YKSAYKiAYKyEZLCIZLSIZMCUaMyYbMyYaMyYaRDIhRDIhPi4gOCkeNCYcMCUcLiQbLSMaKyIaKiEaKSEZKCAZJyAZJh8ZJh8ZJR4ZJR4YJB4YJB4YJB0YIx0YIx0YIx0YIx0YIx0YIx0YIx0YIx0XIx0XIx0YIx0YJB0YJB0YJB4YJR4YJh4YJh8YJx8YKCAYKSAYKiAZKyEZLCIZLCIZLSMZMSUaMycaMyYaMyYZQzIhQzEhPy8gOioeNCccMCUbLyQbLiQbLSMaLCIaKiIaKSEaKCAZJyAZJx8ZJh8ZJR8ZJR4YJB4YJB4YJB0YIx0YIx0YIx0YIx0YIx0YIx0YIx0YIx0YJB0YJB0YJB0YJR4YJR4YJh4YJh8YJx8YKCAYKSAZKiEZKyEZLCIZLCIZLSMZLiMZMSUaMyYaMyUZMyUZRDMhRDIhPi8gOyseNigcMiYcMSUbMCUbLiQbLSMaLCIaKyIaKSEaKSAZKCAZJx8ZJh8ZJh8YJR4YJR4YJB4YJB0YJB0YIx0YIx0YIx0YIx0YIx0YJB0YJB0YJB0YJR4YJR4YJh4YJh8YJx8YKCAYKSAZKiEZKyEZLCIZLSIZ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Wj8oVjwnUTklSzUjRzQiRzIhRDEgPi4fOywdOCkdNSgcNCccMiYbMSUbMCUbLyMaLiMaLSIZLSMZLSMZLSMaLSIZLSIZLSMZLSMZLiMZMCQZMiUaMiUaMyYaNigbPSsdQC4eQy8dRzEeTTUgVjojWjwkVjskWTwkXD4lVzwkVjskVjskYEQqYEMqYEQqYkUqXUIpWj8oVjwnUjklTTcjSDQiSDQiRTIhPy8eOywdOCkcNigcNCgcMyYbMSUbMSUaMCQaLiMaLSMZLiMZLSMZLSMaLSMZLSIZLSMZLiMZLiMZMCQZMiUaMyYaMyYaNykbPisdQS4eRjAeSDEeTjQgWjwjWjwkVjskWDwkXD4lWTwkVjskVjsk",
        "PD9CPD9CPD9COz5BOz5COz5COj1AODs9NDc5MjQ3MDM1MDM1LjAyKy0vKCosKCosKSstKCosKCosJyksJykrJigqJigqJigqJigqJyksJyksJigqJigqJScpJScpJScpJigqJigqJigqJykrKCosKSstKiwuKy0vLS8xLjEzLjAzLjEzMDI1MjQ3MjQ3MTQ2MTQ2PD9CPD9CPD9COz5BOz5COz5COj1AODs9NDY5MTQ2MDI1LzI0LTAyKy0vKCosKCosKCosKCosKCosJykrJigqJigqJigqJigqJigqJyksJyksJigqJigqJScpJScpJScpJScpJigqJigqJigqKCosKSstKiwuKiwuLC4wLjAzLjAzLjEzMDM1MjQ3MTQ2MTQ2MTQ2Oz5BOz5CPD9CPD9COj1AODs+NTg7NDY5MDM1LjEzLC8xLC4wKiwvKSstKCosJykrJigqJigpJScpJScpJScpJScpJSYoJSYoJScpJScpJScpJScpJScpJScpJScpJScpJScpJScpJScpJigqJykrKCosKCosKSstKiwuKiwvLC4wLjAyMDM1MjQ3MTQ2MDM1LzI0OTw/OTw/Oz5BOj1ANzo9NTg6MjQ3LzI0LjAzLC4xKy0vKiwuKCstKCosJigqJScpJScpJCYoJCYoJCUnIyUnJCUnIyUnIyUnIyUnJCYoJCYoJSYoJCUnIyUnJCUnJCUnJCYoJCYoJScpJScpJigqJicpJykrKCosKCstKiwuKy0vLC4wLjAzMDI1LzI0LzE0LzE0OTw/OTw/ODs+Njk8MzY4MDM2LzE0LS8xKiwvKSstKCstKCosJykrJigqJScpJCUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIyUnIiQmIyUnIyUnIyUnIyUnJCYnJCYoJScpJScpJigqJykrKCosKCosKiwuKiwuKy0vLC4xLzE0LzI0LzI0ODs+ODs+NTg7MzY5MDI1LjEzLS8xKiwvKSstJykrJScpJScpJScpJCYnJCUnIiQmIiQmISMkISMlIiQmIiQlISMlIiQmIiQmIiQmIiQmISMlIiMlIiMlISMkISMkISMlIiQmIiQmIiQmIyUnJCYnJCYoJCYoJScpJigqJigqKCosKSstKSstKy0vLjAyLzE0LzE0Njg7Njg7MzY4MDM1LjEzKy0vKSstKCosJigqJScpJCYoJCYnIiQmIiQmISMlISMkISIkICIjICIjICIjICIjICIjICIjISMkISMkISIkISIkICIjICEjHyEiICEjICIjICIjISMkISMlISMlIiQmIyUmJCYnIyUnJCYoJScpJScpJykrKSstKSwuKy0vKy0vKy0vNjg7NTg7MTQ3LjEzKy0wKSsuJykrJigqJCYoJCYoIiQlIiMlISMlISMkICIjICIjICIjICIjHyEiHyEiICEjICEjICEjICEjHyEiICIkISIkICEjHyEiHyAiHyAiHyAiHyEiICIjICIjISIkISMlISMlIiMlIyUmIyUnIyUnJScpJScpJykrJykrKSwuKy0vLC4xMzY4MzU4LzEzLC4xKCotJykrJScoJCYoJCYnIiQmISIkHyEjHyEjHyEjHyEiHyEiHyEiHyEiHyEiHyAiHyAiHyAiHyAiHyAiHyAiHyAiHyEiHyAiHyAiHyAiHh8hHyAiHyAiHyEiHyEiHyEjHyEjICIkISIkISMkISMlIiQmIyUnJSYoJScpJicpJykrKSsuKi0vLzI0LzI0LC8xKiwuJykrJScpJCYoJCUnIiMlISIkHyEjHyEiHyAiHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHh8hHiAhHiAiHyEjHyEjICEjICEjICIkISMlIiQmIiQmJCUnJScpJigqJykrKCosLjAyLTAyKiwuJykrJScoJCYoIiQmIiMlICIkHyEjHiAhHh8hHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHR4gHh8hHh8hHR8gHR8gHiAhHyEjHyEjICEjICIjISMkISMlIiQmIyQmJScpJigqJigqKy4wKi0vKCosJScpIyUnIiQmISMkICEjHyEjHyAiHh8hHB4fHB0fHB0fHB0fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4fHR4gHR4gHR4gHR4gHR8gHh8hHiAiHyEiHyAiICEjICEjICIkIiQmIyUnJScoJCYoKSstKSstJigqJCYoIiQmICIkICEjHyEjHh8hHR4gHB4fHB0fHB0eGx0eGx0eHB0eHB0eHB0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eGx0eHB0eHB0eHB0eHB0eHB0fHB0fHR4gHB0fHR8gHR8gHR8gHiAiHyEiICEjICIjIiMlIyUnJCYnJykrJykrJScpIiQmICIjICEjHyEjHR8hHB0fHB0fHB0fHB0eGxwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGhwdGx0eGx0eGx0eGx0eHB0eHB0eHB0fHB0fHB0fHR4gHR8gHiAhHyAiICEjISMlIiQmIiQmJigqJigqJCUnISMlICEjHyAiHR8gHB0fHB0fHB0fHB0eGxwdGhwdGhwdGhwdGhwdGhwdGRscGRscGhwdGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGhwdGhwdGhwdGhwdGxwdGx0eHB0eHB0fHB0fHB0fHB4fHR8gHh8hHyEjISMkISMlISMlJScpJScpIyUmISMlHyEiHR8gHB0fHB0fGxweGxwdGxwdGhwdGhwdGRscGhwdGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGRscGRscGRscGhwdGRscGhwdGhwdGx0eGx0eHB0eHB0eHB0eHB0fHB0fHR8gHiAiICIjISMlISMlJCYoJCYoISMlICIjHh8hHB0fHB0fGxwdGx0eGhscGRscGRscGRscGhwdGRscGRscGRscGRobGRscGRscGRobGBobGRscGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGhwdGhwdGx0eGx0eGxwdGxwdGxweHB0fHB4fHiAhICIjISMlISMlIyUmIyUmISIkHyEjHB4fHB0fGxwdGhscGhwdGRscGRscGRscGRobGRscGRscGRscGRscGRobGRscGRscGRobGRobGRscGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGhwdGhscGhwdGhwdGx0eHB0eHB0fHR8gHyEjISIkISMkIyUmIyUmISIkHyAiHB4fHB0fGxwdGhwdGRscGRobGBobGBobGBobGRobGRscGRscGRscGRscGRscGRscGRobGRobGRobGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGhwdGRscGRscGhwdGxwdGxweHB0fHR8gHyAiISMkISMkIyUmIyQmISIkHiAiHB4fHB0fGxwdGhwdGRscGRscGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGRscGhwdGhwdGxweGxweHB0fHiAhHyEjISMkIiMlIyUnIyQmICIkHiAiHB4fHB0fGxwdGRscGRscGRobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGRscGhwdGhwdGhwdHB0eHB0fHiAhICEjIiMlIiMlIyUmIyQmICIkHiAiHB4fGxweGhscGRscGRscGRscGRobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGRscGRscGRscGRscGRscGRscGRobGRobGBobGRscGRscGhwdGhwdGhwdGhwdHB0eHB0fHiAhICEjIiMlIiQlIyQmIyQmICIkHh8hHB4fGxweGhscGRscGRscGRobGRobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGhwdGx0eGx0eHB0eHB0fHiAhICIjIiQlIiQmIyUmIyQmICIkHh8hHB0fGxweGhsdGRscGRscGRobGRobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGhwdGhwdGx0eHB0eHB0fHiAhHyEjIiQlIiQmIyUmIyQmICIkHh8hHB4fGxweGxwdGhscGRscGRobGRobGRobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGRscGhwdGxwdGx0eHB0eHB0fHh8hICEjIiQlIiQmJCYnJCUnICIkHh8hHB4fGxweGxwdGRscGRscGRobGRobGRobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGhwdGhwdGx0eHB0eHB4fHiAhICEjIiQlIiQmIyUnIyUmISIkHh8hHB4fGxweGxwdGhscGRscGRobGRobGBobGRobGRobGRobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRobGRscGhwdGRscGhwdGhwdHB0eHR4gHiAhICEjIiQlIyUmIyUnIyUnISIkHh8hHB4fGxweGhsdGRscGRscGRobGRobGRobGRobGRobGRobGRobGRobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGBobGBobGBobGBobGBobGBobGRobGBobGBobGBobGRobGRobGRscGRscGhwdGxwdHB0eHB0fHiAhHyEjJykrKCosIyUnIyUnISIkHh8hHB4fGxweGhscGRscGRscGRscGRscGRscGBobGRobGRobGRobGRobGRobGBobGBobGRobGBobGRobGBobGRocGRscGRobGBobGBobGBobGBobGBobGBobGRobGBobGBobGRobGRscGRscGRscGRscGRscGhwdGxweHB0fISMlIyUnJigqJigqIiQmIiQmICIkHh8hHB4fGxweGhsdGhscGRscGRscGRobGRobGRobGRobGRobGRscGRobGRscGBobGBobGRscGBobGRobGBobGRocGRscGRobGBobGBobGBobGBobGBobGBobGRscGBobGBobGBobGBobGRobGRscGRscGhscGhwdHB4fHyEjISMkIyUnJigqJykrIiQmIiQmICIkHh8hHB0fGxweGhscGhscGRobGRobGRobGRobGRocGRobGRobGRocGRobGBobGBobGRscGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGBobGRobGBobGBobGRobGRscGRobGRobGhwdHR4gHh8hICEjICIkIyUnJykrKCosIiQmIiQlISIkHh8hGx0eGxweGhsdGRscGRscGRobGRobGBobGRobGRobGRobGRobGRobGRocGRobGRscGBobGRobGBobGRscGRscGRobGRobGBobGBobGBobGBobGRobGBobGBobGBobGBobGRobGRscGRobGRscGRscHB0fHB4fHiAiICIjISMlIyUmJigqJykrIyUmIyUmICIkHh8hHB0fGxweGhsdGhscGRobGRscGRobGRobGRscGRobGRscGRobGRscGRscGRobGRscGBobGBobGBobGRobGRobGRobGRobGBobGBobGBobGBobGRobGRobGRobGRobGRobGRscGRobGRscGRscGx0eHB4fHR4gHiAiICIjISMlJCYnJigqJykrIyUmIyUmISIkHh8hHB0fGxweGhsdGhscGRobGRobGRobGBobGRocGRobGRobGRscGRscGRscGRscGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRocGRobGRscGRscGRscGRscGhsdHB0fHB4fHR4gHiAiICEjISMlIyUnJScpJykrIyQmIyQmISIkHh8hHB4fGxweGhsdGRscGRscGRobGRobGRobGBobGBobGRscGRobGRscGRscGRscGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRobGBobGRobGRobGRscGhsdHB0fHB4fHh8hHh8hICIjISMlIyUmJigqJigqIyQmIyQmISIkHiAhHB4fGx0eGhsdGRobGRscGRobGBobGBobGBobGRobGBobGBobGRobGRscGRscGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGBobGBobGRobGRobGRscGhscGxweHB0fHB0fHR4gHh8hICEjISMlIyQmJScpJScpIyQmIiQmISIkHyAiHB4fGx0eGxwdGhscGRscGBobGRobGBobGRobGBobGBobGBobGRobGRobGRobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRscGRscGhscGhwdGx0eHB0fHR4gHh8hICIjISMlIyQmJScpJScpIiMlIiQmICIkHyAiHB4fHB0fGxweGxwdGhscGhscGRscGRobGRobGRobGRobGRobGRobGRobGRobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGhscGhscGhsdGhsdGxweGx0eHB4fHh8hHyAiICIjISMlIiQmJScoJScpIyQmIyQmICIkHiAiHB4fHB0fGxweGxweGhsdGhsdGhscGhscGhscGhscGRscGRobGRobGRobGRobGRobGRobGRobGBobGBobGBobGBobGBobGBobGRobGRobGRobGRobGRscGhscGhscGhsdGhsdGxweGxweGx0eHB4fHR4gHh8hHyAiICEjISMlIyUnJScoJScpJCYoJCYnISMkHyAiHB4fGx0eGxweGxweGxweGxweGhsdGhsdGhsdGhscGhscGhscGhscGRscGRscGRobGRobGRobGRobGRobGRobGRobGRobGRobGRobGRscGRscGhscGhscGhscGhsdGhsdGxweGxweGx0eHB4fHB4fHR8gHh8hHyAiHyEiICIkIyQmJScpJScpJCYoJCYoISMkHyAiHB4fGx0eGx0eGxweGxweGxweGxweGhsdGhsdGhsdGhsdGhscGhscGhscGhscGRscGRscGRscGRobGRobGRobGRobGRscGRscGRscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eHB4fHB4fHR4gHh8hHh8hHyAiHyEiICIkIyQmJSYoJScpJigqJigqIyUmICIjHR4gHB0fHB0fHB0fGx0eGx0eGxweGxweGxweGhsdGhsdGhsdGhsdGhscGhscGhscGhscGRscGRscGRscGRscGRscGRscGhscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eGx0eHB4fHB4fHR4gHh8hHh8hHyAiHyEiICIkIiQmJCYnJSYoJykrJigqJCYoIiMlHh8hHB0fHB4fHB4fHB4fHB0fGx0eGxweGxweGxweGhsdGhsdGhsdGhsdGhscGhscGhscGhscGhscGRscGRscGhscGhscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eGx0eHB4fHB4fHR4gHh8hHh8hHh8hHyAiHyAiICIkIiQlJCYoJSYoJyksJykrJScoIiMlHyEiHh8hHR8gHR4gHB4fHB4fHB4fGx0eGx0eGxweGxweGhsdGhsdGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGhsdGxweGxweGx0eGx0eHB4fHR4gHR4gHh8hHh8hHh8hHyAiHyAiICIkIyQmJCYnJCYoKiwuKSstJigqIiQlICIjHh8hHh8hHh8hHR4gHR4gHB4fHB4fGx0eGxweGxweGxweGhsdGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eGx0eHB4fHB4fHR4gHh8hHh8hHh8hHyAiHyAiHyAiICIkIiQlJCYoJCYoKy0vKiwuJigqIyUnISIkHyEiHyEiHiAhHh8hHh8hHR4gHB4fHB4fGx0eGxweGxweGxweGhsdGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGhsdGxweGxweGx0eGx0eHB4fHR4gHR4gHh8hHh8hHyEiHyEiHyEjHyEiISIkIyUmJCYoJCYoLS8xLC4wKCosJCYoISMkICIkHyEjHyEiHiAhHh8hHR4gHB4fHB4fGx0eGx0eGxweGxweGhsdGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGhsdGxweGxweGx0eHB4fHB4fHR4gHh8hHh8hHyEiHyEiICEjICIkICIkIiQlJCYoJScpJigqLjEzLS8yKiwuJigqIiQmISMkICIkHyEjHyEiHiAhHh8hHR4gHB4fHB4fGx0eGxweGxweGhsdGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eHB4fHR4gHR4gHh8hHiAhHyEiICEjICIkISIkISMkIyUnJScpJigqJigqMDI1LzI0Ky0wJykrJCUnIiQlISMkICIkHyEiHiAhHh8hHR4gHB4fHB4fGx0eGxweGxweGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGxweGxweGx0eHB4fHR4gHR4gHh8hHiAhHyEjICIkISMkIiQmIiQmJScpJigqJyksKSstMzY4MjU3LC4wKSstJigqIyUnIiQmISMkHyEjHyEiHiAhHR4gHB4fHB4fGx0eGxweGxweGhsdGhsdGhscGhscGhscGhscGhscGhscGhscGRocGRocGhscGhscGhsdGhsdGxweGxweHB0fHB4fHR4gHR8gHh8hHyEiICEjISMkIiQmIyUnJCYoJigqKCstKi0vLC4wMzY4MzY4LjAzKy0vJykrJigqIyUnISMkICIkHyEiHiAhHR8gHB4fHB4fGx0eGxweGxwdGhsdGhscGhscGRobGRobGRscGhscGhscGhscGRocGRobGRscGRocGRocGhsdGxweGxweHB0fHB4fHR4gHR8gHR8gHyEiICIkISMlIyQmJScpJigqKSstKy0wLC4xLC4xNDc5NDc5MDM1LS8xKSstJigqJSYoJCYoISMkICIkHyEiHiAhHh8hHR4gHB4fHB0fGx0eGxweGxweGxweGhscGhscGhscGhscGhscGhscGhsdGhsdGhsdGhsdGhsdGhsdGx0eHB0fHB4fHR4gHh8hHiAhHyEjISIkISMlIyQmJScpJigqKSstKy4wLTAyLjAzLjAzMzY4MzY4MzY4LzE0Ky4wKSwuJigqJScpIyUnIiMlISIkHyEiHiAhHh8hHR4gHR8gHB4fHB0fHB0fGx0eGxweGxweGxweGhsdGhsdGxweGxweGx0eGxweGx0eGxweGx0eHB4fHR4gHR8gHh8hHyEiICIkISMkIiQmIyUnJScpJykrKSstKy4wLS8yMDI1MDM1MDM1NDc6NDc6NDY5MjQ3LjAzKy4wKCstJigqJigqIyUnIiMlISIkHyEjHyEiHyAiHiAiHR8gHB4fHB4fHB0fHB0fHB0fGxweGx0eGxweHB0fHB0fHB0fHB0fHB0fHB4fHB4fHR4gHh8hHiAhICIjISIkISMkIiQmJCUnJigqJykrKSsuKy4wLjAyMDM1MDM1MDI1MDI1NDY5MzY4NTg7NTc6MTM2LzE0LC4wKiwvJyksJigqIyUnIiQmIiMlISIkICEjHyAiHyAiHyAiHiAhHR4gHB4fHB4fHB4fHB0fHB4fHB4fHB4fHB4fHB4fHR4gHR4gHR4gHiAhHyEiICIkISIkIiQlIyUnJScpJigqKCosKiwvLC4xLzEzMTQ2MzY4MjU4MDM1MDM1NDc5NTg7NTg6MjQ3MTM2MTQ2MDM1LS8xKiwuKiwuKCotJScoIiMlIiMlISMlICIjICEjHyEjHyEiHyAiHiAiHh8hHR4gHR4gHR4gHR4gHh8hHiAiHh8hHh8hHyEiHyEiICIjICIkISIkIiQlIyUnJigqKCosKy0vLjAzMDI1MDI1MDI1MTM2MjU3MzY5MjU4MjQ3NTg7NDc6NTc6MTQ2MTM2MTQ2MDM1LjAzKy0wKiwuKSstJScoIiMlISMkISMlICIkICEjICEjHyEjHyAiHiAiHh8hHR4gHR4gHR4gHR4gHh8hHyAiHh8hHiAiICIjICIjICIkICIkISMkISMlIyUnJigqKCosLC8xMDM1MTM2MDI1MDI1MTM2MjU3MzY4MjU4MjU4"
    ]
    static let images: [CGImage] = samples.map { encoded in
        let data = Data(base64Encoded: encoded)!
        return CGImage(width: 49, height: 57, bitsPerComponent: 8, bitsPerPixel: 24,
            bytesPerRow: 49 * 3, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: CGDataProvider(data: data as CFData)!,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
    static let rims: [[Color]] = [
        [Color(hex: 0x1DA974), Color(hex: 0x20AA74), Color(hex: 0x20AA75), Color(hex: 0x1CAC76), Color(hex: 0x1DB078), Color(hex: 0x25CC8B), Color(hex: 0x25D08E), Color(hex: 0x37EDB2), Color(hex: 0x44EFB2), Color(hex: 0x3CF7BF), Color(hex: 0x3DF9BB), Color(hex: 0x3BFFC1), Color(hex: 0x41F6B6), Color(hex: 0x2CC586), Color(hex: 0x1A9765), Color(hex: 0x17885A), Color(hex: 0x178D5B), Color(hex: 0x158859), Color(hex: 0x158D5B), Color(hex: 0x178A5B), Color(hex: 0x17925E), Color(hex: 0x15905E), Color(hex: 0x199160), Color(hex: 0x20A86F), Color(hex: 0x3FFAB6), Color(hex: 0x3FFFC3), Color(hex: 0x42FACC), Color(hex: 0x33F5BF), Color(hex: 0x46F5C6), Color(hex: 0x28C994), Color(hex: 0x1EA479), Color(hex: 0x1DA97D), Color(hex: 0x1FB182), Color(hex: 0x1FB684), Color(hex: 0x20B987), Color(hex: 0x21B685), Color(hex: 0x22B484), Color(hex: 0x1FB083), Color(hex: 0x1FB084), Color(hex: 0x2DC999), Color(hex: 0x2DD7A1), Color(hex: 0x31E6AC), Color(hex: 0x36ECB4), Color(hex: 0x36D4A3), Color(hex: 0x41F6C2), Color(hex: 0x35F7C5), Color(hex: 0x34FBCD), Color(hex: 0x3AF7C5), Color(hex: 0x43FFCA), Color(hex: 0x28C78A), Color(hex: 0x209A6C), Color(hex: 0x1D9A6A), Color(hex: 0x1D9B6C), Color(hex: 0x1DA16F), Color(hex: 0x19A370), Color(hex: 0x1AA270), Color(hex: 0x1BA773), Color(hex: 0x1FA070), Color(hex: 0x1EA272), Color(hex: 0x2DD99A), Color(hex: 0x45FFC8), Color(hex: 0x47FABC), Color(hex: 0x2CB07D), Color(hex: 0x269E71), Color(hex: 0x20A16F), Color(hex: 0x1EA270), Color(hex: 0x1DA06D), Color(hex: 0x1A9E70), Color(hex: 0x1BA370), Color(hex: 0x1AA470), Color(hex: 0x1AA46E), Color(hex: 0x1EAB76), Color(hex: 0x1DA974)],
        [Color(hex: 0xF57061), Color(hex: 0xF46F63), Color(hex: 0xF66C5E), Color(hex: 0xF36E5E), Color(hex: 0xEF6355), Color(hex: 0xEE554F), Color(hex: 0xF3584F), Color(hex: 0xF56860), Color(hex: 0xF86F75), Color(hex: 0xEB707E), Color(hex: 0xFA7584), Color(hex: 0xFF7787), Color(hex: 0xFF7F89), Color(hex: 0xF5565F), Color(hex: 0xC2464F), Color(hex: 0xB4424A), Color(hex: 0xAD3D49), Color(hex: 0xAB3C47), Color(hex: 0xA93C47), Color(hex: 0xAE3F4A), Color(hex: 0xB6424C), Color(hex: 0xB4404B), Color(hex: 0xBE474E), Color(hex: 0xF04F5D), Color(hex: 0xFF7787), Color(hex: 0xFB8094), Color(hex: 0xF78091), Color(hex: 0xFE7A93), Color(hex: 0xF87180), Color(hex: 0xF96471), Color(hex: 0xF3474D), Color(hex: 0xFA4C51), Color(hex: 0xF74A52), Color(hex: 0xF54950), Color(hex: 0xF94F54), Color(hex: 0xFA4E55), Color(hex: 0xF95157), Color(hex: 0xFE5859), Color(hex: 0xF95759), Color(hex: 0xF85255), Color(hex: 0xF94D52), Color(hex: 0xF74950), Color(hex: 0xF94D53), Color(hex: 0xFC6A73), Color(hex: 0xFC7180), Color(hex: 0xF9768B), Color(hex: 0xFC8294), Color(hex: 0xF97F8F), Color(hex: 0xFF8197), Color(hex: 0xFF5E72), Color(hex: 0xBF4557), Color(hex: 0xBB4658), Color(hex: 0xBD4658), Color(hex: 0xB74457), Color(hex: 0xB94456), Color(hex: 0xC34659), Color(hex: 0xC3465B), Color(hex: 0xCA475B), Color(hex: 0xD04B5E), Color(hex: 0xFF5C71), Color(hex: 0xFF93A1), Color(hex: 0xFF7E90), Color(hex: 0xFA7685), Color(hex: 0xF1677C), Color(hex: 0xF46E77), Color(hex: 0xF45458), Color(hex: 0xED4C4D), Color(hex: 0xF35153), Color(hex: 0xF04E50), Color(hex: 0xF2534F), Color(hex: 0xF56A5B), Color(hex: 0xF5695C), Color(hex: 0xF57061)],
        [Color(hex: 0xFFBF60), Color(hex: 0xFFC362), Color(hex: 0xFFC262), Color(hex: 0xFFB85D), Color(hex: 0xF99F53), Color(hex: 0xE38849), Color(hex: 0xC37642), Color(hex: 0xCE7A41), Color(hex: 0xD07D42), Color(hex: 0xC68040), Color(hex: 0xDC9149), Color(hex: 0xFFBB5D), Color(hex: 0xFFDD6D), Color(hex: 0xFFB054), Color(hex: 0xC5793D), Color(hex: 0xB67138), Color(hex: 0xB87139), Color(hex: 0xB36F36), Color(hex: 0xB97238), Color(hex: 0xB97239), Color(hex: 0xBD783C), Color(hex: 0xBE783C), Color(hex: 0xBE793D), Color(hex: 0xCD823D), Color(hex: 0xFFDE6E), Color(hex: 0xF3A14D), Color(hex: 0xE0964D), Color(hex: 0xD98D48), Color(hex: 0xD78B43), Color(hex: 0xD68842), Color(hex: 0xF3A04A), Color(hex: 0xFBAE52), Color(hex: 0xFFBB58), Color(hex: 0xFFBD5C), Color(hex: 0xFFBC5A), Color(hex: 0xFFBA57), Color(hex: 0xFFBA56), Color(hex: 0xFCB956), Color(hex: 0xFFBB58), Color(hex: 0xFFBD59), Color(hex: 0xFFBD56), Color(hex: 0xFFC158), Color(hex: 0xFFC058), Color(hex: 0xE19449), Color(hex: 0xC9803E), Color(hex: 0xDB8E49), Color(hex: 0xC88040), Color(hex: 0xEB9A4C), Color(hex: 0xF3A152), Color(hex: 0xD28543), Color(hex: 0xC67E42), Color(hex: 0xD08445), Color(hex: 0xD08142), Color(hex: 0xD78543), Color(hex: 0xE38E47), Color(hex: 0xF1964A), Color(hex: 0xF59C4E), Color(hex: 0xE78F49), Color(hex: 0xD08445), Color(hex: 0xEA974D), Color(hex: 0xF39D50), Color(hex: 0xDB8E49), Color(hex: 0xD78644), Color(hex: 0xBF7C42), Color(hex: 0xAF7340), Color(hex: 0xFFB75B), Color(hex: 0xFFC863), Color(hex: 0xFFB75A), Color(hex: 0xFFBB60), Color(hex: 0xFFBD5D), Color(hex: 0xFFBC5D), Color(hex: 0xFFBE60), Color(hex: 0xFFBF60)],
        [Color(hex: 0x868D94), Color(hex: 0x858C93), Color(hex: 0x838A91), Color(hex: 0x848A91), Color(hex: 0x7B8187), Color(hex: 0x70767C), Color(hex: 0x737A80), Color(hex: 0x80878D), Color(hex: 0x878E95), Color(hex: 0x868D94), Color(hex: 0x8D949B), Color(hex: 0x8F979E), Color(hex: 0x959CA4), Color(hex: 0x747A80), Color(hex: 0x5D6267), Color(hex: 0x575C60), Color(hex: 0x52575B), Color(hex: 0x515559), Color(hex: 0x515559), Color(hex: 0x54585D), Color(hex: 0x585C61), Color(hex: 0x565A5F), Color(hex: 0x5D6267), Color(hex: 0x6E7379), Color(hex: 0x8F979E), Color(hex: 0x959DA5), Color(hex: 0x949CA4), Color(hex: 0x9299A1), Color(hex: 0x899097), Color(hex: 0x7F868D), Color(hex: 0x686D72), Color(hex: 0x6D7278), Color(hex: 0x6B7076), Color(hex: 0x6A6F75), Color(hex: 0x6F757A), Color(hex: 0x6E747A), Color(hex: 0x70767C), Color(hex: 0x767D83), Color(hex: 0x757B81), Color(hex: 0x71777D), Color(hex: 0x6D7379), Color(hex: 0x6A7075), Color(hex: 0x6D7379), Color(hex: 0x848B92), Color(hex: 0x8A9198), Color(hex: 0x8D959C), Color(hex: 0x979FA7), Color(hex: 0x949CA3), Color(hex: 0x979FA7), Color(hex: 0x7C8389), Color(hex: 0x5C6166), Color(hex: 0x5C6166), Color(hex: 0x5D6266), Color(hex: 0x5A5F63), Color(hex: 0x5A5F64), Color(hex: 0x5E6368), Color(hex: 0x5E6368), Color(hex: 0x60656A), Color(hex: 0x646A6F), Color(hex: 0x7B8188), Color(hex: 0xA4ADB5), Color(hex: 0x959CA4), Color(hex: 0x8D959C), Color(hex: 0x81878E), Color(hex: 0x868D93), Color(hex: 0x72777D), Color(hex: 0x6A6F75), Color(hex: 0x6F757B), Color(hex: 0x6C7277), Color(hex: 0x70767C), Color(hex: 0x81888F), Color(hex: 0x80878E), Color(hex: 0x868D94)]
    ]
}
