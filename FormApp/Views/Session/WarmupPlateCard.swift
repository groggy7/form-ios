import SwiftUI

public struct WarmupPlateCard: View {
    let warmupSets: [ExerciseSetLog]
    let hasWorkingLoad: Bool
    let supportsBarbellWarmup: Bool
    var onGenerateWarmup: () -> Void
    var onOpenPlates: () -> Void
    var onClearWarmups: () -> Void
    var onLockedClick: (() -> Void)? = nil
    var onDismissLocked: (() -> Void)? = nil

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var showInternalPaywall: Bool = false

    public init(
        warmupSets: [ExerciseSetLog],
        hasWorkingLoad: Bool = true,
        supportsBarbellWarmup: Bool = true,
        onGenerateWarmup: @escaping () -> Void,
        onOpenPlates: @escaping () -> Void,
        onClearWarmups: @escaping () -> Void,
        onLockedClick: (() -> Void)? = nil,
        onDismissLocked: (() -> Void)? = nil
    ) {
        self.warmupSets = warmupSets
        self.hasWorkingLoad = hasWorkingLoad
        self.supportsBarbellWarmup = supportsBarbellWarmup
        self.onGenerateWarmup = onGenerateWarmup
        self.onOpenPlates = onOpenPlates
        self.onClearWarmups = onClearWarmups
        self.onLockedClick = onLockedClick
        self.onDismissLocked = onDismissLocked
    }

    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var bodySize = 13.0

    public var body: some View {
        let isLocked = !proManager.isFeatureUnlocked(.warmupCalculator)
        if isLocked || warmupSets.isEmpty {
            introCard(isLocked: isLocked)
                .sheet(isPresented: $showInternalPaywall) {
                    ProPaywallSheet(feature: .warmupCalculator, onDismiss: { showInternalPaywall = false })
                }
        } else {
            let hasUncompletedWarmups = warmupSets.contains { !$0.isCompleted }
            VStack(spacing: 10) {
                // Active warmup sets row
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppColors.warmupAmberBg)
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.warmupAmber.opacity(0.5), lineWidth: 1)
                            )

                        Image(systemName: "flame.fill")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.warmupAmber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            ProBadge()
                            Text(LanguageManager.t("warmup.active_badge"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.warmupAmber)
                                .lineLimit(1)
                        }

                        Text(LanguageManager.t("warmup.active_desc", ["count": warmupSets.count]))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        if supportsBarbellWarmup && hasWorkingLoad { Button(action: onOpenPlates) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LanguageManager.t("warmup.tab_plates"))
                        }

                        if hasUncompletedWarmups {
                            Button(action: onClearWarmups) {
                                Image(systemName: "trash")
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.muted)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LanguageManager.t("warmup.clear_warmups"))
                            .accessibilityIdentifier("clear-warmup-sets")
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.warmupAmber.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("warmup-plate-card")
        }
    }

    private func openPaywall() {
        if let onLockedClick { onLockedClick() } else { showInternalPaywall = true }
    }

    private var title: some View {
        Text(LanguageManager.t("warmup.card_title"))
            .font(.system(size: titleSize, weight: .bold))
            .foregroundColor(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func introCard(isLocked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                HStack(spacing: 1) {
                    Capsule().frame(width: 2.5, height: 9)
                    Capsule().frame(width: 3.5, height: 15)
                    Rectangle().frame(width: 8, height: 3)
                    Capsule().frame(width: 3.5, height: 15)
                    Capsule().frame(width: 2.5, height: 9)
                }
                .foregroundColor(AppColors.accent)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title; ProBadge() }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { title; ProBadge() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isLocked, let onDismissLocked {
                    Button(action: onDismissLocked) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LanguageManager.t("common.close"))
                    .accessibilityIdentifier("dismiss-warmup-card")
                    .frame(width: 24, height: 24)
                }
            }
            Text(LanguageManager.t(!isLocked && !hasWorkingLoad ? "warmup.enter_working_load" : "warmup.card_desc"))
                .font(.system(size: bodySize))
                .foregroundColor(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            if isLocked || hasWorkingLoad {
                WarmupPlateActionsLayout {
                    WarmupPlateAction(warmup: true, action: isLocked ? openPaywall : onGenerateWarmup)
                    WarmupPlateAction(warmup: false, action: isLocked ? openPaywall : onOpenPlates)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityIdentifier("warmup-plate-card")
    }
}

private struct WarmupPlateAction: View {
    let warmup: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var labelSize = 13.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: warmup ? "flame.fill" : "square.stack.3d.up.fill")
                    .font(.system(size: 16))
                    .frame(width: 16, height: 18)
                    .foregroundColor(warmup ? AppColors.warmupAmber : AppColors.secondaryText)
                    .accessibilityHidden(true)
                Text(LanguageManager.t(warmup ? "warmup.generate_btn" : "warmup.plates_btn"))
                    .font(.system(size: labelSize, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(warmup ? AppColors.warmupAmber : AppColors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(warmup ? AppColors.warmupAmberBg : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(warmup ? AppColors.warmupAmber.opacity(0.7) : AppColors.secondaryText.opacity(0.35), lineWidth: 1))
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(warmup ? "generate-warmup-sets" : "open-plate-calculator")
    }
}

private struct WarmupPlateActionsLayout: Layout {
    private func dimensions(width: CGFloat, subviews: Subviews) -> (stacked: Bool, widths: [CGFloat], height: CGFloat) {
        let idealWidths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let availableWidth = max(0, width - 8)
        let stacked = idealWidths.reduce(0, +) > availableWidth
        let firstWidth = min(max(availableWidth / 2, idealWidths[0]), availableWidth - idealWidths[1])
        let widths = stacked ? [width, width] : [firstWidth, availableWidth - firstWidth]
        let heights = subviews.enumerated().map { index, view in
            view.sizeThatFits(ProposedViewSize(width: widths[index], height: nil)).height
        }
        return (stacked, widths, stacked ? heights.reduce(0, +) + 8 : heights.max() ?? 48)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + 8
        return CGSize(width: width, height: dimensions(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = dimensions(width: bounds.width, subviews: subviews)
        var x = bounds.minX
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let buttonWidth = layout.widths[index]
            let height = layout.stacked
                ? subview.sizeThatFits(ProposedViewSize(width: buttonWidth, height: nil)).height : layout.height
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                proposal: ProposedViewSize(width: buttonWidth, height: height))
            if layout.stacked { y += height + 8 }
            else { x += buttonWidth + 8 }
        }
    }
}
