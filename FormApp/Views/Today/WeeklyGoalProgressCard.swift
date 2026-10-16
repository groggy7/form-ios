import SwiftUI

private var cardBackground: Color { AppColors.heroSurface }
private var cardBorder: Color { AppColors.heroBorder }
private var segmentActive: Color { AppColors.goalSegmentActive }
private var segmentBlinkingTarget: Color { AppColors.goalSegmentPending }
private var segmentTrack: Color { AppColors.surface }
private var statBoxBg: Color { AppColors.surface }
private var statBoxBorder: Color { AppColors.border }
private var amberPr: Color { AppColors.lightThemeColor(Color(hex: 0xFBBF24), AppColors.warmupAmber) }

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
    @ObservedObject var themeManager = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let metrics: WeeklyGoalProgressMetrics
    public let isCurrentWorkoutPending: Bool
    public var weightUnit: WeightUnit = .kg
    public var isPageVisible: Bool = true
    @State private var isVisible = false

    public init(metrics: WeeklyGoalProgressMetrics, isCurrentWorkoutPending: Bool = true, weightUnit: WeightUnit = .kg, isPageVisible: Bool = true) {
        self.metrics = metrics
        self.isCurrentWorkoutPending = isCurrentWorkoutPending
        self.weightUnit = weightUnit
        self.isPageVisible = isPageVisible
    }

    private var shouldBlink: Bool {
        isVisible && isPageVisible && scenePhase == .active && !reduceMotion &&
            metrics.totalWorkouts > 0 && metrics.completedWorkouts < metrics.totalWorkouts
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        VStack(spacing: 14) {
            // Header: "Weekly Goal Progress" and "X / Y Completed"
            HStack(alignment: .center) {
                Text(LanguageManager.t("today.weeklyGoalProgress"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.text)

                Spacer()

                HStack(spacing: 4) {
                    Text("\(metrics.completedWorkouts) / \(metrics.totalWorkouts)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(segmentActive)

                    Text(LanguageManager.t("today.completed"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            // Segmented Progress Bar
            WeeklyGoalSegments(
                completedWorkouts: metrics.completedWorkouts,
                totalWorkouts: metrics.totalWorkouts,
                animate: shouldBlink,
                track: segmentTrack,
                completed: segmentActive,
                pending: segmentBlinkingTarget
            )
            .accessibilityIdentifier("weekly-goal-progress-segments")
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }

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
                        .foregroundStyle(AppColors.muted)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(metrics.formattedVolume(unit: weightUnit))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.text)

                        Text(weightUnit.label)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.muted)
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
                        .foregroundStyle(AppColors.muted)

                    Text(metrics.formattedActiveTime)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.text)
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
                        .foregroundStyle(AppColors.muted)

                    HStack(alignment: .center, spacing: 4) {
                        Text("⚡")
                            .font(.system(size: 13))
                            .foregroundStyle(amberPr)

                        Text("\(metrics.prsHitCount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(amberPr)
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

// Draw one coherent progress snapshot. A repeatForever transaction on the row
// can retain old per-capsule color animations after progress or palette changes.
struct WeeklyGoalSegments: View {
    let completedWorkouts: Int
    let totalWorkouts: Int
    let animate: Bool
    let track: Color
    let completed: Color
    let pending: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.5)
            let fraction = animate ? (1 - cos(phase * .pi / 1.25)) / 2 : 1
            let pendingColor = Color.mix(track, pending, fraction)
            Canvas { context, size in
                let count = max(totalWorkouts, 1)
                let gap: CGFloat = 6
                let width = max(0, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                for index in 0..<count {
                    let color: Color
                    if totalWorkouts > 0 && index < completedWorkouts {
                        color = completed
                    } else if isWeeklyGoalPillBlinking(pillIndex: index, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts) {
                        color = pendingColor
                    } else {
                        color = track
                    }
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: 0, width: width, height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: size.height / 2), with: .color(color))
                }
            }
        }
        .frame(height: 8)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}
