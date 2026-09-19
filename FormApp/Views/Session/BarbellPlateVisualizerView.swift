import SwiftUI

public enum BarbellPlateColors {
    public static func colorFor(weight: Double) -> Color {
        switch weight {
        case 24.0...:
            return Color(hex: 0xDC2626) // 25kg / 55lb Red
        case 19.0...:
            return Color(hex: 0x2563EB) // 20kg / 45lb Blue
        case 14.0...:
            return Color(hex: 0xEAB308) // 15kg / 35lb Yellow
        case 9.0...:
            return Color(hex: 0x16A34A) // 10kg / 25lb Green
        case 4.0...:
            return Color(hex: 0xE2E8F0) // 5kg / 10lb White / Silver
        case 2.0...:
            return Color(hex: 0x334155) // 2.5kg / 5lb Dark Slate
        default:
            return Color(hex: 0x94A3B8) // 1.25kg / 2.5lb Chrome
        }
    }

    public static func textColorFor(weight: Double) -> Color {
        if weight >= 14.0 && weight < 19.0 {
            return Color(hex: 0x1A1A1A) // Dark text on yellow
        } else if weight >= 4.0 && weight < 9.0 {
            return Color(hex: 0x1A1A1A) // Dark text on white
        }
        return .white
    }

    public static func heightFor(weight: Double) -> CGFloat {
        switch weight {
        case 19.0...:
            return 96
        case 14.0...:
            return 82
        case 9.0...:
            return 70
        case 4.0...:
            return 56
        case 2.0...:
            return 44
        default:
            return 36
        }
    }

    public static func widthFor(weight: Double) -> CGFloat {
        switch weight {
        case 24.0...:
            return 22
        case 19.0...:
            return 20
        case 14.0...:
            return 17
        case 9.0...:
            return 15
        case 4.0...:
            return 13
        case 2.0...:
            return 11
        default:
            return 9
        }
    }
}

public struct BarbellPlateVisualizerView: View {
    public let result: PlateCalculationResult
    public var unit: WeightUnit = .kg

    public init(result: PlateCalculationResult, unit: WeightUnit = .kg) {
        self.result = result
        self.unit = unit
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Sleeve Graphic Container
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0x0C1014))
                    .frame(height: 118)

                // Horizontal bar shaft
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x26323D))
                    .frame(height: 20)
                    .padding(.horizontal, 16)

                // Plates stack aligned to the left of the sleeve
                HStack(spacing: 0) {
                    // Inner Barbell Collar / Stopper
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: 0x5A6672))
                        .frame(width: 12, height: 84)

                    Spacer().frame(width: 2)

                    if result.platesPerSide.isEmpty {
                        // Empty Bar Indicator
                        Text(LanguageManager.t("warmup.empty_bar_sleeve"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.muted.opacity(0.7))
                            .tracking(0.5)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // Loaded plates
                        HStack(spacing: 2) {
                            ForEach(Array(result.platesPerSide.enumerated()), id: \.offset) { _, plate in
                                ForEach(0..<plate.count, id: \.self) { _ in
                                    let h = BarbellPlateColors.heightFor(weight: plate.weight)
                                    let w = BarbellPlateColors.widthFor(weight: plate.weight)
                                    let bgColor = BarbellPlateColors.colorFor(weight: plate.weight)
                                    let fgColor = BarbellPlateColors.textColorFor(weight: plate.weight)
                                    let label = WarmupPlateEngine.formatPlateWeight(plate.weight)

                                    ZStack {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(bgColor)
                                            .frame(width: w, height: h)

                                        Text(label)
                                            .font(.system(size: label.count > 2 ? 7 : 8.5, weight: .bold))
                                            .foregroundColor(fgColor)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            // Spring Collar Clip
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color(hex: 0x8A9BA8))
                                .frame(width: 8, height: 34)
                                .padding(.leading, 2)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 24)
            }

            // Plate breakdown chips
            if !result.platesPerSide.isEmpty {
                HStack(spacing: 6) {
                    Text("\(LanguageManager.t("warmup.per_side")):")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(result.platesPerSide.enumerated()), id: \.offset) { _, plate in
                                let color = BarbellPlateColors.colorFor(weight: plate.weight)
                                let label = "\(plate.count)×\(WarmupPlateEngine.formatPlateWeight(plate.weight))\(unit.label)"

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 7, height: 7)

                                    Text(label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppColors.surface)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(color.opacity(0.5), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }

            // Summary row
            HStack {
                Text("\(LanguageManager.t("warmup.bar")): \(WarmupPlateEngine.formatPlateWeight(result.barWeight)) \(unit.label)")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.muted)

                Spacer()

                Text("\(LanguageManager.t("warmup.plates_total")): \(WarmupPlateEngine.formatPlateWeight(result.totalPlatesWeight)) \(unit.label)")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.muted)

                Spacer()

                Text("\(LanguageManager.t("warmup.total")): \(WarmupPlateEngine.formatPlateWeight(result.totalAchievedWeight)) \(unit.label)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(result.isExactMatch ? AppColors.accent : AppColors.warmupAmber)
            }

            if !result.isExactMatch && result.remainderPerSide > 0 {
                let remainderStr = "\(WarmupPlateEngine.formatPlateWeight(result.remainderPerSide * 2.0)) \(unit.label)"
                let nearestStr = "\(WarmupPlateEngine.formatPlateWeight(result.totalAchievedWeight)) \(unit.label)"
                Text(LanguageManager.t("warmup.unmatched_remainder", ["remainder": remainderStr, "nearest": nearestStr]))
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.warmupAmber)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }
}
