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
    @ScaledMetric(relativeTo: .title2) private var headlineSize = 22.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 13.5
    @ScaledMetric(relativeTo: .subheadline) private var actionSize = 15.0
    @ScaledMetric(relativeTo: .caption) private var footnoteSize = 11.0
    @ObservedObject private var storeKit = StoreKitSubscriptionManager.shared
    @State private var selectedPlan: PaywallPlan = .annual
    @State private var userInteractedWithPlan: Bool = false
    @State private var purchaseErrorMessage: String? = nil
    @State private var restoreStatusMessage: String? = nil
    @State private var isRestoreError: Bool = false
    @State private var isRestoring: Bool = false
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
                PaywallBenefit(titleKey: "paywall.form_lab.benefit3", descKey: "paywall.form_lab.benefit3_desc", iconName: "scalemass.fill")
            ]
        case .cloudBackup:
            return [
                PaywallBenefit(titleKey: "paywall.cloud_backup.benefit1", descKey: "paywall.cloud_backup.benefit1_desc", iconName: "cloud.fill"),
                PaywallBenefit(titleKey: "paywall.cloud_backup.benefit2", descKey: "paywall.cloud_backup.benefit2_desc", iconName: "lock.shield.fill"),
                PaywallBenefit(titleKey: "paywall.cloud_backup.benefit3", descKey: "paywall.cloud_backup.benefit3_desc", iconName: "arrow.triangle.2.circlepath")
            ]
        case .autoProgression:
            return [
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit1", descKey: "paywall.auto_progression.benefit1_desc", iconName: "arrow.up.forward.circle.fill"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit2", descKey: "paywall.auto_progression.benefit2_desc", iconName: "info.circle.fill"),
                PaywallBenefit(titleKey: "paywall.auto_progression.benefit3", descKey: "paywall.auto_progression.benefit3_desc", iconName: "checkmark.circle.fill")
            ]
        case .warmupCalculator:
            return [
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit1", descKey: "paywall.warmup_calculator.benefit1_desc", iconName: "flame.fill"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit2", descKey: "paywall.warmup_calculator.benefit2_desc", iconName: "circle.grid.cross.fill"),
                PaywallBenefit(titleKey: "paywall.warmup_calculator.benefit3", descKey: "paywall.warmup_calculator.benefit3_desc", iconName: "plus.circle.fill")
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

    private var selectedPriceAvailable: Bool {
        selectedPlan == .annual ? storeKit.annualProduct != nil : storeKit.monthlyProduct != nil
    }

    private func selectDefaultPlanIfNeeded() {
        if !userInteractedWithPlan && !storeKit.hasFreeTrial(for: .annual) && storeKit.hasFreeTrial(for: .monthly) {
            selectedPlan = .monthly
        }
    }

    private func performPurchase() {
        guard !storeKit.isPurchasing else { return }
        purchaseErrorMessage = nil
        Task {
            do {
                let status = try await storeKit.purchase(plan: selectedPlan)
                switch status {
                case .success:
                    purchaseErrorMessage = nil
                    onUnlocked?()
                    dismissSelf()
                case .userCancelled:
                    purchaseErrorMessage = nil
                case .pending:
                    purchaseErrorMessage = LanguageManager.t("paywall.purchase_pending")
                }
            } catch {
                purchaseErrorMessage = LanguageManager.t("paywall.purchase_failed")
            }
        }
    }

    private func performRestore() {
        guard !isRestoring else { return }
        isRestoring = true
        restoreStatusMessage = nil
        Task {
            defer { isRestoring = false }
            do {
                let restored = try await storeKit.restorePurchases()
                if restored || proManager.isProSubscribed {
                    restoreStatusMessage = LanguageManager.t("paywall.restored_success")
                    isRestoreError = false
                    onUnlocked?()
                    dismissSelf()
                } else {
                    restoreStatusMessage = LanguageManager.t("paywall.restore_no_purchases")
                    isRestoreError = true
                }
            } catch {
                restoreStatusMessage = LanguageManager.t("paywall.restore_failed")
                isRestoreError = true
            }
        }
    }

    private var isSessionFeature: Bool {
        feature == .autoProgression || feature == .warmupCalculator
    }

    private var headlineKey: String {
        switch feature {
        case .autoProgression: return "paywall.auto_progression.headline"
        case .warmupCalculator: return "paywall.warmup_calculator.headline"
        default: return feature?.titleKey ?? "pro.upgrade_cta"
        }
    }

    private var subtitleKey: String {
        switch feature {
        case .autoProgression: return "paywall.auto_progression.subtitle"
        case .warmupCalculator: return "paywall.warmup_calculator.subtitle"
        default: return feature?.descriptionKey ?? "paywall.cancel_anytime"
        }
    }

    private var purchaseFooter: some View {
        // Primary Call to Action Button
        VStack(spacing: 8) {
            if isSessionFeature {
                let annual = selectedPlan == .annual
                let price = annual ? storeKit.annualProduct?.displayPrice : storeKit.monthlyProduct?.displayPrice
                Text(price.map { LanguageManager.t(annual ? "paywall.selected_annual_price" : "paywall.selected_monthly_price", ["price": $0]) }
                    ?? LanguageManager.t("paywall.price_unavailable_short"))
                    .font(.system(size: subtitleSize, weight: .bold))
                    .foregroundColor(AppColors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                let trial = storeKit.hasFreeTrial(for: selectedPlan)
                let termsKey = annual ? (trial ? "paywall.annual_trial_subtitle" : "paywall.annual_subtitle")
                    : (trial ? "paywall.monthly_trial_subtitle" : "paywall.monthly_subtitle")
                Text(LanguageManager.t(termsKey))
                    .font(.system(size: footnoteSize))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: {
                performPurchase()
            }) {
                if storeKit.isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.background))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 14, weight: .bold))
                        let planHasTrial = storeKit.hasFreeTrial(for: selectedPlan)
                        let ctaText = planHasTrial ? LanguageManager.t("paywall.cta_trial") : LanguageManager.t("paywall.cta_continue")
                        Text(ctaText)
                            .font(.system(size: actionSize, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(AppColors.background)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(AppColors.accent)
                    .cornerRadius(14)
                }
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isPurchasing || !selectedPriceAvailable)

            if let purchaseError = purchaseErrorMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppColors.danger)
                        .font(.system(size: 14))

                    Text(purchaseError)
                        .font(.system(size: 11.5))
                        .foregroundColor(AppColors.text)
                        .lineLimit(3)

                    Spacer()

                    Button(action: {
                        performPurchase()
                    }) {
                        Text(LanguageManager.t("paywall.retry"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.accent.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(AppColors.avoidBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.avoidBorder, lineWidth: 1)
                )
                .cornerRadius(10)
            }

            Text(LanguageManager.t("paywall.cancel_anytime"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
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
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LanguageManager.t("common.close"))
                    }

                    // Headline & Subtitle
                    VStack(spacing: 6) {
                        if isSessionFeature {
                            Text(LanguageManager.t(feature == .autoProgression ? "progression.coach.locked_title" : "warmup.card_title"))
                                .font(.system(size: 12, weight: .medium)).foregroundColor(AppColors.muted)
                        }
                        let headline = LanguageManager.t(headlineKey)
                        Text(headline)
                            .font(.system(size: headlineSize, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .multilineTextAlignment(.center)

                        let subtitle = LanguageManager.t(subtitleKey)
                        Text(subtitle)
                            .font(.system(size: subtitleSize))
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
                                        .font(.system(size: subtitleSize, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(LanguageManager.t(benefit.descKey))
                                        .font(.system(size: footnoteSize + 1))
                                        .foregroundColor(AppColors.secondaryText)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
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

                    if isSessionFeature {
                        if feature == .autoProgression {
                            Text(LanguageManager.t("paywall.auto_progression.history_hint"))
                                .font(.system(size: 12)).foregroundColor(AppColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(LanguageManager.t("paywall.all_features"))
                            .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Pricing Plans
                    VStack(spacing: 12) {
                        // Annual Plan Card (Featured)
                        let isAnnual = selectedPlan == .annual
                        Button(action: {
                            userInteractedWithPlan = true
                            selectedPlan = .annual
                        }) {
                            VStack(spacing: 10) {
                                HStack {
                                    HStack(spacing: 6) {
                                        if let savings = storeKit.annualSavingsPercentage {
                                            ProBadge(text: LanguageManager.t("paywall.annual_savings_template", ["savings": "\(savings)%"]))
                                        }
                                        if storeKit.hasFreeTrial(for: .annual) {
                                            ProBadge(text: LanguageManager.t("paywall.trial_badge"))
                                        }
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
                                        Text(storeKit.hasFreeTrial(for: .annual) ? LanguageManager.t("paywall.annual_trial_subtitle") : LanguageManager.t("paywall.annual_subtitle"))
                                            .font(.system(size: 11.5))
                                            .foregroundColor(AppColors.secondaryText)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        let annualPrice = storeKit.annualProduct?.displayPrice ?? "—"
                                        Text(annualPrice)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(AppColors.accent)
                                        let annualBreakdown = storeKit.annualPerMonthDisplayPrice ?? LanguageManager.t("paywall.price_unavailable_short")
                                        Text(annualBreakdown)
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
                        Button(action: {
                            userInteractedWithPlan = true
                            selectedPlan = .monthly
                        }) {
                            VStack(spacing: 10) {
                                HStack {
                                    if storeKit.hasFreeTrial(for: .monthly) {
                                        ProBadge(text: LanguageManager.t("paywall.trial_badge"))
                                    } else {
                                        Spacer()
                                    }

                                    Spacer()

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

                                HStack(alignment: .bottom) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("paywall.monthly_plan"))
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Text(storeKit.hasFreeTrial(for: .monthly) ? LanguageManager.t("paywall.monthly_trial_subtitle") : LanguageManager.t("paywall.monthly_subtitle"))
                                            .font(.system(size: 11.5))
                                            .foregroundColor(AppColors.secondaryText)
                                    }

                                    Spacer()

                                    let monthlyPrice = storeKit.monthlyProduct?.displayPrice ?? "—"
                                    Text(monthlyPrice)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(isMonthly ? AppColors.accent : AppColors.text)
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
                        if storeKit.annualProduct == nil || storeKit.monthlyProduct == nil {
                            HStack(spacing: 8) {
                                Text(LanguageManager.t("paywall.price_unavailable"))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.secondaryText)
                                Spacer()
                                Button(LanguageManager.t("paywall.retry")) {
                                    Task { await storeKit.requestProducts() }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                            }
                        }
                    }

                    if !isSessionFeature { purchaseFooter }

                    // Restore Purchases & Legal Links
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Button(action: {
                                performRestore()
                            }) {
                                if isRestoring {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.secondaryText))
                                        .scaleEffect(0.7)
                                } else {
                                    Text(LanguageManager.t("paywall.restore"))
                                        .font(.system(size: 11.5))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRestoring)

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

                        if let status = restoreStatusMessage {
                            HStack(alignment: .center, spacing: 6) {
                                Image(systemName: isRestoreError ? "exclamationmark.circle" : "checkmark.circle.fill")
                                    .foregroundColor(isRestoreError ? AppColors.danger : AppColors.accent)
                                    .font(.system(size: 12))

                                Text(status)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(isRestoreError ? AppColors.danger : AppColors.accent)
                                    .multilineTextAlignment(.center)

                                if isRestoreError {
                                    Button(action: {
                                        performRestore()
                                    }) {
                                        Text(LanguageManager.t("paywall.retry"))
                                            .font(.system(size: 11.5, weight: .bold))
                                            .foregroundColor(AppColors.accent)
                                            .underline()
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSessionFeature {
                    purchaseFooter
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.surface)
                        .overlay(alignment: .top) { Rectangle().fill(AppColors.border).frame(height: 1) }
                }
            }
            .onAppear(perform: selectDefaultPlanIfNeeded)
            .onChange(of: storeKit.products) { selectDefaultPlanIfNeeded() }
            .onChange(of: storeKit.eligibleFreeTrialProductIds) { selectDefaultPlanIfNeeded() }
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
                Text(LanguageManager.t("paywall.badge"))
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
