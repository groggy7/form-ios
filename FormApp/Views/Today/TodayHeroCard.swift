import SwiftUI

public struct TodayHeroCard: View {
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
    private var textWidth: CGFloat? { dynamicTypeSize >= .xxxLarge ? nil : 215 }

    private let cardSurface = Color(hex: 0x1E242B)
    private let cardBorder = Color(hex: 0x303B46)
    private let selectedViewSurface = Color(hex: 0x25232D)
    private let selectedViewBorder = Color(hex: 0x51455F)
    private let selectedViewText = Color(hex: 0xD8CFDF)

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
                    .foregroundStyle(Color(hex: 0xD3D0C7))

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
                .foregroundStyle(Color(hex: 0xF3EFE5))
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
                .foregroundStyle(Color(hex: 0xB1BAC2))
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
                        .fill((isAvailable && !isCompleted) ? AppColors.accent : Color(hex: 0x14171A))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(
                            (isAvailable && !isCompleted)
                                ? Color.clear
                                : (isCompleted ? AppColors.accent.opacity(0.4) : Color(hex: 0x38404A)),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    (isAvailable && !isCompleted)
                        ? AppColors.background
                        : (isCompleted ? AppColors.accent : Color(hex: 0xB1BAC2))
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

                // Muscle artwork underlay
                MuscleArtwork(view: activeView, muscles: workout.resolvedMuscles)
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                // Horizontal Gradient scrim (matching Android 1-to-1)
                LinearGradient(
                    stops: [
                        .init(color: cardSurface, location: 0),
                        .init(color: cardSurface.opacity(0.94), location: 0.25),
                        .init(color: cardSurface.opacity(0.50), location: 0.51),
                        .init(color: cardSurface.opacity(0.03), location: 0.76),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                // Vertical Gradient scrim (matching Android 1-to-1)
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0),
                        .init(color: Color.clear, location: 0.20),
                        .init(color: cardSurface.opacity(0.12), location: 0.44),
                        .init(color: cardSurface.opacity(0.96), location: 0.83),
                        .init(color: cardSurface, location: 0.96),
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
                .foregroundStyle(Color(hex: 0xD3D0C7))
                .frame(minHeight: 20)

            Spacer().frame(height: 20)

            // Title
            Text(LanguageManager.t("today.restDay"))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(Color(hex: 0xF3EFE5))
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
                .foregroundStyle(Color(hex: 0x9AA4AC))
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

                GeometryReader { geo in
                    Image("body_rest")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

                LinearGradient(
                    stops: [
                        .init(color: cardSurface, location: 0),
                        .init(color: cardSurface.opacity(0.95), location: 0.26),
                        .init(color: cardSurface.opacity(0.50), location: 0.48),
                        .init(color: cardSurface.opacity(0.04), location: 0.64),
                        .init(color: Color.clear, location: 0.74),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

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

private struct TodayHeroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
