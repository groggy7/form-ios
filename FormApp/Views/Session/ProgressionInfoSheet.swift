import SwiftUI

public struct ProgressionInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    actionsSection
                    plateauSection
                    tipSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("progression.info.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Text(LanguageManager.t("progression.info.ddpTitle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)
            }

            Text(LanguageManager.t("progression.info.ddpText"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Progression Rules")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)

            VStack(spacing: 10) {
                actionRow(
                    action: .increaseLoad,
                    desc: "When all working sets hit the top rep target with clean form, increase weight by 2.5 kg (or 5 lb)."
                )
                actionRow(
                    action: .addReps,
                    desc: "When sets are within the target rep range, maintain load and push reps upward."
                )
                actionRow(
                    action: .holdLoad,
                    desc: "When failing below the rep floor on any set, hold weight to consolidate form and recovery."
                )
                actionRow(
                    action: .deload,
                    desc: "When stagnant across 3+ workouts, deload load by 10% or swap to a fresh variation."
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
        HStack(alignment: .top, spacing: 12) {
            Text(LanguageManager.t(action.titleKey))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(action.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(action.badgeBgColor)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(action.color.opacity(0.4), lineWidth: 1))
                .cornerRadius(6)
                .frame(width: 140, alignment: .leading)

            Text(desc)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var plateauSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xB18AFF))
                Text(LanguageManager.t("progression.info.plateauTitle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)
            }

            Text(LanguageManager.t("progression.info.plateauText"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: 0xF2AF61))
                Text(LanguageManager.t("progression.info.tipTitle"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)
            }

            Text(LanguageManager.t("progression.info.tipText"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1A1E24))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xF2AF61).opacity(0.3), lineWidth: 1))
        .cornerRadius(16)
    }
}
