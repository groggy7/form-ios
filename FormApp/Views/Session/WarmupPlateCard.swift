import SwiftUI

public struct WarmupPlateCard: View {
    let warmupSets: [ExerciseSetLog]
    var onGenerateWarmup: () -> Void
    var onOpenPlates: () -> Void
    var onClearWarmups: () -> Void
    var onLockedClick: (() -> Void)? = nil
    var onDismissLocked: (() -> Void)? = nil

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var showInternalPaywall: Bool = false

    public init(
        warmupSets: [ExerciseSetLog],
        onGenerateWarmup: @escaping () -> Void,
        onOpenPlates: @escaping () -> Void,
        onClearWarmups: @escaping () -> Void,
        onLockedClick: (() -> Void)? = nil,
        onDismissLocked: (() -> Void)? = nil
    ) {
        self.warmupSets = warmupSets
        self.onGenerateWarmup = onGenerateWarmup
        self.onOpenPlates = onOpenPlates
        self.onClearWarmups = onClearWarmups
        self.onLockedClick = onLockedClick
        self.onDismissLocked = onDismissLocked
    }

    public var body: some View {
        if !proManager.isFeatureUnlocked(.warmupCalculator) {
            HStack(spacing: 6) {
                Button(action: {
                    if let onLockedClick = onLockedClick {
                        onLockedClick()
                    } else {
                        showInternalPaywall = true
                    }
                }) {
                    HStack(spacing: 10) {
                        // Left Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.purpleBg)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.purple.opacity(0.4), lineWidth: 1)
                                )

                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.purple)
                        }

                        // Text details
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text(LanguageManager.t("pro.warmup_calculator.title"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Text(LanguageManager.t("pro.warmup_calculator.teaser"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 2)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.purple)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onDismissLocked = onDismissLocked {
                    Button(action: onDismissLocked) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dismiss-warmup-card")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, onDismissLocked != nil ? 8 : 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppColors.purple.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("warmup-plate-card")
            .sheet(isPresented: $showInternalPaywall) {
                ProPaywallSheet(feature: .warmupCalculator, onDismiss: { showInternalPaywall = false })
            }
        } else {
            let hasWarmups = !warmupSets.isEmpty
            let hasUncompletedWarmups = warmupSets.contains { !$0.isCompleted }

            VStack(spacing: 10) {
                if !hasWarmups {
                    // Header row
                    Button(action: onOpenPlates) {
                        HStack(spacing: 10) {
                            // Left Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppColors.positiveBg)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
                                    )

                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.accent)
                            }

                            // Text details
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    ProBadge()
                                    Text(LanguageManager.t("warmup.card_title"))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppColors.text)
                                        .lineLimit(1)
                                }

                                Text(LanguageManager.t("warmup.card_desc"))
                                    .font(.system(size: 11))
                                    .foregroundColor(AppColors.muted)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                        }
                    }
                    .buttonStyle(.plain)

                    // Action buttons (50/50 split)
                    HStack(spacing: 8) {
                        // Generate button
                        Button(action: onGenerateWarmup) {
                            HStack(spacing: 6) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                Text(LanguageManager.t("warmup.generate_btn"))
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AppColors.warmupAmber)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppColors.warmupAmberBg)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.warmupAmber.opacity(0.6), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Plates button
                        Button(action: onOpenPlates) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 12))
                                Text(LanguageManager.t("warmup.tab_plates"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(AppColors.surface)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
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
                            Button(action: onOpenPlates) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LanguageManager.t("warmup.tab_plates"))

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
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(hasWarmups ? AppColors.warmupAmber.opacity(0.35) : AppColors.border, lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("warmup-plate-card")
        }
    }
}
