import SwiftUI

struct SessionPaywallOffer {
    let price: String?
    var hasTrial = false
    var monthlyBreakdown: String? = nil
    var savingsPercent: Int? = nil
}

/// A store-independent presentation; ProPaywallSheet owns billing and entitlement changes.
struct SessionFeaturePaywallContent: View {
    let annual: SessionPaywallOffer
    let monthly: SessionPaywallOffer
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
    var feature: ProFeature? = .autoProgression
    var weightUnit: WeightUnit = .kg

    @Environment(\.sizeCategory) private var textSize
    @ScaledMetric(relativeTo: .title) private var headlineSize = 26.0
    @ScaledMetric(relativeTo: .title) private var warmupHeadlineSize = 24.0
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 13.0
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize = 12.0
    @ScaledMetric(relativeTo: .caption) private var bodySize = 11.0
    @ScaledMetric(relativeTo: .caption2) private var footnoteSize = 10.0
    private let headerTopPadding: CGFloat = 12
    private let headerRowHeight: CGFloat = 48
    private let headerBottomPadding: CGFloat = 10
    private let accent = AppColors.progressionPaywallAccent
    private var isWarmup: Bool { feature == .warmupCalculator }
    private var isVolumeMatrix: Bool { feature == .volumeMatrix }
    private var isRepLab: Bool { feature == .formLab }
    private var isGeneral: Bool { feature == nil }
    private var copyPrefix: String { feature == nil ? "paywall.general" : "paywall.\(feature!.rawValue)" }
    private var tagPrefix: String {
        switch feature {
        case .warmupCalculator: return "warmup-paywall"
        case .volumeMatrix: return "volume-paywall"
        case .formLab: return "rep-lab-paywall"
        case .none: return "general-paywall"
        default: return "progression-paywall"
        }
    }
    private var heroArtwork: String {
        switch feature {
        case .warmupCalculator: return weightUnit == .lbs ? "paywall_warmup_plates_lbs" : "paywall_warmup_plates"
        case .volumeMatrix: return "paywall_volume_matrix"
        case .formLab: return "paywall_rep_lab"
        case .none: return "paywall_general"
        default: return "paywall_smart_progression"
        }
    }
    private var featureTitleKey: String {
        switch feature {
        case .warmupCalculator: return "warmup.card_title"
        case .volumeMatrix, .formLab, .none: return "\(copyPrefix).feature_title"
        default: return "progression.coach.locked_title"
        }
    }
    private var selected: SessionPaywallOffer { selectedPlan == .annual ? annual : monthly }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        header(width: geometry.size.width)
                        hero(width: geometry.size.width)
                        VStack(spacing: 10) {
                            Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1).padding(.horizontal, 4)
                            HStack(spacing: 12) {
                                benefitIcon("infinity", size: 32)
                                (Text(LanguageManager.t("\(copyPrefix).unlock_title"))
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
                        }
                        .padding(.horizontal, 20)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 0) { legalLinks(singleLine: true) }
                            VStack(spacing: 0) { legalLinks(singleLine: false) }
                        }
                        .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 4)
                        if let restoreMessage {
                            feedback(restoreMessage, isError: isRestoreError, retry: onRestore)
                                .padding(.horizontal, 20).padding(.top, 10)
                        }
                    }
                }
                .clipped()
                .accessibilityIdentifier("\(tagPrefix)-scroll")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .background(AppColors.progressionPaywallSurface.ignoresSafeArea())
    }

    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill").font(.system(size: 18, weight: .semibold)).frame(width: 20, height: 20)
                Text(LanguageManager.t("paywall.auto_progression.badge"))
                    .font(.system(size: bodySize, weight: .bold)).tracking(1.3)
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
            .accessibilityIdentifier("\(tagPrefix)-close")
        }
        .frame(maxWidth: .infinity, minHeight: headerRowHeight)
        .padding(.horizontal, 24).padding(.top, headerTopPadding).padding(.bottom, headerBottomPadding)
    }

    private func hero(width: CGFloat) -> some View {
        let comfortableText = width >= 350 && textSize <= .large
        // The header replaces the space it previously occupied inside the photographic hero.
        let heroHeight = max(0, width * 1.1 - headerTopPadding - headerRowHeight - headerBottomPadding)
        return VStack(alignment: .leading, spacing: 0) {
            Text(LanguageManager.t(featureTitleKey))
                .font(.system(size: subtitleSize)).foregroundStyle(AppColors.secondaryText)
                .padding(.bottom, 8)
            Text(LanguageManager.t("\(copyPrefix).headline"))
                .font(.system(size: isWarmup ? warmupHeadlineSize : headlineSize, weight: .bold))
                .foregroundStyle(AppColors.text).fixedSize(horizontal: false, vertical: true)
                .frame(width: comfortableText ? (width - 48) * (isWarmup ? 0.84 : (isVolumeMatrix || isRepLab || isGeneral ? 0.72 : 0.64)) : width - 48, alignment: .leading)
                .padding(.bottom, 10)
            Text(LanguageManager.t("\(copyPrefix).subtitle"))
                .font(.system(size: subtitleSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: comfortableText ? (width - 48) * 0.68 : width - 48, alignment: .leading)
                .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 16) {
                benefit(1, icon: (isVolumeMatrix || isWarmup) ? "chart.bar.fill" : (isRepLab ? "number.circle.fill" : (isGeneral ? "arrow.up.forward.circle.fill" : "arrow.up.right")), width: comfortableText ? (width - 48) * 0.78 : width - 48)
                benefit(2, icon: isWarmup ? "paywall.plates" : (isVolumeMatrix || isGeneral ? "square.grid.3x3.fill" : (isRepLab ? "chart.xyaxis.line" : "info.circle.fill")), width: comfortableText ? (width - 48) * 0.78 : width - 48)
                benefit(3, icon: isWarmup ? "plus" : (isVolumeMatrix ? "calendar" : (isRepLab ? "chart.bar.fill" : (isGeneral ? "chart.xyaxis.line" : "bolt.fill"))), width: comfortableText ? (width - 48) * 0.78 : width - 48)
            }
            if isRepLab {
                Text(LanguageManager.t("\(copyPrefix).reference_note"))
                    .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: comfortableText ? (width - 48) * 0.78 : width - 48, alignment: .leading)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 22)
        .frame(minHeight: heroHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            Image(heroArtwork).resizable().scaledToFill()
                .frame(width: width, height: heroHeight, alignment: .topTrailing).clipped()
                .overlay(LinearGradient(stops: [
                    .init(color: AppColors.progressionPaywallSurface.opacity(0.5), location: 0),
                    .init(color: AppColors.progressionPaywallSurface.opacity(0.35), location: 0.52),
                    .init(color: .clear, location: 0.78), .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .overlay(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: isVolumeMatrix ? 0.80 : 0.58),
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
                Text(LanguageManager.t("\(copyPrefix).benefit\(number)"))
                    .font(.system(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                Text(LanguageManager.t("\(copyPrefix).benefit\(number)_desc"))
                    .font(.system(size: bodySize)).foregroundStyle(AppColors.secondaryText).lineSpacing(2)
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    private func benefitIcon(_ name: String, size: CGFloat = 34) -> some View {
        Group {
            if name == "paywall.plates" {
                WarmupPlateStack().fill(accent).frame(width: 22, height: 22)
                    .overlay(Ellipse().fill(AppColors.progressionPaywallIconSurface).frame(width: 6, height: 3).offset(y: -5))
            }
            else { Image(systemName: name).font(.system(size: 19, weight: .semibold)).foregroundStyle(accent) }
        }
            .frame(width: size, height: size).background(AppColors.progressionPaywallIconSurface, in: Circle())
            .accessibilityHidden(true)
    }

    private func plan(_ plan: PaywallPlan, offer: SessionPaywallOffer, width: CGFloat) -> some View {
        let isAnnual = plan == .annual
        let isSelected = selectedPlan == plan
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
                            let terms = isAnnual ? (offer.hasTrial ? "paywall.auto_progression.annual_trial_subtitle" : "paywall.annual_subtitle")
                                : (offer.hasTrial ? "paywall.auto_progression.monthly_trial_subtitle" : "paywall.auto_progression.monthly_subtitle")
                            Text(LanguageManager.t(terms)).font(.system(size: footnoteSize))
                                .foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        planPrice(offer, selected: isSelected, maxWidth: width * 0.4).layoutPriority(1)
                    }
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
        .accessibilityIdentifier(isAnnual ? "\(tagPrefix)-annual" : "\(tagPrefix)-monthly")
    }

    private func planTitle(_ annual: Bool) -> some View {
        Text(LanguageManager.t(annual ? "paywall.annual_plan" : "paywall.monthly_plan"))
            .font(.system(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func planPrice(_ offer: SessionPaywallOffer, selected: Bool, maxWidth: CGFloat) -> some View {
        PaywallPriceWidth(maxWidth: maxWidth) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(offer.price ?? "—").font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(selected ? accent : AppColors.text)
                if let breakdown = offer.monthlyBreakdown {
                    Text(breakdown).font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                }
            }
            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func planTags(_ offer: SessionPaywallOffer) -> some View {
        if let savings = offer.savingsPercent {
            planTag(LanguageManager.t("paywall.annual_savings_template", ["savings": "\(savings)%"]))
        }
    }

    private func planTag(_ text: String) -> some View {
        Text(text).font(.system(size: footnoteSize - 2, weight: .bold)).foregroundStyle(accent)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(accent.opacity(0.55), lineWidth: 1))
    }

    @ViewBuilder private func legalLinks(singleLine: Bool) -> some View {
        Button(action: onRestore) {
            Group {
                if isRestoring { ProgressView().tint(AppColors.secondaryText) }
                else { Text(LanguageManager.t("paywall.auto_progression.restore")).fixedSize(horizontal: singleLine, vertical: true) }
            }
            .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.disabled(isRestoring)
            .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
        Button(action: onTerms) {
            Text(LanguageManager.t("paywall.terms")).fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
        Button(action: onPrivacy) {
            Text(LanguageManager.t("paywall.privacy")).fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 6).frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText).buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppColors.border.opacity(0.65)).frame(height: 1)
            VStack(spacing: 6) {
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
                .accessibilityIdentifier("\(tagPrefix)-purchase")
                let footerTerms = selectedPlan == .annual
                    ? (selected.hasTrial ? "paywall.auto_progression.annual_trial_footer" : "paywall.auto_progression.annual_footer")
                    : (selected.hasTrial ? "paywall.auto_progression.monthly_trial_footer" : "paywall.auto_progression.monthly_footer")
                Text(selected.price.map { LanguageManager.t(footerTerms, ["price": $0]) }
                     ?? LanguageManager.t("paywall.price_unavailable_short"))
                    .font(.system(size: footnoteSize)).foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                if let purchaseError { feedback(purchaseError, isError: true, retry: onPurchase) }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(AppColors.progressionPaywallSurface)
        .accessibilityIdentifier("\(tagPrefix)-footer")
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

/// Keep short prices at their natural width and wrap long prices within the trailing column.
private struct PaywallPriceWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let limit = max(0, min(maxWidth, proposal.width ?? maxWidth))
        let width = min(limit, content.sizeThatFits(.unspecified).width)
        guard width > 0 else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct WarmupPlateStack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 3, y: 2, width: 18, height: 12))
        for y in [CGFloat(13), CGFloat(18)] {
            path.move(to: CGPoint(x: 3, y: y))
            path.addCurve(to: CGPoint(x: 21, y: y), control1: CGPoint(x: 7, y: y + 4), control2: CGPoint(x: 17, y: y + 4))
            path.addLine(to: CGPoint(x: 21, y: y + 3))
            path.addCurve(to: CGPoint(x: 3, y: y + 3), control1: CGPoint(x: 17, y: y + 7), control2: CGPoint(x: 7, y: y + 7))
            path.closeSubpath()
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
