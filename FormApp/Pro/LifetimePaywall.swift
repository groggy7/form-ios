import SwiftUI

/// Purchases and restores the selected non-consumable through StoreKit in every build configuration.
struct LifetimePaywallSheet: View {
    @ObservedObject private var proManager = ProAccessManager.shared
    @ObservedObject private var storeKit = StoreKitSubscriptionManager.shared
    var onDismiss: () -> Void
    @State private var isRestoring = false
    @State private var statusMessage: String?
    @Environment(\.openURL) private var openURL

    private var owned: Bool { proManager.hasLifetimeAccess }
    private var price: String? { storeKit.lifetimeProduct?.displayPrice }

    private func purchase() {
        guard !isRestoring && !storeKit.isPurchasing else { return }
        statusMessage = nil
        Task {
            do {
                switch try await storeKit.purchaseLifetime() {
                case .success: if owned { onDismiss() }
                case .pending: statusMessage = LanguageManager.t("paywall.purchase_pending")
                case .userCancelled: break
                }
            } catch {
                let key = (error as NSError).code == 404 ? "paywall.error_product_unavailable" : "paywall.purchase_failed"
                statusMessage = LanguageManager.t(key)
            }
        }
    }

    private func restore() {
        guard !isRestoring && !storeKit.isPurchasing else { return }
        isRestoring = true
        statusMessage = nil
        Task {
            defer { isRestoring = false }
            do {
                _ = try await storeKit.restorePurchases()
                if owned { onDismiss() }
                else { statusMessage = LanguageManager.t("lifetime.noPass") }
            } catch { statusMessage = LanguageManager.t("paywall.restore_failed") }
        }
    }

    var body: some View {
        LifetimePaywallContent(
            canPurchase: price != nil && !owned && !isRestoring && !storeKit.isPurchasing,
            onPurchase: purchase,
            onTerms: { if let url = URL(string: LegalUrls.termsOfService) { openURL(url) } },
            onPrivacy: { if let url = URL(string: LegalUrls.privacyPolicy) { openURL(url) } },
            onClose: onDismiss,
            price: price, isBusy: isRestoring || storeKit.isPurchasing, statusMessage: statusMessage,
            onRestore: restore, onRetry: { Task { await storeKit.requestProducts() } },
            hasActiveSubscription: proManager.hasActiveSubscription
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(AppColors.progressionPaywallSurface)
        .task { await storeKit.requestProducts(); if owned { onDismiss() } }
        .onChange(of: proManager.hasLifetimeAccess) { if owned { onDismiss() } }
    }
}

/// Presentation only; LifetimePaywallSheet owns the purchase and dismissal.
struct LifetimePaywallContent: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let canPurchase: Bool
    let onPurchase: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onClose: () -> Void
    var price: String? = nil
    var isBusy = false
    var statusMessage: String? = nil
    var onRestore: () -> Void = {}
    var onRetry: () -> Void = {}
    var hasActiveSubscription = false

    @ScaledMetric(relativeTo: .title) private var headlineSize = 26.0
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 13.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 12.0
    @ScaledMetric(relativeTo: .caption) private var bodySize = 11.0
    @ScaledMetric(relativeTo: .caption) private var descriptionSize = 12.0
    @ScaledMetric(relativeTo: .caption2) private var footnoteSize = 10.0
    private let headerRowHeight: CGFloat = 48
    private var accent: Color { AppColors.progressionPaywallAccent }

