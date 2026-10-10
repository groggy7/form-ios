import SwiftUI

public struct SessionSummaryView: View {
    let workoutTitle: String
    let durationSeconds: Int
    let totalCompletedSets: Int
    let totalVolumeKg: Double
    let exerciseLogs: [SessionExerciseLog]
    var onBack: () -> Void
    var onSaveAndClose: () -> Void
    var onDiscard: (() -> Void)? = nil
    var onSelectExercise: ((Int) -> Void)? = nil
    var weightUnit: WeightUnit = .kg

    public init(
        workoutTitle: String,
        durationSeconds: Int,
        totalCompletedSets: Int,
        totalVolumeKg: Double,
        exerciseLogs: [SessionExerciseLog],
        onBack: @escaping () -> Void,
        onSaveAndClose: @escaping () -> Void,
        onDiscard: (() -> Void)? = nil,
        onSelectExercise: ((Int) -> Void)? = nil,
        weightUnit: WeightUnit = .kg
    ) {
        self.workoutTitle = workoutTitle
        self.durationSeconds = durationSeconds
        self.totalCompletedSets = totalCompletedSets
        self.totalVolumeKg = totalVolumeKg
        self.exerciseLogs = exerciseLogs
        self.onBack = onBack
        self.onSaveAndClose = onSaveAndClose
        self.onDiscard = onDiscard
        self.onSelectExercise = onSelectExercise
        self.weightUnit = weightUnit
    }

