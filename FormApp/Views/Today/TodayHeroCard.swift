import SwiftUI

public struct TodayHeroCard: View {
    let workout: Workout?
    let todayIndex: Int
    let isCompleted: Bool
    let isAvailable: Bool
    let onStart: () -> Void

    public init(
        workout: Workout?,
        todayIndex: Int,
        isCompleted: Bool,
        isAvailable: Bool,
        onStart: @escaping () -> Void
    ) {
        self.workout = workout
        self.todayIndex = todayIndex
        self.isCompleted = isCompleted
        self.isAvailable = isAvailable
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
        VStack(alignment: .leading, spacing: 16) {
            // Artwork / Header preview
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .frame(height: 160)
                    .overlay(
                        bodyViewArtwork(for: workout)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    )

                if isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.positive)
                        Text(LanguageManager.t("today.completed"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppColors.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.surface.opacity(0.85))
                    .cornerRadius(12)
                    .padding(12)
                }
            }

            // Workout info
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppColors.text)

                let mins = max(25, workout.exercises.count * 8)
                let meta = LanguageManager.t("today.workoutMeta", [
                    "exercises": workout.exercises.count,
                    "minutes": mins
                ])
                Text(meta)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.muted)
            }

            // Start Button
            Button(action: onStart) {
                HStack(spacing: 8) {
                    Image(systemName: isCompleted ? "checkmark" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(isCompleted ? LanguageManager.t("today.completed") : LanguageManager.t("plan.startWorkout"))
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isAvailable && !isCompleted ? AppColors.accent : AppColors.surfaceRaised)
                )
                .foregroundColor(isAvailable && !isCompleted ? AppColors.todaySelectionText : AppColors.muted)
            }
            .disabled(!isAvailable || isCompleted)
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    private func restDayCard() -> some View {
        let weekdayName = LanguageManager.workoutDays.indices.contains(todayIndex)
            ? LanguageManager.workoutDays[todayIndex]
            : ""

        return ZStack(alignment: .topLeading) {
            // Background card container
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(Color(hex: 0x15191E))
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(Color(hex: 0x343A41), lineWidth: 1)
                )

            // Right-aligned rest image
            HStack {
                Spacer()
                Image("body_rest")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 240)
                    .clipped()
            }

            // Gradient masks over the image
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x15191E), location: 0),
                    .init(color: Color(hex: 0x15191E).opacity(0.95), location: 0.28),
                    .init(color: Color(hex: 0x15191E).opacity(0.50), location: 0.52),
                    .init(color: Color.clear, location: 0.75)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0),
                    .init(color: Color.clear, location: 0.70),
                    .init(color: Color(hex: 0x15191E).opacity(0.95), location: 0.94),
                    .init(color: Color(hex: 0x15191E), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            // Text info
            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: 0xD3D0C7))

                Spacer().frame(height: 18)

                Text(LanguageManager.t("today.restDay"))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Color(hex: 0xF3EFE5))
                    .lineLimit(2)

                Spacer().frame(height: 9)

                Text(LanguageManager.t("today.restDescription"))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(22)
        }
        .frame(height: 270)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func bodyViewArtwork(for workout: Workout) -> some View {
        let firstMuscle = workout.resolvedMuscles.first
        let viewName: String = {
            if let v = firstMuscle?.views.first {
                switch v {
                case .back: return "body_back"
                case .front: return "body_front"
                case .legsFront: return "body_legs_front"
                case .legsBack: return "body_legs_back"
                }
            }
            return "body_front"
        }()

        Image(viewName)
            .resizable()
            .scaledToFit()
            .opacity(0.8)
    }
}
