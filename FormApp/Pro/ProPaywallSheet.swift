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
    @ObservedObject private var storeKit = StoreKitSubscriptionManager.shared
    @State private var selectedPlan: PaywallPlan = .annual
    @State private var showRestoreSuccess: Bool = false
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.openURL) private var openURL

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
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit2", descKey: "paywall.volume_matrix.benefit2_desc", iconName: "figure.walk"),
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit3", descKey: "paywall.volume_matrix.benefit3_desc", iconName: "gauge.with.needle.fill"),
                PaywallBenefit(titleKey: "paywall.volume_matrix.benefit4", descKey: "paywall.volume_matrix.benefit4_desc", iconName: "arrow.triangle.2.circlepath")
            ]
        case .formLab:
            return [
                PaywallBenefit(titleKey: "paywall.form_lab.benefit1", descKey: "paywall.form_lab.benefit1_desc", iconName: "number.circle.fill"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit2", descKey: "paywall.form_lab.benefit2_desc", iconName: "chart.xyaxis.line"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit3", descKey: "paywall.form_lab.benefit3_desc", iconName: "scalemass.fill"),
                PaywallBenefit(titleKey: "paywall.form_lab.benefit4", descKey: "paywall.form_lab.benefit4_desc", iconName: "cloud.fill")
            ]
        case .autoProgression:
            return [
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit1", descKey: "paywall.auto_progression.benefit1_desc", iconName: "arrow.up.forward.circle.fill"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit2", descKey: "paywall.auto_progression.benefit2_desc", iconName: "slider.horizontal.3"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit3", descKey: "paywall.auto_progression.benefit3_desc", iconName: "brain.head.profile"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit4", descKey: "paywall.auto_progression.benefit4_desc", iconName: "shield.checkered")
            ]
        case .warmupCalculator:
            return [
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit1", descKey: "paywall.warmup_calculator.benefit1_desc", iconName: "flame.fill"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit2", descKey: "paywall.warmup_calculator.benefit2_desc", iconName: "circle.grid.cross.fill"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit3", descKey: "paywall.warmup_calculator.benefit3_desc", iconName: "gauge.with.needle.fill"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit4", descKey: "paywall.warmup_calculator.benefit4_desc", iconName: "bolt.badge.clock.fill")
            ]
        case .none:
            return [
                PaywallBenefit(titleKey: "paywall.general.benefit1", descKey: "paywall.general.benefit1_desc", iconName: "figure.strengthtraining.traditional"),
                PaywallBenefit(titleKey: "paywall.general.benefit2", descKey: "paywall.general.benefit2_desc", iconName: "chart.line.uptrend.xyaxis"),
                PaywallBenefit(titleKey: "paywall.general.benefit3", descKey: "paywall.general.benefit3_desc", iconName: "waveform.path.ecg"),
                PaywallBenefit(titleKey: "paywall.general.benefit4", descKey: "paywall.general.benefit4_desc", iconName: "lock.shield.fill")
            ]
        }
    }

    private func dismissSelf() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Top Drag Indicator & Header
                    HStack {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.purpleBg)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(AppColors.purple)
                            }

                            ProBadge(text: LanguageManager.t("paywall.badge"))
                        }

                        Spacer()

                        Button(action: { dismissSelf() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }

                    // Headline & Subtitle
                    VStack(spacing: 6) {
                        let headline = feature != nil ? LanguageManager.t(feature!.titleKey) : LanguageManager.t("pro.upgrade_cta")
                        Text(headline)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .multilineTextAlignment(.center)

                        let subtitle = feature != nil ? LanguageManager.t(feature!.descriptionKey) : LanguageManager.t("paywall.cancel_anytime")
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    // Benefit List Card
                    VStack(spacing: 14) {
                        ForEach(benefits) { benefit in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.accent.opacity(0.12))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: benefit.iconName)
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LanguageManager.t(benefit.titleKey))
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                    Text(LanguageManager.t(benefit.descKey))
                                        .font(.system(size: 11.5))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineSpacing(2)
                                }

                                Spacer()
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

                    // Pricing Plans
                    VStack(spacing: 12) {
                        // Annual Plan Card (Featured)
                        let isAnnual = selectedPlan == .annual
                        Button(action: { selectedPlan = .annual }) {
                            VStack(spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        ProBadge(text: LanguageManager.t("paywall.annual_savings"))
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
                                        let annualPrice = storeKit.annualProduct?.displayPrice ?? LanguageManager.t("paywall.annual_price")
                                        Text(annualPrice)
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
                                    let monthlyPrice = storeKit.monthlyProduct?.displayPrice ?? LanguageManager.t("paywall.monthly_price")
                                    Text(monthlyPrice)
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
                            Task {
                                do {
                                    let purchased = try await storeKit.purchase(plan: selectedPlan)
                                    if purchased {
                                        onUnlocked?()
                                        dismissSelf()
                                    }
                                } catch {
                                    #if DEBUG
                                    proManager.updateSubscriptionStatus(active: true)
                                    onUnlocked?()
                                    dismissSelf()
                                    #endif
                                }
                            }
                        }) {
                            if storeKit.isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.background))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(AppColors.accent)
                                    .cornerRadius(14)
                            } else {
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
                        }
                        .buttonStyle(.plain)

                        Text(LanguageManager.t("paywall.cancel_anytime"))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Dev Mode Simulation & Legal Links
                    VStack(spacing: 10) {
                        #if DEBUG
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
                        #endif

                        // Restore Purchases & Legal Links
                        HStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    do {
                                        try await storeKit.restorePurchases()
                                        if proManager.isProSubscribed {
                                            showRestoreSuccess = true
                                            onUnlocked?()
                                        }
                                    } catch {
                                        #if DEBUG
                                        proManager.updateSubscriptionStatus(active: true)
                                        showRestoreSuccess = true
                                        onUnlocked?()
                                        #endif
                                    }
                                }
                            }) {
                                Text(LanguageManager.t("paywall.restore"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .foregroundColor(AppColors.border)

                            Button(action: {
                                if let url = URL(string: LegalUrls.termsOfService) {
                                    openURL(url)
                                }
                            }) {
                                Text(LanguageManager.t("paywall.terms"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Text("·")
                                .foregroundColor(AppColors.border)

                            Button(action: {
                                if let url = URL(string: LegalUrls.privacyPolicy) {
                                    openURL(url)
                                }
                            }) {
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
}

public struct ProPaywallPreview: View {
    public let feature: ProFeature
    public let onUpgradeClick: (() -> Void)?
    @State private var showSheet = false

    public init(
        feature: ProFeature,
        onUpgradeClick: (() -> Void)? = nil
    ) {
        self.feature = feature
        self.onUpgradeClick = onUpgradeClick
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppColors.purple)
                Text("FORCED REP PRO")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(AppColors.purple)
                    .tracking(0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(AppColors.purpleBg)
            .cornerRadius(6)

            Text(LanguageManager.t(feature.titleKey))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppColors.text)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(LanguageManager.t(feature.teaserKey))
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(2)
                .padding(.horizontal, 4)

            Button(action: {
                if let onUpgradeClick = onUpgradeClick {
                    onUpgradeClick()
                } else {
                    showSheet = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                    Text(LanguageManager.t("pro.upgrade_cta"))
                        .font(.system(size: 13.5, weight: .bold))
                }
                .foregroundColor(AppColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppColors.accent)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Text(LanguageManager.t("paywall.cancel_anytime_short"))
                .font(.system(size: 10))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 285)
        .background(AppColors.surfaceRaised.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.purple.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(16)
        .sheet(isPresented: $showSheet) {
            ProPaywallSheet(feature: feature, onDismiss: { showSheet = false })
        }
    }
}
