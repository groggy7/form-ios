import SwiftUI

public struct ProgressionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(LanguageManager.t("progression.info.title"))
                    .font(.headline)
                    .foregroundColor(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.close"))
                .accessibilityIdentifier("progression-info-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    actionsSection
                    plateauSection
                    tipSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Text(LanguageManager.t("progression.info.ddpTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(LanguageManager.t("progression.info.ddpText"))
                .font(.footnote)
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LanguageManager.t("progression.info.rules"))
                .font(.headline)
                .foregroundColor(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                actionRow(
                    action: .increaseLoad,
                    desc: LanguageManager.t("progression.info.rule_load")
                )
                actionRow(
                    action: .addReps,
                    desc: LanguageManager.t("progression.info.rule_reps")
                )
                actionRow(
                    action: .holdLoad,
                    desc: LanguageManager.t("progression.info.rule_hold")
                )
                actionRow(
                    action: .deload,
                    desc: LanguageManager.t("progression.info.rule_review")
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.progressionRulesSurface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private func actionRow(action: ProgressionAction, desc: String) -> some View {
        let colors = ruleColors(action)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: ruleIcon(action))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(colors.accent)
                .frame(width: 44, height: 44)
                .background(colors.iconSurface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.accent.opacity(0.24), lineWidth: 1))
                .cornerRadius(12)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(LanguageManager.t(action.titleKey).uppercased(with: Locale(identifier: LanguageManager.shared.currentLanguage)))
                    .font(.footnote.weight(.bold))
                    .foregroundColor(colors.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(desc)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.accent.opacity(0.22), lineWidth: 1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
    }

    private func ruleColors(_ action: ProgressionAction) -> AppColors.ProgressionRuleColors {
        switch action {
        case .increaseLoad: return AppColors.progressionRuleLoad
        case .addReps: return AppColors.progressionRuleReps
        case .holdLoad: return AppColors.progressionRuleHold
        default: return AppColors.progressionRuleReview
        }
    }

    private func ruleIcon(_ action: ProgressionAction) -> String {
        switch action {
        case .increaseLoad: return "chart.bar.fill"
        case .addReps: return "dumbbell.fill"
        case .holdLoad: return "target"
        default: return "doc.text.fill"
        }
    }

    private var plateauSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.purple)
                Text(LanguageManager.t("progression.info.plateauTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(LanguageManager.t("progression.info.plateauText"))
                .font(.footnote)
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Text(LanguageManager.t("progression.info.tipTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(LanguageManager.t("progression.info.tipText"))
                .font(.footnote)
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.accent.opacity(0.35), lineWidth: 1))
        .cornerRadius(16)
    }
}
