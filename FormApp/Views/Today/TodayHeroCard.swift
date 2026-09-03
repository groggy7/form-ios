import SwiftUI

public struct TodayHeroCard: View {
    let workout: Workout?
    let todayIndex: Int
    let isCompleted: Bool
    let isAvailable: Bool
    let availableDay: String?
    let hasUnfinishedProgress: Bool
    let onStart: () -> Void

    @State private var selectedViewIndex: Int = 0

    private let cardSurface = Color(hex: 0x1E242B)
    private let cardBorder = Color(hex: 0x303B46)

    public init(
        workout: Workout?,
        todayIndex: Int,
        isCompleted: Bool,
        isAvailable: Bool,
        availableDay: String?,
        hasUnfinishedProgress: Bool,
        onStart: @escaping () -> Void
    ) {
        self.workout = workout
        self.todayIndex = todayIndex
        self.isCompleted = isCompleted
        self.isAvailable = isAvailable
        self.availableDay = availableDay
        self.hasUnfinishedProgress = hasUnfinishedProgress
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
        let bodyViews = workout.bodyViews()
        let activeView = bodyViews.indices.contains(selectedViewIndex) ? bodyViews[selectedViewIndex] : (bodyViews.first ?? .front)

        return ZStack(alignment: .topLeading) {
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

            // Content Column
            VStack(alignment: .leading, spacing: 0) {
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0xD3D0C7))

                    Spacer()

                    if isCompleted {
                        ZStack {
                            Circle()
                                .fill(cardSurface)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
                .frame(minHeight: 20)

                Spacer().frame(height: 18)

                // Title
                Text(workout.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Color(hex: 0xF3EFE5))
                    .lineLimit(2)
                    .frame(maxWidth: 220, alignment: .leading)

                Spacer().frame(height: 8)

                // Focus
                if !workout.focus.isEmpty {
                    Text(LanguageManager.content(workout.focus))
                        .font(.system(size: 13, weight: .regular))
                        .lineSpacing(2)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)
                        .frame(maxWidth: 215, alignment: .leading)
                }

                Spacer().frame(height: 12)

                // Body view switcher chips (if more than 1)
                if bodyViews.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(bodyViews.enumerated()), id: \.offset) { idx, v in
                            let isSel = idx == selectedViewIndex
                            Button(action: { selectedViewIndex = idx }) {
                                Text(LanguageManager.t("muscles.view.\(v.rawValue)"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isSel ? Color(hex: 0xE3DAF1) : AppColors.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSel ? Color(hex: 0x343044) : cardSurface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSel ? Color(hex: 0x494260) : cardBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer().frame(height: 10)
                }

                // Meta
                let mins = max(25, workout.exercises.count * 8)
                let meta = LanguageManager.t("today.workoutMeta", [
                    "exercises": workout.exercises.count,
                    "minutes": mins
                ])
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: 0xB1BAC2))

                Spacer().frame(height: 16)

                // Button
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: isCompleted ? "checkmark" : (availableDay != nil ? "clock" : "play.fill"))
                            .font(.system(size: 15, weight: .semibold))

                        Text(buttonTitle())
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill((isAvailable && !isCompleted) ? AppColors.accent : AppColors.surfaceRaised)
                    )
                    .foregroundColor((isAvailable && !isCompleted) ? AppColors.background : (isCompleted ? AppColors.accent : AppColors.muted))
                }
                .disabled(!isAvailable || isCompleted)
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 20, leading: 19, bottom: 19, trailing: 19))
        }
        .padding(.horizontal, 20)
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

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )

            HStack {
                Spacer()
                Image("body_rest")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 185, height: 260)
                    .offset(x: 10, y: -5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            LinearGradient(
                stops: [
                    .init(color: cardSurface, location: 0),
                    .init(color: cardSurface, location: 0.35),
                    .init(color: cardSurface.opacity(0.85), location: 0.55),
                    .init(color: Color.clear, location: 0.85)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0),
                    .init(color: Color.clear, location: 0.35),
                    .init(color: cardSurface.opacity(0.35), location: 0.55),
                    .init(color: cardSurface.opacity(0.95), location: 0.80),
                    .init(color: cardSurface, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: 0xD3D0C7))

                Spacer().frame(height: 18)

                Text(LanguageManager.t("today.restDay"))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(Color(hex: 0xF3EFE5))
                    .lineLimit(2)

                Spacer().frame(height: 9)

                Text(LanguageManager.t("today.restDescription"))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: 210, alignment: .leading)
            }
            .padding(22)
        }
        .frame(minHeight: 250)
        .padding(.horizontal, 20)
    }
}
