import SwiftUI

public struct TodayHeroCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let workout: Workout?
    let programId: String?
    let todayIndex: Int
    let isCompleted: Bool
    let isAvailable: Bool
    let availableDay: String?
    let hasUnfinishedProgress: Bool
    let onStart: () -> Void

    @State private var selectedViewIndex: Int?

    @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var bodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var actionSize: CGFloat = 15
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public static let cardHeight: CGFloat = 420
    /// Dark suites fade the surface into the photograph on a diagonal from the top-left copy toward the lower right.
    private static let scrimEnd = UnitPoint(x: 1, y: 0.5)
    private var textWidth: CGFloat? { dynamicTypeSize >= .xxxLarge ? nil : (themeManager.currentTheme.isDark ? 215 : 172) }

    private var workoutScrim: [Gradient.Stop] {
        return [.init(color: cardSurface, location: 0),
                .init(color: cardSurface.opacity(0.94), location: 0.25),
                .init(color: cardSurface.opacity(0.50), location: 0.51),
                .init(color: cardSurface.opacity(0.03), location: 0.76),
                .init(color: .clear, location: 1)]
    }
    private var recoveryScrim: [Gradient.Stop] {
        return [.init(color: cardSurface, location: 0),
                .init(color: cardSurface.opacity(0.95), location: 0.26),
                .init(color: cardSurface.opacity(0.50), location: 0.48),
                .init(color: cardSurface.opacity(0.04), location: 0.64),
                .init(color: .clear, location: 0.74), .init(color: .clear, location: 1)]
    }
    /// Light suites draw the athlete over their own warm paper, not over the photograph's black studio. Ivory glows
    /// behind the head at the upper right and deepens diagonally into sand at the lower left, where the copy sits.
    private var lightBackdrop: some View {
        let sand = Color.mix(cardSurface, AppColors.border, 0.70)
        return ZStack {
            AppColors.surface
            LinearGradient(stops: [
                .init(color: sand, location: 0),
                .init(color: sand.opacity(0.85), location: 0.20),
                .init(color: sand.opacity(0.42), location: 0.50),
                .init(color: sand.opacity(0), location: 0.95)
            ], startPoint: .bottomLeading, endPoint: .topTrailing)
        }
    }
    private var workoutVerticalScrim: [Gradient.Stop] {
        return [.init(color: .clear, location: 0), .init(color: .clear, location: 0.20),
                .init(color: cardSurface.opacity(0.12), location: 0.44),
                .init(color: cardSurface.opacity(0.96), location: 0.83),
                .init(color: cardSurface, location: 0.96), .init(color: cardSurface, location: 1)]
    }

    private var cardSurface: Color { AppColors.heroSurface }
    private var cardBorder: Color { AppColors.heroBorder }
    private var selectedViewSurface: Color { AppColors.bodyViewSelectedSurface }
    private var selectedViewBorder: Color { AppColors.bodyViewSelectedBorder }
    private var selectedViewText: Color { AppColors.bodyViewSelectedText }

    public init(
        workout: Workout?,
        programId: String? = nil,
        todayIndex: Int,
        isCompleted: Bool,
        isAvailable: Bool,
        availableDay: String?,
        hasUnfinishedProgress: Bool,
        initialViewIndex: Int? = nil,
        onStart: @escaping () -> Void
    ) {
        self.workout = workout
        self.programId = programId
        self.todayIndex = todayIndex
        self.isCompleted = isCompleted
        self.isAvailable = isAvailable
        self.availableDay = availableDay
        self.hasUnfinishedProgress = hasUnfinishedProgress
        self._selectedViewIndex = State(initialValue: initialViewIndex)
        self.onStart = onStart
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        if let workout = workout {
            workoutCard(workout)
        } else {
            restDayCard()
        }
    }

    private func workoutCard(_ workout: Workout) -> some View {
        let bodyViews = Self.bodyViewOptions(for: workout)
        let activeIndex = selectedViewIndex.flatMap { bodyViews.indices.contains($0) ? $0 : nil }
            ?? 0
        let activeView = bodyViews[activeIndex]

        return VStack(alignment: .leading, spacing: 0) {
            // Top row
            HStack(alignment: .center) {
                let dayText: String = {
                    if workout.day == todayIndex + 1 {
                        return LanguageManager.t("today.todayWorkout")
                    } else if LanguageManager.workoutDays.indices.contains(workout.day - 1) {
                        return LanguageManager.workoutDays[workout.day - 1]
                    }
                    return ""
                }()

                Text(dayText)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)

                Spacer()

                if isCompleted {
                    ZStack {
                        Circle()
                            .fill(cardSurface)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: captionSize, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            .frame(minHeight: 20)

            Spacer().frame(height: 20)

            // Title
            Text(workout.displayTitle(programId: programId))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: textWidth, alignment: .leading)
                .accessibilityIdentifier("today-workout-title")

            Spacer().frame(height: 10)

            // Focus
            if !workout.focus.isEmpty {
                Text(workout.displayFocus(programId: programId))
                    .font(.system(size: bodySize, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: textWidth, minHeight: 42, alignment: .topLeading)
                    .accessibilityIdentifier("today-workout-focus")
            }

            Spacer(minLength: 20)

            // Show every required view, including the selected indicator for a single view.
            if !bodyViews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(bodyViews.enumerated()), id: \.offset) { idx, v in
                            let isSel = idx == activeIndex
                            Button(action: { selectedViewIndex = idx }) {
                                Text(LanguageManager.t("muscles.view.\(v.rawValue)"))
                                    .font(.system(size: captionSize, weight: .medium))
                                    .foregroundStyle(isSel ? selectedViewText : AppColors.secondaryText)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                             .fill(isSel ? selectedViewSurface : cardSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                             .strokeBorder(isSel ? selectedViewBorder : cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(TodayHeroActionButtonStyle())
                            .disabled(isSel)
                            .accessibilityIdentifier("muscle-view-\(v.rawValue)")
                            .accessibilityAddTraits(isSel ? .isSelected : [])
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: 20)
            }

            // Meta
            let mins = max(25, workout.exercises.count * 8)
            let meta = LanguageManager.t("today.workoutMeta", [
                "exercises": workout.exercises.count,
                "minutes": mins
            ])
            Text(meta)
                .font(.system(size: captionSize, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 22)

            // Button
            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: isCompleted ? "checkmark" : (availableDay != nil ? "clock" : "play.fill"))
                        .font(.system(size: actionSize, weight: .semibold))

                    Text(buttonTitle())
                        .font(.system(size: actionSize, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill((isAvailable && !isCompleted) ? AppColors.accent : AppColors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            (isAvailable && !isCompleted)
                                ? Color.clear
                                : (isCompleted ? AppColors.accent.opacity(0.4) : AppColors.border),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    (isAvailable && !isCompleted)
                        ? AppColors.background
                        : (isCompleted ? AppColors.accent : AppColors.secondaryText)
                )
            }
            .disabled(!isAvailable || isCompleted)
            .buttonStyle(TodayHeroActionButtonStyle())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("today-start-workout")
        }
        .padding(EdgeInsets(top: 22, leading: 19, bottom: 20, trailing: 19))
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
        .background {
            ZStack(alignment: .topLeading) {
                // Container background
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )

                if !themeManager.currentTheme.isDark {
                    // The open upper-right studio uses Oat's ivory, blending diagonally into beige at the lower left.
                    lightBackdrop
                }

                // Muscle artwork underlay
                MuscleArtwork(view: activeView, muscles: workout.resolvedMuscles,
                    subjectOnly: !themeManager.currentTheme.isDark)
                    .opacity(!themeManager.currentTheme.isDark && dynamicTypeSize >= .xxxLarge ? 0.02 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                // Light heroes put their own palette behind the athlete, without a horizontal cover.
                if themeManager.currentTheme.isDark {
                    LinearGradient(stops: workoutScrim, startPoint: .topLeading, endPoint: Self.scrimEnd)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                }

                // Vertical Gradient scrim (matching Android 1-to-1)
                LinearGradient(stops: workoutVerticalScrim, startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                if !themeManager.currentTheme.isDark {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .padding(.horizontal, 20)
        .onChange(of: workout.id) { _, _ in selectedViewIndex = nil }
    }

    static func bodyViewOptions(for workout: Workout) -> [BodyView] {
        workout.bodyViews()
    }

    private func buttonTitle() -> String {
        if isCompleted {
            return LanguageManager.t("today.completed")
        }
        if let day = availableDay {
            return LanguageManager.t("today.availableOn", ["day": day])
        }
        if hasUnfinishedProgress {
            return LanguageManager.t("plan.resumeWorkout")
        }
        return LanguageManager.t("plan.startWorkout")
    }

    private func restDayCard() -> some View {
        let weekdayName = LanguageManager.workoutDays.indices.contains(todayIndex)
            ? LanguageManager.workoutDays[todayIndex]
            : ""

        return VStack(alignment: .leading, spacing: 0) {
            // Top row
            Text(weekdayName)
                .font(.system(size: captionSize, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .frame(minHeight: 20)

            Spacer().frame(height: 20)

            // Title
            Text(LanguageManager.t("today.restDay"))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: textWidth, alignment: .leading)

            Spacer().frame(height: 12)

            // Motivational Recovery Quote
            Text(LanguageManager.restMotivationQuote(for: todayIndex))
                .font(.system(size: bodySize, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: textWidth, alignment: .leading)

            Spacer().frame(height: 16)

            // Guidance Note
            Text(LanguageManager.t("today.restDescription"))
                .font(.system(size: captionSize, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: textWidth, alignment: .leading)

            Spacer()
        }
        .padding(EdgeInsets(top: 22, leading: 19, bottom: 20, trailing: 19))
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
        .background {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1)
                    )

                let isDark = themeManager.currentTheme.isDark
                if isDark {
                    // Restore the studio beneath the cutout so the existing surface-to-studio gradient stays visible.
                    AppColors.recoveryStudioBackdrop
                } else {
                    lightBackdrop
                }

                GeometryReader { geo in
                    restPhoto(size: geo.size)
                }
                .opacity(!isDark && dynamicTypeSize >= .xxxLarge ? 0.02 : 1)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                // Dark suites keep their diagonal text-contrast scrim over the shared athlete cutout.
                if isDark {
                    LinearGradient(stops: recoveryScrim, startPoint: .topLeading, endPoint: Self.scrimEnd)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: Color.clear, location: 0.70),
                        .init(color: cardSurface.opacity(0.60), location: 0.84),
                        .init(color: cardSurface.opacity(0.95), location: 0.94),
                        .init(color: cardSurface, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .padding(.horizontal, 20)
    }
}

extension TodayHeroCard {
    /// Every theme uses the detailed transparent joggers cutout with the same crop and placement.
    @ViewBuilder
    fileprivate func restPhoto(size: CGSize) -> some View {
        // Keep the athlete toward the right edge in every suite, matching Android's recovery card.
        Image("library_body_rest").resizable().scaledToFill()
            .frame(width: size.width, height: size.height, alignment: .topTrailing).clipped()
            .offset(x: size.width * 0.10)
    }
}

private struct TodayHeroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
