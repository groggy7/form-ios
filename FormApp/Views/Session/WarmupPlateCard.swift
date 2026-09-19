import SwiftUI

public struct WarmupPlateCard: View {
    let warmupSets: [ExerciseSetLog]
    var onGenerateWarmup: () -> Void
    var onOpenPlates: () -> Void
    var onClearWarmups: () -> Void

    public init(
        warmupSets: [ExerciseSetLog],
        onGenerateWarmup: @escaping () -> Void,
        onOpenPlates: @escaping () -> Void,
        onClearWarmups: @escaping () -> Void
    ) {
        self.warmupSets = warmupSets
        self.onGenerateWarmup = onGenerateWarmup
        self.onOpenPlates = onOpenPlates
        self.onClearWarmups = onClearWarmups
    }

    public var body: some View {
        if ProAccessManager.shared.isFeatureUnlocked(.warmupCalculator) {
            let hasWarmups = !warmupSets.isEmpty

            HStack(spacing: 10) {
                // Left Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hasWarmups ? AppColors.warmupAmberBg : AppColors.positiveBg)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(hasWarmups ? AppColors.warmupAmber.opacity(0.5) : AppColors.accent.opacity(0.4), lineWidth: 1)
                        )

                    Image(systemName: hasWarmups ? "flame.fill" : "dumbbell.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hasWarmups ? AppColors.warmupAmber : AppColors.accent)
                }

                // Text details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        ProBadge()
                        Text(hasWarmups ? LanguageManager.t("warmup.active_badge") : LanguageManager.t("warmup.card_title"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(hasWarmups ? AppColors.warmupAmber : AppColors.text)
                    }

                    Text(hasWarmups
                         ? LanguageManager.t("warmup.active_desc", ["count": warmupSets.count])
                         : LanguageManager.t("warmup.card_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                        .lineLimit(1)
                }

                Spacer()

                // Actions
                if !hasWarmups {
                    HStack(spacing: 6) {
                        // Generate button
                        Button(action: onGenerateWarmup) {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                Text(LanguageManager.t("warmup.generate_btn"))
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(AppColors.warmupAmber)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
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
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 34, height: 34)
                                .background(AppColors.surface)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LanguageManager.t("warmup.tab_plates"))
                    }
                } else {
                    HStack(spacing: 6) {
                        // Inspect Plates
                        Button(action: onOpenPlates) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LanguageManager.t("warmup.tab_plates"))

                        // Clear warmups
                        Button(action: onClearWarmups) {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.muted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LanguageManager.t("warmup.clear_warmups"))
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
