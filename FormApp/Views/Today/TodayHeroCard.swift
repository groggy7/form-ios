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

    private let cardSurface = Color(hex: 0x15191E)
    private let cardBorder = Color(hex: 0x343A41)

    public init(
        workout: Workout?,
        todayIndex: Int,
        isCompleted: Bool,
        isAvailable: Bool,
        availableDay: String? = nil,
        hasUnfinishedProgress: Bool = false,
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
        let views = availableBodyViews(for: workout)
        let activeViewName = views.indices.contains(selectedViewIndex) ? views[selectedViewIndex].imageName : "body_front"

        return ZStack(alignment: .topLeading) {
            // Container background
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                )

            // Right-aligned anatomy image
            HStack {
                Spacer()
                Image(activeViewName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 185, height: 280)
                    .offset(x: 10, y: -5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            // Horizontal Gradient scrim
            LinearGradient(
                stops: [
                    .init(color: cardSurface, location: 0),
                    .init(color: cardSurface, location: 0.32),
                    .init(color: cardSurface.opacity(0.92), location: 0.52),
                    .init(color: cardSurface.opacity(0.15), location: 0.74),
                    .init(color: Color.clear, location: 0.95)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            // Vertical Gradient scrim
            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0),
                    .init(color: Color.clear, location: 0.35),
                    .init(color: cardSurface.opacity(0.30), location: 0.55),
                    .init(color: cardSurface.opacity(0.96), location: 0.82),
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
                if views.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(views.enumerated()), id: \.offset) { idx, v in
                            let isSel = idx == selectedViewIndex
                            Button(action: { selectedViewIndex = idx }) {
                                Text(v.label)
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

    private struct BodyViewOption {
        let label: String
        let imageName: String
    }

    private func availableBodyViews(for workout: Workout) -> [BodyViewOption] {
        var options: [BodyViewOption] = []
        let muscles = workout.resolvedMuscles

        let hasBack = muscles.contains { $0.views.contains(.back) }
        let hasFront = muscles.contains { $0.views.contains(.front) }
        let hasLegsFront = muscles.contains { $0.views.contains(.legsFront) }
        let hasLegsBack = muscles.contains { $0.views.contains(.legsBack) }

        if hasBack {
            options.append(BodyViewOption(label: LanguageManager.t("muscles.view.back"), imageName: "body_back"))
        }
        if hasFront {
            options.append(BodyViewOption(label: LanguageManager.t("muscles.view.front"), imageName: "body_front"))
        }
        if hasLegsFront {
            options.append(BodyViewOption(label: LanguageManager.t("muscles.view.legs-front"), imageName: "body_legs_front"))
        }
        if hasLegsBack {
            options.append(BodyViewOption(label: LanguageManager.t("muscles.view.legs-back"), imageName: "body_legs_back"))
        }

        if options.isEmpty {
            switch workout.visualRegion {
            case .upper:
                options.append(BodyViewOption(label: LanguageManager.t("muscles.view.back"), imageName: "body_back"))
            case .lower:
                options.append(BodyViewOption(label: LanguageManager.t("muscles.view.legs-front"), imageName: "body_legs_front"))
            case .fullBody:
                options.append(BodyViewOption(label: LanguageManager.t("muscles.view.front"), imageName: "body_front"))
            }
        }

        return options
    }
}
