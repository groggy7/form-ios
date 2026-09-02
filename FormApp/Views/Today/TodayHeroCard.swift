import SwiftUI

public struct TodayHeroCard: View {
    let workout: Workout?
    let isToday: Bool
    let isCompleted: Bool
    let isAvailable: Bool
    let onStart: () -> Void

    public init(
        workout: Workout?,
        isToday: Bool,
        isCompleted: Bool,
        isAvailable: Bool,
        onStart: @escaping () -> Void
    ) {
        self.workout = workout
        self.isToday = isToday
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
                    Text(isCompleted ? LanguageManager.t("today.completed") : LanguageManager.t("today.startWorkout"))
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    private func restDayCard() -> some View {
        VStack(spacing: 14) {
            Image("body_rest")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(LanguageManager.t("today.restTitle"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t("today.restSubtitle"))
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
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
