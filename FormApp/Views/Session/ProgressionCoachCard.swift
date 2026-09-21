import SwiftUI

public struct ProgressionCoachCard: View {
    let recommendation: ExerciseProgressionRecommendation
    let onApplyTarget: () -> Void
    let onOpenInfo: () -> Void
    var onLockedClick: (() -> Void)? = nil
    var onDismissLocked: (() -> Void)? = nil

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var wasApplied: Bool = false
    @State private var showInternalPaywall: Bool = false

    public init(
        recommendation: ExerciseProgressionRecommendation,
        onApplyTarget: @escaping () -> Void,
        onOpenInfo: @escaping () -> Void,
        onLockedClick: (() -> Void)? = nil,
        onDismissLocked: (() -> Void)? = nil
    ) {
        self.recommendation = recommendation
        self.onApplyTarget = onApplyTarget
        self.onOpenInfo = onOpenInfo
        self.onLockedClick = onLockedClick
        self.onDismissLocked = onDismissLocked
    }

    public var body: some View {
        if !proManager.isFeatureUnlocked(.autoProgression) {
            HStack(spacing: 6) {
                Button(action: {
                    if let onLockedClick = onLockedClick {
                        onLockedClick()
                    } else {
                        showInternalPaywall = true
                    }
                }) {
                    HStack(spacing: 10) {
                        // Left Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.purpleBg)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.purple.opacity(0.4), lineWidth: 1)
                                )

                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.purple)
                        }

                        // Text details
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text(LanguageManager.t("pro.auto_progression.title"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Text(LanguageManager.t("pro.auto_progression.teaser"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 2)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.purple)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onDismissLocked = onDismissLocked {
                    Button(action: onDismissLocked) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dismiss-progression-card")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, onDismissLocked != nil ? 8 : 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.purple.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("progression-coach-card")
            .sheet(isPresented: $showInternalPaywall) {
                ProPaywallSheet(feature: .autoProgression, onDismiss: { showInternalPaywall = false })
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        ProBadge()

                        Text(LanguageManager.t(recommendation.action.titleKey))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(recommendation.action.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(recommendation.action.badgeBgColor)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(recommendation.action.color.opacity(0.5), lineWidth: 1))
                            .cornerRadius(6)
                    }

                    Spacer()

                    Button(action: onOpenInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.muted)
                            .padding(4)
                    }
                    .accessibilityLabel(LanguageManager.t("progression.info.title"))
                }

                // Target Headline & Action Button Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(recommendation.action.color)

                            let repStr = recommendation.suggestedRepsMin == recommendation.suggestedRepsMax
                                ? "\(recommendation.suggestedRepsMin)"
                                : "\(recommendation.suggestedRepsMin)–\(recommendation.suggestedRepsMax)"

                            let targetHeadline: String = {
                                if recommendation.suggestedWeightKg != nil {
                                    return "\(LanguageManager.t("progression.coach.target")): \(recommendation.suggestedWeightDisplay) × \(repStr)"
                                } else {
                                    return "\(LanguageManager.t("progression.coach.target")): \(repStr) reps"
                                }
                            }()

                            Text(targetHeadline)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }

                        if let delta = recommendation.weightDeltaDisplay {
                            Text(delta)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(recommendation.action.color)
                                .padding(.leading, 19)
                        }
                    }

                    Spacer()

                    if recommendation.suggestedWeightKg != nil {
                        Button(action: {
                            onApplyTarget()
                            wasApplied = true
                        }) {
                            HStack(spacing: 4) {
                                if wasApplied {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppColors.accent)
                                }
                                Text(wasApplied ? LanguageManager.t("progression.coach.applied") : LanguageManager.t("progression.coach.apply"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(wasApplied ? AppColors.accent : AppColors.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(wasApplied ? AppColors.positiveBg : AppColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(wasApplied ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1))
                            .cornerRadius(8)
                        }
                    }
                }

                // Rationale text
                let rationaleText = LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs)
                Text(rationaleText)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(14)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(recommendation.action.color.opacity(0.35), lineWidth: 1))
            .cornerRadius(16)
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenInfo()
            }
        }
    }
}
