import SwiftUI

public struct ProgressionCoachCard: View {
    let recommendation: ExerciseProgressionRecommendation
    let weightUnit: WeightUnit
    let canApplyTarget: Bool
    let onApplyTarget: () -> Void
    let onOpenInfo: () -> Void
    var onLockedClick: (() -> Void)? = nil
    var onDismissLocked: (() -> Void)? = nil

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var wasApplied: Bool = false
    @State private var showInternalPaywall: Bool = false
    @ScaledMetric(relativeTo: .subheadline) private var emptyHeaderSize = 14.0
    @ScaledMetric(relativeTo: .title2) private var emptyHeadlineSize = 22.0
    @ScaledMetric(relativeTo: .subheadline) private var emptyBodySize = 14.0

    public init(
        recommendation: ExerciseProgressionRecommendation,
        weightUnit: WeightUnit = .kg,
        canApplyTarget: Bool = true,
        onApplyTarget: @escaping () -> Void,
        onOpenInfo: @escaping () -> Void,
        onLockedClick: (() -> Void)? = nil,
        onDismissLocked: (() -> Void)? = nil
    ) {
        self.recommendation = recommendation
        self.weightUnit = weightUnit
        self.canApplyTarget = canApplyTarget
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
        } else if recommendation.action == .firstSession && recommendation.setTargets.isEmpty {
            firstSessionCard
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // Header Row
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        ProBadge()

                        Text(LanguageManager.t(recommendation.action.titleKey))
                            .font(.system(size: 11, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
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
                            .frame(minWidth: 48, minHeight: 48)
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
                                if recommendation.setTargets.isEmpty {
                                    return LanguageManager.t(recommendation.isPlateau ? "progression.coach.review" : "progression.coach.no_target")
                                } else if hasDifferentTargets {
                                    return LanguageManager.t("progression.coach.by_set")
                                } else if (recommendation.suggestedWeightKg ?? 0) > 0 {
                                    return "\(LanguageManager.t("progression.coach.target")): \(recommendation.suggestedWeightDisplay) \(weightUnit.label) × \(repStr)"
                                } else {
                                    return "\(LanguageManager.t("progression.coach.target")): \(LanguageManager.t("progression.coach.reps", ["reps": repStr]))"
                                }
                            }()

                            Text(targetHeadline)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let delta = recommendation.weightDeltaDisplay {
                            Text(delta)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(recommendation.action.color)
                                .padding(.leading, 19)
                        }
                    }

                    Spacer()

                    if !recommendation.setTargets.isEmpty {
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
                            .frame(minHeight: 48)
                            .background(wasApplied ? AppColors.positiveBg : AppColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(wasApplied ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1))
                            .cornerRadius(8)
                        }
                        .disabled(!canApplyTarget)
                        .accessibilityIdentifier("apply-progression-target")
                    }
                }

                if hasDifferentTargets {
                    ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                        let load = (target.weightKg ?? 0) > 0 ? "\(weightUnit.formatWeight(target.weightKg!)) \(weightUnit.label) × " : ""
                        Text(LanguageManager.t("progression.coach.set_target", ["set": "\(index + 1)", "target": load.isEmpty ? LanguageManager.t("progression.coach.reps", ["reps": "\(target.reps)"]) : "\(load)\(target.reps)"]))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.text)
                    }
                }
                if let summary = recommendation.lastSessionSummary {
                    Text(LanguageManager.t("progression.coach.last_logged", ["summary": summary, "unit": weightUnit.label]))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                }
                if !recommendation.setTargets.isEmpty && !canApplyTarget {
                    Text(LanguageManager.t("progression.coach.set_count_changed"))
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
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
            .onChange(of: recommendation) { _, _ in wasApplied = false }
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenInfo()
            }
        }
    }

    private var firstSessionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.purple)
                    .frame(width: 34, height: 34)
                    .background(AppColors.purpleBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.purple.opacity(0.25), lineWidth: 1))
                    .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        firstSessionHeader
                        ProBadge()
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) {
                        firstSessionHeader
                        ProBadge()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onOpenInfo) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.muted)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("progression.info.title"))
            }
            .padding(.bottom, 14)

            Text(LanguageManager.t("progression.coach.no_target"))
                .font(.system(size: emptyHeadlineSize, weight: .bold))
                .foregroundColor(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(LanguageManager.t("progression.coach.first_session_hint"))
                .font(.system(size: emptyBodySize))
                .lineSpacing(3)
                .foregroundColor(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenInfo)
        .accessibilityIdentifier("progression-coach-card")
    }

    private var firstSessionHeader: some View {
        Text(LanguageManager.t("progression.coach.next_target"))
            .font(.system(size: emptyHeaderSize, weight: .semibold))
            .foregroundColor(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hasDifferentTargets: Bool {
        guard let first = recommendation.setTargets.first else { return false }
        return recommendation.setTargets.contains { $0 != first }
    }
}
