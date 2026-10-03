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
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.text)

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
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private func actionRow(action: ProgressionAction, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LanguageManager.t(action.titleKey))
                .font(.caption2.weight(.bold))
                .foregroundColor(action.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(action.badgeBgColor)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(action.color.opacity(0.4), lineWidth: 1))
                .cornerRadius(6)
                .fixedSize(horizontal: false, vertical: true)

            Text(desc)
                .font(.caption)
                .lineSpacing(2)
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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
