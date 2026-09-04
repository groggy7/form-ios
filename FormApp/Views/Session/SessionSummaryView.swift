import SwiftUI

public struct SessionSummaryView: View {
    let workoutTitle: String
    let durationSeconds: Int
    let totalCompletedSets: Int
    let totalVolumeKg: Double
    let exerciseLogs: [SessionExerciseLog]
    var onBack: () -> Void
    var onSaveAndClose: () -> Void

    public init(
        workoutTitle: String,
        durationSeconds: Int,
        totalCompletedSets: Int,
        totalVolumeKg: Double,
        exerciseLogs: [SessionExerciseLog],
        onBack: @escaping () -> Void,
        onSaveAndClose: @escaping () -> Void
    ) {
        self.workoutTitle = workoutTitle
        self.durationSeconds = durationSeconds
        self.totalCompletedSets = totalCompletedSets
        self.totalVolumeKg = totalVolumeKg
        self.exerciseLogs = exerciseLogs
        self.onBack = onBack
        self.onSaveAndClose = onSaveAndClose
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(workoutTitle)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppColors.text)
                            Text(LanguageManager.t("summary.badge"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                        }

                        // Metrics Row
                        HStack(spacing: 8) {
                            summaryMetric(
                                title: LanguageManager.t("summary.totalDuration"),
                                value: RestTimerUtils.formatSecondsToTime(durationSeconds)
                            )
                            summaryMetric(
                                title: LanguageManager.t("summary.setsCompleted"),
                                value: "\(totalCompletedSets)"
                            )
                            summaryMetric(
                                title: LanguageManager.t("summary.estimatedVolume"),
                                value: "\(Int(totalVolumeKg)) kg"
                            )
                        }

                        // Exercise Recap
                        VStack(alignment: .leading, spacing: 14) {
                            Text(LanguageManager.t("summary.exerciseRecap"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)

                            ForEach(exerciseLogs, id: \.exerciseName) { log in
                                HStack(spacing: 14) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(log.sets.isEmpty ? AppColors.muted.opacity(0.35) : AppColors.accent)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(log.exerciseName)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(AppColors.text)

                                        Text(LanguageManager.t("summary.setsDone", ["count": log.sets.count]))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
                    .padding(20)
                }

                // Pinned Bottom Actions
                VStack(spacing: 8) {
                    Button(action: onSaveAndClose) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                            Text(LanguageManager.t("summary.saveAndClose"))
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppColors.accent)
                        )
                        .foregroundColor(AppColors.todaySelectionText)
                    }
                    .buttonStyle(.plain)

                    Button(action: onBack) {
                        Text(LanguageManager.t("summary.back"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .padding(.top, 8)
                .background(AppColors.background)
            }
            .background(AppColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.muted)
                    }
                }
            }
        }
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.muted)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}
