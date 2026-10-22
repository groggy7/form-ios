import SwiftUI

/// The Founders Pass introduction. The pass is not on sale yet, so release builds cannot buy it and
/// debug builds stand in for the purchase by granting founder status until the app restarts.
struct FoundersPassPaywallSheet: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var proManager = ProAccessManager.shared
    var onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    static var canPurchase: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        let _ = themeManager.currentTheme
        FoundersPassPaywallContent(
            canPurchase: Self.canPurchase,
            onPurchase: { proManager.updateFounderStatus(active: true) },
            onTerms: { if let url = URL(string: LegalUrls.termsOfService) { openURL(url) } },
            onPrivacy: { if let url = URL(string: LegalUrls.privacyPolicy) { openURL(url) } },
            onClose: onDismiss
        )
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(AppColors.progressionPaywallSurface)
        .onChange(of: proManager.isFounder) { if proManager.isFounder { onDismiss() } }
    }
}

/// Presentation only; FoundersPassPaywallSheet owns the purchase and dismissal.
struct FoundersPassPaywallContent: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let canPurchase: Bool
    let onPurchase: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onClose: () -> Void

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
                        AppIconPreview(option: AppIcons.standard, size: 80).padding(.bottom, 18)
                        Text(LanguageManager.t("founders.headline"))
                            .font(.app(size: headlineSize, weight: .bold)).foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
                        Text(LanguageManager.t("founders.subtitle"))
                            .font(.app(size: subtitleSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true).padding(.bottom, 22)
                        VStack(spacing: 16) {
                            benefit(1, icon: "infinity")
                            benefit(2, icon: "apps.iphone")
                            benefit(3, icon: "bolt.fill")
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 22)
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1).padding(.horizontal, 4)
                        plan
                        Text(LanguageManager.t("founders.platformNote"))
                            .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) { legalLinks(singleLine: true) }
                        VStack(spacing: 0) { legalLinks(singleLine: false) }
                    }
                    .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 4)
                }
            }
            .clipped()
            .accessibilityIdentifier("founders-paywall-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(AppColors.progressionPaywallSurface.ignoresSafeArea())
        .accessibilityIdentifier("founders-paywall-sheet")
    }

    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").font(.system(size: 18, weight: .semibold)).frame(width: 20, height: 20)
                Text(LanguageManager.t("founders.badge"))
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
            .accessibilityIdentifier("founders-paywall-close")
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
                Text(LanguageManager.t("founders.benefit\(number)"))
                    .font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("founders.benefit\(number)_desc"))
                    .font(.app(size: descriptionSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var plan: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(LanguageManager.t("founders.plan"))
                    .font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("founders.planSubtitle"))
                    .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Prices come from the store once the pass is sold.
            Text("—").font(.app(size: titleSize, weight: .bold)).foregroundStyle(accent)
        }
        .padding(16)
        .background(AppColors.progressionPaywallSelectedSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("founders-paywall-plan")
    }

    @ViewBuilder private func legalLinks(singleLine: Bool) -> some View {
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
                        Image(systemName: "lock.open").font(.system(size: 20, weight: .medium))
                        Text(LanguageManager.t("founders.cta"))
                            .font(.app(size: titleSize + 1, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppColors.background).padding(12).frame(maxWidth: .infinity, minHeight: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    .opacity(canPurchase ? 1 : 0.4)
                }
                .buttonStyle(.plain).disabled(!canPurchase)
                .accessibilityIdentifier("founders-paywall-purchase")
                Text(LanguageManager.t("founders.notOnSale"))
                    .font(.app(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(AppColors.progressionPaywallSurface)
        .accessibilityIdentifier("founders-paywall-footer")
    }
}