    private var totalExercises: Int { exerciseLogs.count }
    private var completedExercisesCount: Int {
        exerciseLogs.filter { log in
            let working = log.sets.filter { !$0.isWarmup }
            let target = (log.targetSets ?? 0) > 0 ? (log.targetSets ?? 0) : max(working.count, 1)
            return working.count >= target && target > 0
        }.count
    }
    private var isWorkoutEmpty: Bool { totalCompletedSets == 0 }
    private var isWorkoutComplete: Bool { !isWorkoutEmpty && totalExercises > 0 && completedExercisesCount == totalExercises }
    private var isWorkoutPartial: Bool { !isWorkoutEmpty && !isWorkoutComplete }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isWorkoutEmpty {
                    // Empty State: Body stretched with centered card
                    VStack(alignment: .leading, spacing: 16) {
                        Text(workoutTitle)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppColors.text)

                        // Unified Segmented KPI Metrics Card
                        summaryMetricsCard

                        Text(LanguageManager.t("summary.exerciseRecap"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)

                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.accent.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle()
                                            .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                                    )
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 34))
                                    .foregroundColor(AppColors.accent)
                            }

                            VStack(spacing: 6) {
                                Text(LanguageManager.t("summary.noSetsTitle"))
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .multilineTextAlignment(.center)

                                Text(LanguageManager.t("summary.noSetsSubtitle"))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.muted)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                        .background(AppColors.surface)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                    .padding(20)
                } else {
                    // Non-Empty State: Scrollable Body
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(workoutTitle)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(AppColors.text)

                            // Unified Segmented KPI Metrics Card
                            summaryMetricsCard

                            // Status Banners
                            if isWorkoutComplete {
                                HStack(spacing: 12) {
                                    Text("🎉")
                                        .font(.system(size: 24))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("summary.completeBannerTitle", ["count": totalExercises]))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Text(LanguageManager.t("summary.completeBannerSubtitle"))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(Color(hex: 0x14241D))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.completedGreen.opacity(0.35), lineWidth: 1)
                                )
                            } else if isWorkoutPartial {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(AppColors.unfinishedOrange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("summary.partialBannerTitle", ["completed": completedExercisesCount, "total": totalExercises]))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Text(LanguageManager.t("summary.partialBannerSubtitle"))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(Color(hex: 0x261D13))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.unfinishedOrange.opacity(0.35), lineWidth: 1)
                                )
                            }

                            // Exercise Recap Section
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LanguageManager.t("summary.exerciseRecap"))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.secondaryText)

                                ForEach(Array(exerciseLogs.enumerated()), id: \.offset) { index, log in
                                    let working = log.sets.filter { !$0.isWarmup }
                                    let completedCount = working.count
                                    let targetCount = (log.targetSets ?? 0) > 0 ? (log.targetSets ?? 0) : max(working.count, 1)
                                    let isDone = completedCount >= targetCount && targetCount > 0
                                    let isHalfway = completedCount > 0 && !isDone
                                    let isUnstarted = completedCount == 0
                                    let exerciseVolumeKg = working.reduce(0.0) { sum, set in sum + ((set.weightKg ?? 0.0) * Double(set.reps ?? 0)) }

                                    Button(action: {
                                        onSelectExercise?(index)
                                    }) {
                                        HStack(spacing: 12) {
                                            if isDone {
                                                Circle()
                                                    .fill(AppColors.accent)
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 13, weight: .bold))
                                                            .foregroundColor(AppColors.todaySelectionText)
                                                    )
                                            } else if isHalfway {
                                                Circle()
                                                    .fill(AppColors.unfinishedOrange.opacity(0.15))
                                                    .overlay(
                                                        Circle().stroke(AppColors.unfinishedOrange, lineWidth: 1.5)
                                                    )
                                                    .frame(width: 28, height: 28)
                                                    .overlay(
                                                        Image(systemName: "clock.fill")
                                                            .font(.system(size: 12))
                                                            .foregroundColor(AppColors.unfinishedOrange)
                                                    )
                                            } else {
                                                Circle()
                                                    .stroke(AppColors.muted.opacity(0.4), lineWidth: 1.5)
                                                    .frame(width: 28, height: 28)
                                            }

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(log.exerciseName)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(AppColors.text)

                                                let subtitleText: String = {
                                                    if isUnstarted {
                                                        return "0/\(targetCount) sets • \(LanguageManager.t("history.notStarted"))"
                                                    } else if exerciseVolumeKg <= 0.0 {
                                                        return "\(completedCount)/\(targetCount) sets • \(LanguageManager.t("exercise.history.bodyweight"))"
                                                    } else {
                                                        return "\(completedCount)/\(targetCount) sets • \(weightUnit.formatVolume(exerciseVolumeKg)) \(weightUnit.label)"
                                                    }
                                                }()

                                                Text(subtitleText)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AppColors.muted)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(AppColors.muted.opacity(0.6))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .background(AppColors.surface)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(20)
                    }
                }

                // Pinned Bottom Actions (Always stretched to the bottom across all states)
                VStack(spacing: 8) {
                    if isWorkoutEmpty {
                        Button(action: onBack) {
                            Text(LanguageManager.t("summary.continueWorkout"))
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.accent)
                                )
                                .foregroundColor(AppColors.todaySelectionText)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            if let onDiscard = onDiscard {
                                onDiscard()
                            } else {
                                onBack()
                            }
                        }) {
                            Text(LanguageManager.t("summary.exitSession"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
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
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.backward")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.text)
                            Text(LanguageManager.t("summary.badge"))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AppColors.text)
                        }
                    }
                }
            }
        }
    }

    private var summaryMetricsCard: some View {
        HStack(spacing: 0) {
            summaryMetricColumn(
                icon: "clock",
                value: RestTimerUtils.formatSecondsToTime(durationSeconds),
                title: LanguageManager.t("summary.totalDuration")
            )

            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: 44)

            summaryMetricColumn(
                icon: "dumbbell.fill",
                value: "\(totalCompletedSets)",
                title: LanguageManager.t("summary.setsCompleted")
            )

            Rectangle()
                .fill(AppColors.border)
                .frame(width: 1, height: 44)

            summaryMetricColumn(
                icon: "square.stack.3d.up",
                value: "\(weightUnit.formatVolume(totalVolumeKg)) \(weightUnit.label)",
                title: LanguageManager.t("summary.estimatedVolume")
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func summaryMetricColumn(icon: String, value: String, title: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.muted)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppColors.text)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.muted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}
