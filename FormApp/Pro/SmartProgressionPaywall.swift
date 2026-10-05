import SwiftUI

struct ProgressionPaywallOffer {
    let price: String?
    var hasTrial = false
    var monthlyBreakdown: String? = nil
    var savingsPercent: Int? = nil
}

/// A store-independent presentation; ProPaywallSheet owns billing and entitlement changes.
struct SmartProgressionPaywallContent: View {
    let annual: ProgressionPaywallOffer
    let monthly: ProgressionPaywallOffer
    let selectedPlan: PaywallPlan
    let isPurchasing: Bool
    let isRestoring: Bool
    let purchaseError: String?
    let restoreMessage: String?
    let isRestoreError: Bool
    let onSelectPlan: (PaywallPlan) -> Void
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onRetryPrices: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onClose: () -> Void

    @Environment(\.sizeCategory) private var textSize
    @ScaledMetric(relativeTo: .title) private var headlineSize = 26.0
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 13.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 12.0
    @ScaledMetric(relativeTo: .caption) private var bodySize = 11.0
    @ScaledMetric(relativeTo: .caption2) private var footnoteSize = 10.0
    private let accent = AppColors.progressionPaywallAccent
    private var selected: ProgressionPaywallOffer { selectedPlan == .annual ? annual : monthly }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    hero(width: geometry.size.width)
                    VStack(spacing: 10) {
                        Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1).padding(.horizontal, 4)
                        HStack(spacing: 12) {
                            benefitIcon("infinity", size: 32)
                            (Text(LanguageManager.t("paywall.auto_progression.unlock_title"))
                                .font(.system(size: subtitleSize, weight: .semibold)).foregroundColor(AppColors.text)
                             + Text(LanguageManager.t("paywall.auto_progression.unlock_suffix"))
                                .font(.system(size: subtitleSize)).foregroundColor(AppColors.secondaryText))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 8)
                        VStack(spacing: 8) {
                            plan(.annual, offer: annual, width: geometry.size.width - 40)
                            plan(.monthly, offer: monthly, width: geometry.size.width - 40)
                        }
                        if annual.price == nil || monthly.price == nil {
                            HStack {
                                Text(LanguageManager.t("paywall.price_unavailable"))
                                    .font(.system(size: subtitleSize)).foregroundStyle(AppColors.secondaryText)
                                Spacer(minLength: 8)
                                Button(LanguageManager.t("paywall.retry"), action: onRetryPrices)
                                    .font(.system(size: subtitleSize, weight: .semibold)).foregroundStyle(accent)
                                    .frame(minHeight: 48)
                            }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { legalLinks }
                            VStack(spacing: 0) { legalLinks }
                        }
                        .frame(maxWidth: .infinity)
                        if let restoreMessage { feedback(restoreMessage, isError: isRestoreError, retry: onRestore) }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 4)
                }
            }
            .accessibilityIdentifier("progression-paywall-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(AppColors.progressionPaywallSurface.ignoresSafeArea())
    }

    private func hero(width: CGFloat) -> some View {
        let comfortableText = width >= 350 && textSize <= .large
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill").font(.system(size: 18, weight: .semibold)).frame(width: 20, height: 20)
                    Text(LanguageManager.t("paywall.auto_progression.badge"))
                        .font(.system(size: bodySize, weight: .bold)).tracking(1.3)
                }
                .foregroundStyle(accent).padding(.horizontal, 12).padding(.vertical, 9)
                .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.4), lineWidth: 1))
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 22, weight: .regular))
                        .foregroundStyle(AppColors.secondaryText).frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(LanguageManager.t("common.close"))
                .accessibilityIdentifier("progression-paywall-close")
            }
            .padding(.bottom, 18)
            Text(LanguageManager.t("progression.coach.locked_title"))
                .font(.system(size: subtitleSize)).foregroundStyle(AppColors.secondaryText)
                .padding(.bottom, 8)
            Text(LanguageManager.t("paywall.auto_progression.headline"))
                .font(.system(size: headlineSize, weight: .bold))
                .foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                .frame(width: comfortableText ? (width - 48) * 0.64 : width - 48, alignment: .leading)
                .padding(.bottom, 10)
            Text(LanguageManager.t("paywall.auto_progression.subtitle"))
                .font(.system(size: subtitleSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: comfortableText ? (width - 48) * 0.68 : width - 48, alignment: .leading)
                .padding(.bottom, 22)
            VStack(spacing: 16) {
                benefit(1, icon: "arrow.up.right", width: comfortableText ? (width - 48) * 0.78 : width - 48)
                benefit(2, icon: "info.circle.fill", width: comfortableText ? (width - 48) * 0.78 : width - 48)
                benefit(3, icon: "bolt.fill", width: comfortableText ? (width - 48) * 0.78 : width - 48)
            }
        }
        .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            Image("paywall_smart_progression").resizable().scaledToFit()
                .frame(width: width, height: width * 1.1, alignment: .topTrailing).clipped()
                .overlay(LinearGradient(stops: [
                    .init(color: AppColors.progressionPaywallSurface.opacity(0.5), location: 0),
                    .init(color: AppColors.progressionPaywallSurface.opacity(0.35), location: 0.52),
                    .init(color: .clear, location: 0.78), .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.58),
                    .init(color: AppColors.progressionPaywallSurface, location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .overlay(comfortableText ? .clear : AppColors.progressionPaywallSurface.opacity(0.6))
                .accessibilityHidden(true)
        }
    }

    private func benefit(_ number: Int, icon: String, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 14) {
            benefitIcon(icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(LanguageManager.t("paywall.auto_progression.benefit\(number)"))
                    .font(.system(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("paywall.auto_progression.benefit\(number)_desc"))
                    .font(.system(size: bodySize)).foregroundStyle(AppColors.secondaryText).lineSpacing(2)
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    private func benefitIcon(_ name: String, size: CGFloat = 34) -> some View {
        Image(systemName: name).font(.system(size: 19, weight: .semibold)).foregroundStyle(accent)
            .frame(width: size, height: size).background(AppColors.progressionPaywallIconSurface, in: Circle())
            .accessibilityHidden(true)
    }

    private func plan(_ plan: PaywallPlan, offer: ProgressionPaywallOffer, width: CGFloat) -> some View {
        let isAnnual = plan == .annual
        let isSelected = selectedPlan == plan
        let stackPrice = width < 340 || textSize > .large
        return Button { onSelectPlan(plan) } label: {
            HStack(alignment: .top, spacing: 16) {
                Circle().stroke(isSelected ? accent : AppColors.secondaryText, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay { if isSelected { Circle().fill(accent).frame(width: 11, height: 11) } }
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) { planTitle(isAnnual); planTags(offer) }
                                VStack(alignment: .leading, spacing: 4) { planTitle(isAnnual); planTags(offer) }
                            }
                            let terms = isAnnual ? (offer.hasTrial ? "paywall.annual_trial_subtitle" : "paywall.annual_subtitle")
                                : (offer.hasTrial ? "paywall.monthly_trial_subtitle" : "paywall.auto_progression.monthly_subtitle")
                            Text(LanguageManager.t(terms)).font(.system(size: footnoteSize))
                                .foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !stackPrice { planPrice(offer, selected: isSelected) }
                    }
                    if stackPrice { planPrice(offer, selected: isSelected) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AppColors.progressionPaywallSelectedSurface : AppColors.progressionPaywallPlanSurface,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? accent : AppColors.border,
                                                             lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain).accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(isAnnual ? "progression-paywall-annual" : "progression-paywall-monthly")
    }

    private func planTitle(_ annual: Bool) -> some View {
        Text(LanguageManager.t(annual ? "paywall.annual_plan" : "paywall.monthly_plan"))
            .font(.system(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ offer: ProgressionPaywallOffer, selected: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(offer.price ?? "—").font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(selected ? accent : AppColors.text)
            if let breakdown = offer.monthlyBreakdown {
                Text(breakdown).font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func planTags(_ offer: ProgressionPaywallOffer) -> some View {
        if let savings = offer.savingsPercent {
            planTag(LanguageManager.t("paywall.annual_savings_template", ["savings": "\(savings)%"]))
        }
        if offer.hasTrial { planTag(LanguageManager.t("paywall.trial_badge")) }
    }

    private func planTag(_ text: String) -> some View {
        Text(text).font(.system(size: footnoteSize - 2, weight: .bold)).foregroundStyle(accent)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(0.55), lineWidth: 1))
    }

    @ViewBuilder private var legalLinks: some View {
        Button(action: onRestore) {
            if isRestoring { ProgressView().tint(AppColors.secondaryText) }
            else { Text(LanguageManager.t("paywall.restore")) }
        }.disabled(isRestoring).frame(minHeight: 48)
            .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
        Button(LanguageManager.t("paywall.terms"), action: onTerms)
            .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain).frame(minHeight: 48)
        Button(LanguageManager.t("paywall.privacy"), action: onPrivacy)
            .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain).frame(minHeight: 48)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1)
            VStack(spacing: 10) {
                Button(action: onPurchase) {
                    HStack(spacing: 10) {
                        if isPurchasing { ProgressView().tint(AppColors.background) }
                        else {
                            Image(systemName: "lock.open").font(.system(size: 20, weight: .medium))
                            Text(LanguageManager.t(selected.hasTrial ? "paywall.cta_trial" : "paywall.auto_progression.cta_continue"))
                                .font(.system(size: titleSize + 1, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(AppColors.background).padding(12).frame(maxWidth: .infinity, minHeight: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
                    .opacity(selected.price == nil ? 0.4 : 1)
                }
                .buttonStyle(.plain).disabled(isPurchasing || selected.price == nil)
                .accessibilityIdentifier("progression-paywall-purchase")
                Text(selected.price.map { LanguageManager.t(selectedPlan == .annual
                    ? "paywall.auto_progression.annual_footer" : "paywall.auto_progression.monthly_footer", ["price": $0]) }
                     ?? LanguageManager.t("paywall.price_unavailable_short"))
                    .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if selected.hasTrial {
                    Text(LanguageManager.t(selectedPlan == .annual ? "paywall.annual_trial_subtitle" : "paywall.monthly_trial_subtitle"))
                        .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                if let purchaseError { feedback(purchaseError, isError: true, retry: onPurchase) }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .background(AppColors.progressionPaywallSurface)
        .accessibilityIdentifier("progression-paywall-footer")
    }

    private func feedback(_ message: String, isError: Bool, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(message).font(.system(size: subtitleSize)).foregroundStyle(isError ? AppColors.danger : AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
            if isError {
                Button(LanguageManager.t("paywall.retry"), action: retry)
                    .foregroundStyle(accent).font(.system(size: subtitleSize, weight: .semibold)).frame(minHeight: 48)
            }
        }
        .padding(10).frame(maxWidth: .infinity)
        .background(isError ? AppColors.avoidBg : AppColors.positiveBg, in: RoundedRectangle(cornerRadius: 10))
    }
}
