import SwiftUI

public enum PaywallPlan: String, CaseIterable {
    case annual
    case monthly
}

public struct ProPaywallSheet: View {
    @ObservedObject var themeManager = ThemeManager.shared
    public var feature: ProFeature?
    public var onDismiss: (() -> Void)?
    public var onUnlocked: (() -> Void)?

    @ObservedObject private var proManager = ProAccessManager.shared
    @ObservedObject private var appStore = AppStore.shared
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
        // Workout swaps have no dedicated paywall art or copy; they use the general one, as on Android.
        self.feature = feature == .exerciseSwaps || feature == .bodyTrends ? nil : feature
        self.onDismiss = onDismiss
        self.onUnlocked = onUnlocked
    }

    private func dismissSelf() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
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

    public var body: some View {
        let _ = themeManager.currentTheme
        SessionFeaturePaywallContent(
            annual: SessionPaywallOffer(price: storeKit.annualProduct?.displayPrice,
                hasTrial: storeKit.hasFreeTrial(for: .annual), monthlyBreakdown: storeKit.annualPerMonthDisplayPrice,
                savingsPercent: storeKit.annualSavingsPercentage),
            monthly: SessionPaywallOffer(price: storeKit.monthlyProduct?.displayPrice,
                hasTrial: storeKit.hasFreeTrial(for: .monthly)),
            selectedPlan: selectedPlan, isPurchasing: storeKit.isPurchasing, isRestoring: isRestoring,
            purchaseError: purchaseErrorMessage, restoreMessage: restoreStatusMessage, isRestoreError: isRestoreError,
            onSelectPlan: { plan in
                userInteractedWithPlan = true
                selectedPlan = plan
                purchaseErrorMessage = nil
                restoreStatusMessage = nil
            },
            onPurchase: performPurchase, onRestore: performRestore,
            onRetryPrices: { Task { await storeKit.requestProducts() } },
            onTerms: { if let url = URL(string: LegalUrls.termsOfService) { openURL(url) } },
            onPrivacy: { if let url = URL(string: LegalUrls.privacyPolicy) { openURL(url) } },
            onClose: dismissSelf,
            feature: feature, weightUnit: appStore.weightUnit
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(AppColors.progressionPaywallSurface)
        .onAppear(perform: selectDefaultPlanIfNeeded)
        .onChange(of: storeKit.products) { selectDefaultPlanIfNeeded() }
        .onChange(of: storeKit.eligibleFreeTrialProductIds) { selectDefaultPlanIfNeeded() }
    }
}

public struct ProPaywallPreview: View {
    @ObservedObject var themeManager = ThemeManager.shared
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
        let _ = themeManager.currentTheme
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.purple)
                Text(LanguageManager.t("paywall.badge"))
                    .font(.app(size: 10.5, weight: .bold))
                    .foregroundStyle(AppColors.purple)
                    .tracking(0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(AppColors.purpleBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(LanguageManager.t(feature.titleKey))
                .font(.app(size: 15, weight: .bold))
                .foregroundStyle(AppColors.text)
                .multilineTextAlignment(.center)
                .lineLimit(1)

            Text(LanguageManager.t(feature.teaserKey))
                .font(.app(size: 12))
                .foregroundStyle(AppColors.secondaryText)
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
                        .font(.app(size: 13.5, weight: .bold))
                }
                .foregroundStyle(AppColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            Text(LanguageManager.t("paywall.cancel_anytime_short"))
                .font(.app(size: 10))
                .foregroundStyle(AppColors.secondaryText)
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showSheet) {
            ProPaywallSheet(feature: feature, onDismiss: { showSheet = false })
        }
    }
}
