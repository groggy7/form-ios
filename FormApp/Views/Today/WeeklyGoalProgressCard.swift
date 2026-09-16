import SwiftUI

private let cardBackground = Color(hex: 0x1E242B)
private let cardBorder = Color(hex: 0x303B46)
private let segmentActive = Color(hex: 0x21E498)
private let segmentBlinkingTarget = Color(hex: 0x1E946A)
private let segmentTrack = Color(hex: 0x13171B)
private let statBoxBg = AppColors.surface
private let statBoxBorder = AppColors.border
private let amberPr = Color(hex: 0xFBBF24)

public func isWeeklyGoalPillBlinking(
    pillIndex: Int,
    totalWorkouts: Int,
    completedWorkouts: Int,
    isCurrentWorkoutPending: Bool = true
) -> Bool {
    totalWorkouts > 0 &&
        completedWorkouts < totalWorkouts &&
        pillIndex == completedWorkouts
}

public struct WeeklyGoalProgressCard: View {
    public let metrics: WeeklyGoalProgressMetrics
    public let isCurrentWorkoutPending: Bool
    @State private var isBlinking: Bool = false

    public init(metrics: WeeklyGoalProgressMetrics, isCurrentWorkoutPending: Bool = true) {
        self.metrics = metrics
        self.isCurrentWorkoutPending = isCurrentWorkoutPending
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Header: "Weekly Goal Progress" and "X / Y Completed"
            HStack(alignment: .center) {
                Text(LanguageManager.t("today.weeklyGoalProgress"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)

                Spacer()

                HStack(spacing: 4) {
                    Text("\(metrics.completedWorkouts) / \(metrics.totalWorkouts)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(segmentActive)

                    Text(LanguageManager.t("today.completed"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            // Segmented Progress Bar
            let totalSegments = max(metrics.totalWorkouts, 1)
            HStack(spacing: 6) {
                ForEach(0..<totalSegments, id: \.self) { i in
                    let isCompleted = metrics.totalWorkouts > 0 && i < metrics.completedWorkouts
                    let isBlinkingPill = isWeeklyGoalPillBlinking(
                        pillIndex: i,
                        totalWorkouts: metrics.totalWorkouts,
                        completedWorkouts: metrics.completedWorkouts,
                        isCurrentWorkoutPending: isCurrentWorkoutPending
                    )

                    let segmentColor: Color = {
                        if isCompleted {
                            return segmentActive
                        } else if isBlinkingPill {
                            return isBlinking ? segmentBlinkingTarget : segmentTrack
                        } else {
                            return segmentTrack
                        }
                    }()

                    Capsule()
                        .fill(segmentColor)
                        .frame(height: 8)
                }
            }
            .accessibilityIdentifier("weekly-goal-progress-segments")
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.25)
                    .repeatForever(autoreverses: true)
                ) {
                    isBlinking = true
                }
            }

            // Subtle Divider
            Rectangle()
                .fill(cardBorder)
                .frame(height: 1)

            // 3 Stat Boxes Row (TOTAL VOLUME, ACTIVE TIME, PRS HIT)
            HStack(spacing: 8) {
                // Stat 1: Total Volume
                VStack(spacing: 4) {
                    Text(LanguageManager.t("today.totalVolume"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.muted)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(metrics.formattedVolume)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.text)

                        Text("kg")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(AppColors.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .background(statBoxBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(statBoxBorder, lineWidth: 1)
                )
                .accessibilityIdentifier("weekly-progress-volume")

                // Stat 2: Active Time
                VStack(spacing: 4) {
                    Text(LanguageManager.t("today.activeTime"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.muted)

                    Text(metrics.formattedActiveTime)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .background(statBoxBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(statBoxBorder, lineWidth: 1)
                )
                .accessibilityIdentifier("weekly-progress-active-time")

                // Stat 3: PRs Hit
                VStack(spacing: 4) {
                    Text(LanguageManager.t("today.prsHit"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppColors.muted)

                    HStack(alignment: .center, spacing: 4) {
                        Text("⚡")
                            .font(.system(size: 13))
                            .foregroundColor(amberPr)

                        Text("\(metrics.prsHitCount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(amberPr)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
                .background(statBoxBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(statBoxBorder, lineWidth: 1)
                )
                .accessibilityIdentifier("weekly-progress-prs")
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("weekly-goal-progress-card")
    }
}
