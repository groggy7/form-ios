import SwiftUI

public enum PaywallPlan: String, CaseIterable {
    case annual
    case monthly
}

private struct PaywallBenefit: Identifiable {
    let id = UUID()
    let titleKey: String
    let descKey: String
    let iconName: String
}

public struct ProPaywallSheet: View {
    public var feature: ProFeature?
    public var onDismiss: (() -> Void)?
    public var onUnlocked: (() -> Void)?

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var selectedPlan: PaywallPlan = .annual
    @State private var showRestoreSuccess: Bool = false
    @Environment(\.presentationMode) private var presentationMode

    public init(
        feature: ProFeature? = nil,
        onDismiss: (() -> Void)? = nil,
        onUnlocked: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.onDismiss = onDismiss
        self.onUnlocked = onUnlocked
    }

    private var benefits: [PaywallBenefit] {
        switch feature {
        case .volumeMatrix:
            return [
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit1", descKey: "paywall.volume_matrix.benefit1_desc", iconName: "chart.bar.fill"),
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit2", descKey: "paywall.volume_matrix.benefit2_desc", iconName: "square.grid.3x3.fill"),
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit3", descKey: "paywall.volume_matrix.benefit3_desc", iconName: "bolt.heart.fill")
            ]
        case .formLab:
            return [
                PaywallBenefit(titleKey: "paywall.form_lab.benefit1", descKey: "paywall.form_lab.benefit1_desc", iconName: "function"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit2", descKey: "paywall.form_lab.benefit2_desc", iconName: "chart.xyaxis.line"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit3", descKey: "paywall.form_lab.benefit3_desc", iconName: "scalemass.fill"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit4", descKey: "paywall.form_lab.benefit4_desc", iconName: "lock.icloud.fill")
            ]
        case .autoProgression:
            return [
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit1", descKey: "paywall.auto_progression.benefit1_desc", iconName: "arrow.up.forward.app.fill"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit2", descKey: "paywall.auto_progression.benefit2_desc", iconName: "arrow.counterclockwise.circle.fill")
            ]
        case .warmupCalculator:
            return [
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit1", descKey: "paywall.warmup_calculator.benefit1_desc", iconName: "figure.strengthtraining.traditional"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit2", descKey: "paywall.warmup_calculator.benefit2_desc", iconName: "circle.grid.2x1.fill")
            ]
        case .none:
            return [
                PaywallBenefit(titleKey: "pro.volume_matrix.title", descKey: "pro.volume_matrix.description", iconName: "chart.bar.fill"),
                PaywallBenefit(titleKey: "pro.form_lab.title", descKey: "pro.form_lab.description", iconName: "chart.xyaxis.line"),
                PaywallBenefit(titleKey: "pro.auto_progression.title", descKey: "pro.auto_progression.description", iconName: "arrow.up.forward.app.fill"),
                PaywallBenefit(titleKey: "pro.warmup_calculator.title", descKey: "pro.warmup_calculator.description", iconName: "figure.strengthtraining.traditional")
            ]
        }
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header: Pro Badge & Close Button
                    HStack {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.purpleBg)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.purple)
                            }
                            ProBadge(text: LanguageManager.t("paywall.badge"))
                        }

                        Spacer()

                        Button(action: dismissSelf) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 32, height: 32)
                                .background(AppColors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Headline & Value Context
                    VStack(alignment: .leading, spacing: 6) {
                        let headline = feature != nil ? LanguageManager.t(feature!.titleKey) : LanguageManager.t("pro.upgrade_cta")
                        Text(headline)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)

                        let subtitle = feature != nil ? LanguageManager.t(feature!.descriptionKey) : LanguageManager.t("paywall.cancel_anytime")
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundColor(AppColors.secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Value Propositions Card
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(benefits) { benefit in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.accent.opacity(0.15))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: benefit.iconName)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.accent)
                                }
                                .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageManager.t(benefit.titleKey))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                    Text(LanguageManager.t(benefit.descKey))
                                        .font(.system(size: 12.5))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .cornerRadius(16)

                    // Subscription Plan Cards
                    VStack(spacing: 12) {
                        // Annual Plan Card
                        let isAnnual = selectedPlan == .annual
                        Button(action: { selectedPlan = .annual }) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Text(LanguageManager.t("paywall.annual_savings"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(AppColors.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.accent.opacity(0.18))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .stroke(AppColors.accent.opacity(0.5), lineWidth: 1)
                                            )
                                            .cornerRadius(4)

                                        ProBadge(text: LanguageManager.t("paywall.annual_trial"))
                                    }

                                    Spacer()

                                    ZStack {
                                        Circle()
                                            .stroke(isAnnual ? AppColors.accent : AppColors.secondaryText, lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if isAnnual {
                                            Circle()
                                                .fill(AppColors.accent)
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                }

                                HStack(alignment: .bottom) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("paywall.annual_plan"))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Text(LanguageManager.t("paywall.annual_subtitle"))
                                            .font(.system(size: 11.5))
                                            .foregroundColor(AppColors.secondaryText)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(LanguageManager.t("paywall.annual_price"))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(AppColors.accent)
                                        Text(LanguageManager.t("paywall.annual_breakdown"))
                                            .font(.system(size: 11.5))
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                            }
                            .padding(16)
                            .background(isAnnual ? AppColors.accent.opacity(0.08) : AppColors.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isAnnual ? AppColors.accent : AppColors.border, lineWidth: isAnnual ? 1.5 : 1)
                            )
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        // Monthly Plan Card
                        let isMonthly = selectedPlan == .monthly
                        Button(action: { selectedPlan = .monthly }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageManager.t("paywall.monthly_plan"))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(AppColors.text)
                                    Text(LanguageManager.t("paywall.monthly_subtitle"))
                                        .font(.system(size: 11.5))
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                HStack(spacing: 12) {
                                    Text(LanguageManager.t("paywall.monthly_price"))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(isMonthly ? AppColors.accent : AppColors.text)

                                    ZStack {
                                        Circle()
                                            .stroke(isMonthly ? AppColors.accent : AppColors.secondaryText, lineWidth: 1.5)
                                            .frame(width: 20, height: 20)
                                        if isMonthly {
                                            Circle()
                                                .fill(AppColors.accent)
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .background(isMonthly ? AppColors.accent.opacity(0.08) : AppColors.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isMonthly ? AppColors.accent : AppColors.border, lineWidth: isMonthly ? 1.5 : 1)
                            )
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }

                    // Primary Call to Action Button
                    VStack(spacing: 8) {
                        Button(action: {
                            proManager.updateSubscriptionStatus(active: true)
                            onUnlocked?()
                            dismissSelf()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 14, weight: .bold))
                                let ctaText = selectedPlan == .annual ? LanguageManager.t("paywall.cta_trial") : LanguageManager.t("paywall.cta_continue")
                                Text(ctaText)
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)

                        Text(LanguageManager.t("paywall.cancel_anytime"))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Dev Mode Simulation & Legal Links
                    VStack(spacing: 10) {
                        // Quick Dev Unlock Button
                        Button(action: {
                            proManager.updateSubscriptionStatus(active: true)
                            onUnlocked?()
                            dismissSelf()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.open")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(LanguageManager.t("paywall.dev_unlock"))
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundColor(AppColors.purple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.purple.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Restore Purchases & Legal Links
                        HStack(spacing: 12) {
                            Button(action: {
                                proManager.updateSubscriptionStatus(active: true)
                                showRestoreSuccess = true
                                onUnlocked?()
                            }) {
                                Text(LanguageManager.t("paywall.restore"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .foregroundColor(AppColors.border)

                            Button(action: {}) {
                                Text(LanguageManager.t("paywall.terms"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .foregroundColor(AppColors.border)

                            Button(action: {}) {
                                Text(LanguageManager.t("paywall.privacy"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }

                        if showRestoreSuccess {
                            Text(LanguageManager.t("paywall.restored_success"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
    }

    private func dismissSelf() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

public struct ProPaywallPreview: View {
    public var feature: ProFeature
    public var onUpgradeClick: (() -> Void)?

    @State private var showSheet: Bool = false

    public init(feature: ProFeature, onUpgradeClick: (() -> Void)? = nil) {
        self.feature = feature
        self.onUpgradeClick = onUpgradeClick
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.purpleBg)
                    .frame(width: 56, height: 56)
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.purple)
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(LanguageManager.t(feature.titleKey))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .multilineTextAlignment(.center)
                    ProBadge()
                }

                Text(LanguageManager.t(feature.descriptionKey))
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: {
                if let onUpgradeClick = onUpgradeClick {
                    onUpgradeClick()
                } else {
                    showSheet = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                    Text(LanguageManager.t("pro.upgrade_cta"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(AppColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppColors.accent)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(AppColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .cornerRadius(20)
        .sheet(isPresented: $showSheet) {
            ProPaywallSheet(feature: feature, onDismiss: { showSheet = false })
        }
    }
}
