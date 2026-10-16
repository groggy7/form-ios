import SwiftUI

public struct FormLabInfoSheet: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var language = LanguageManager.shared

    public init() {}

    public var body: some View {
        let _ = themeManager.currentTheme
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    overviewSection
                    formulasSection
                    balanceSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("form_lab.info_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FormCloseToolbarItem { dismiss() }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t("form_lab.info_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.text)
            Text(LanguageManager.t("form_lab.info_subtitle"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var formulasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LanguageManager.t("form_lab.info_brzycki_epley_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.text)

            VStack(alignment: .leading, spacing: 4) {
                Text("Brzycki")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                Text(LanguageManager.t("form_lab.info_brzycki_subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("Epley")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                Text(LanguageManager.t("form_lab.info_epley_subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(LanguageManager.t("form_lab.info_brzycki_epley_desc"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LanguageManager.t("form_lab.info_antagonist_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.text)

            Text(LanguageManager.t("form_lab.info_antagonist_desc"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(AppColors.secondaryText)

            VStack(spacing: 8) {
                ratioRow(label: LanguageManager.t("form_lab.balance.push_pull_title"), range: "0.80 – 1.25", desc: LanguageManager.t("form_lab.info_push_pull_desc"))
                ratioRow(label: LanguageManager.t("form_lab.balance.quad_ham_title"), range: "0.75 – 1.40", desc: LanguageManager.t("form_lab.info_quad_ham_desc"))
                ratioRow(label: LanguageManager.t("form_lab.balance.upper_lower_title"), range: "0.65 – 1.60", desc: LanguageManager.t("form_lab.info_upper_lower_desc"))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func ratioRow(label: String, range: String, desc: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.muted)
            }
            Spacer()
            Text(range)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.positiveBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