    var body: some View {
        let _ = themeManager.currentTheme
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(width: geometry.size.width)
                    VStack(alignment: .leading, spacing: 0) {
                        // The real Classic icon, so the hero needs no artwork of its own.
                        LifetimeLauncherIcon(size: 80).padding(.bottom, 18)
                        Text(LanguageManager.t("lifetime.headline"))
                            .font(.app(size: headlineSize, weight: .bold)).foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
                        Text(LanguageManager.t("lifetime.subtitle"))
                            .font(.app(size: subtitleSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 22)
                        VStack(spacing: 16) {
                            benefit(1, icon: "infinity")
                            benefit(2, icon: "checkmark.circle.fill")
                            benefit(3, icon: "arrow.clockwise")
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 22)
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1).padding(.horizontal, 4)
                        plan
                        Text(LanguageManager.t("lifetime.platformNote"))
                            .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)
                    if hasActiveSubscription {
                        Text(LanguageManager.t("lifetime.subscriptionNotice"))
                            .font(.app(size: descriptionSize)).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24).padding(.top, 16)
                    }
                    if let statusMessage {
                        Text(statusMessage).font(.app(size: descriptionSize)).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24).padding(.top, 16)
                            .accessibilityIdentifier("lifetime-paywall-feedback")
                    }
                    if price == nil {
                        Button(LanguageManager.t("paywall.retry"), action: onRetry)
                            .font(.app(size: descriptionSize)).foregroundStyle(accent).frame(minHeight: 48)
                            .disabled(isBusy).frame(maxWidth: .infinity)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) { legalLinks(singleLine: true) }
                        VStack(spacing: 0) { legalLinks(singleLine: false) }
                    }
                    .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 4)
                }
            }
            .clipped()
            .accessibilityIdentifier("lifetime-paywall-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(AppColors.progressionPaywallSurface.ignoresSafeArea())
        .accessibilityIdentifier("lifetime-paywall-sheet")
    }

    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").font(.system(size: 18, weight: .semibold)).frame(width: 20, height: 20)
                Text(LanguageManager.t("lifetime.badge"))
                    .font(.app(size: bodySize, weight: .bold)).tracking(1.3)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(accent).padding(.horizontal, 12).padding(.vertical, 9)
            .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.4), lineWidth: 1))
            // Equal clearance on both sides keeps the badge centered and clear of Close.
            .frame(maxWidth: max(48, width - 48 - 112))
            .frame(maxWidth: .infinity)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AppColors.secondaryText).frame(width: headerRowHeight, height: headerRowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(LanguageManager.t("common.close"))
            .accessibilityIdentifier("lifetime-paywall-close")
        }
        .frame(maxWidth: .infinity, minHeight: headerRowHeight)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10)
    }

    private func benefit(_ number: Int, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 34, height: 34).background(AppColors.progressionPaywallIconSurface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(LanguageManager.t("lifetime.benefit\(number)"))
                    .font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("lifetime.benefit\(number)_desc"))
                    .font(.app(size: descriptionSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var plan: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LanguageManager.t("lifetime.plan"))
                    .font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("lifetime.planSubtitle"))
                    .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(price ?? "—").font(.app(size: titleSize, weight: .bold)).foregroundStyle(accent)
        }
        .padding(16)
        .background(AppColors.progressionPaywallSelectedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lifetime-paywall-plan")
    }

    @ViewBuilder private func legalLinks(singleLine: Bool) -> some View {
        Button(action: onRestore) {
            Text(LanguageManager.t("paywall.auto_progression.restore")).fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
            .disabled(isBusy).accessibilityIdentifier("lifetime-paywall-restore")
        Button(action: onTerms) {
            Text(LanguageManager.t("paywall.terms")).fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
        Button(action: onPrivacy) {
            Text(LanguageManager.t("paywall.privacy")).fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1)
            VStack(spacing: 6) {
                Button(action: onPurchase) {
                    HStack(spacing: 10) {
                        if isBusy { ProgressView().tint(AppColors.background) }
                        else { Image(systemName: "lock.open").font(.system(size: 20, weight: .medium)) }
                        Text(LanguageManager.t("lifetime.cta"))
                            .font(.app(size: titleSize + 1, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppColors.background).padding(12).frame(maxWidth: .infinity, minHeight: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    .opacity(canPurchase ? 1 : 0.4)
                }
                .buttonStyle(.plain).disabled(!canPurchase)
                .accessibilityIdentifier("lifetime-paywall-purchase")
                Text(price.map { LanguageManager.t("lifetime.footer", ["price": $0]) }
                     ?? LanguageManager.t("paywall.price_unavailable"))
                    .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(AppColors.progressionPaywallSurface)
        .accessibilityIdentifier("lifetime-paywall-footer")
    }
}

/// A static preview of the primary launcher artwork, independent of icon selection.
private struct LifetimeLauncherIcon: View {
    let size: CGFloat

    private var image: UIImage? {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        guard let file = (primary?["CFBundleIconFiles"] as? [String])?.last else { return nil }
        return UIImage(named: file)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                AppColors.surfaceRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
