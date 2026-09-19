import SwiftUI

public struct FormLabInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = LanguageManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    formulasSection
                    balanceSection
                    cloudSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("form_lab.info_title"))
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
            Text(LanguageManager.t("form_lab.info_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)
            Text(LanguageManager.t("form_lab.info_subtitle"))
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

    private var formulasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LanguageManager.t("form_lab.info_brzycki_epley_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)

            VStack(alignment: .leading, spacing: 6) {
                Text("Brzycki (1993)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Text("1RM = Weight × (36 / (37 − Reps))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Epley (1985)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Text("1RM = Weight × (1 + Reps / 30)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .cornerRadius(10)

            Text(LanguageManager.t("form_lab.info_brzycki_epley_desc"))
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

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LanguageManager.t("form_lab.info_antagonist_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)

            Text(LanguageManager.t("form_lab.info_antagonist_desc"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundColor(AppColors.secondaryText)

            VStack(spacing: 8) {
                ratioRow(label: "Push / Pull", range: "0.80 – 1.25", desc: "Glenohumeral & Scapular Balance")
                ratioRow(label: "Quad / Hamstring", range: "0.75 – 1.40", desc: "Knee Joint Shear & ACL Integrity")
                ratioRow(label: "Upper / Lower", range: "0.65 – 1.60", desc: "Systemic Whole-Body Equilibrium")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private func ratioRow(label: String, range: String, desc: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.text)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.muted)
            }
            Spacer()
            Text(range)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.positiveBg)
                .cornerRadius(6)
        }
        .padding(10)
        .background(AppColors.surface)
        .cornerRadius(10)
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t("form_lab.info_cloud_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.text)
            Text(LanguageManager.t("form_lab.info_cloud_desc"))
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
}
