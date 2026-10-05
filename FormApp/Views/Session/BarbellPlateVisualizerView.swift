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
    @ScaledMetric(relativeTo: .caption) private var chipSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var summarySize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var totalSize: CGFloat = 13

    public init(result: PlateCalculationResult, unit: WeightUnit = .kg) {
        self.result = result
        self.unit = unit
    }

    public var body: some View {
        VStack(spacing: 14) {
            barbellDiagram

            // Plate breakdown chips
            if !result.platesPerSide.isEmpty {
                PlateInfoFlow(spacing: 6) {
                    Text("\(LanguageManager.t("warmup.per_side")):")
                        .font(.system(size: summarySize, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)

                    ForEach(Array(result.platesPerSide.enumerated()), id: \.offset) { _, plate in
                        let color = BarbellPlateColors.colorFor(weight: plate.weight)
                        let label = "\(plate.count)×\(WarmupPlateEngine.formatPlateWeight(plate.weight))\(unit.label)"

                        HStack(spacing: 4) {
                            Circle()
                                .fill(color)
                                .frame(width: 7, height: 7)

                            Text(label)
                                .font(.system(size: chipSize, weight: .semibold))
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

            // Summary row
            PlateInfoFlow(spacing: 12) {
                Text("\(LanguageManager.t("warmup.bar")): \(WarmupPlateEngine.formatPlateWeight(result.barWeight)) \(unit.label)")
                    .font(.system(size: summarySize))
                    .foregroundColor(AppColors.muted)

                Text("\(LanguageManager.t("warmup.plates_total")): \(WarmupPlateEngine.formatPlateWeight(result.totalPlatesWeight)) \(unit.label)")
                    .font(.system(size: summarySize))
                    .foregroundColor(AppColors.muted)

                Text("\(LanguageManager.t("warmup.total")): \(WarmupPlateEngine.formatPlateWeight(result.totalAchievedWeight)) \(unit.label)")
                    .font(.system(size: totalSize, weight: .bold))
                    .foregroundColor(result.isExactMatch ? AppColors.accent : AppColors.warmupAmber)
            }

            if !result.isExactMatch && result.remainderPerSide > 0 {
                let remainderStr = "\(WarmupPlateEngine.formatPlateWeight(result.remainderPerSide * 2.0)) \(unit.label)"
                let nearestStr = "\(WarmupPlateEngine.formatPlateWeight(result.totalAchievedWeight)) \(unit.label)"
                Text(LanguageManager.t("warmup.unmatched_remainder", ["remainder": remainderStr, "nearest": nearestStr]))
                    .font(.system(size: chipSize))
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

    private var barbellDiagram: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let edge: CGFloat = 12
            let minimumGripWidth = max(48, size.width * 0.26)
            let sleeveInnerLimit = (size.width - minimumGripWidth) / 2
            let count = result.platesPerSide.reduce(0) { $0 + $1.count }
            let stackWidth = result.platesPerSide.reduce(CGFloat(0)) {
                $0 + BarbellPlateColors.widthFor(weight: $1.weight) * CGFloat($1.count)
            } + CGFloat(max(0, count - 1)) * 2
            // Fit every plate on both sleeves while leaving the center grip visible.
            let scale = stackWidth > 0 ? min(1, (sleeveInnerLimit - edge) / stackWidth) : 1
            // Short stacks sit near the ends; fuller sleeves keep the existing grip spacing.
            let leftInner = count > 0 ? min(sleeveInnerLimit, edge + 12 + stackWidth * scale) : sleeveInnerLimit
            let rightInner = size.width - leftInner

            context.fill(
                Path(roundedRect: CGRect(x: edge, y: centerY - 3, width: size.width - 2 * edge, height: 6), cornerRadius: 2),
                with: .color(AppColors.muted)
            )
            for start in [edge, rightInner] {
                context.fill(
                    Path(roundedRect: CGRect(x: start, y: centerY - 5, width: leftInner - edge, height: 10), cornerRadius: 2),
                    with: .color(AppColors.secondaryText.opacity(0.65))
                )
            }

            var distance: CGFloat = 0
            for plate in result.platesPerSide {
                let width = BarbellPlateColors.widthFor(weight: plate.weight) * scale
                let height = BarbellPlateColors.heightFor(weight: plate.weight) * scale
                let label = WarmupPlateEngine.formatPlateWeight(plate.weight)
                let text = context.resolve(Text(label)
                    .font(.system(size: label.count > 2 ? 7 : 8.5, weight: .bold))
                    .foregroundColor(BarbellPlateColors.textColorFor(weight: plate.weight)))
                let textSize = text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                for _ in 0..<plate.count {
                    for x in [leftInner - distance - width, rightInner + distance] {
                        context.fill(
                            Path(roundedRect: CGRect(x: x, y: centerY - height / 2, width: width, height: height), cornerRadius: 3 * scale),
                            with: .color(BarbellPlateColors.colorFor(weight: plate.weight))
                        )
                        if textSize.width + 2 <= width && textSize.height <= height {
                            context.draw(text, at: CGPoint(x: x + width / 2, y: centerY))
                        }
                    }
                    distance += width + 2 * scale
                }
            }
        }
        .frame(height: 118)
        .background(AppColors.background)
        .overlay(alignment: .bottom) {
            if result.platesPerSide.isEmpty {
                Text(LanguageManager.t("warmup.empty_bar_sleeve"))
                    .font(.system(size: chipSize, weight: .semibold))
                    .foregroundColor(AppColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

// Wrap the breakdown and totals without shrinking translated or larger text.
private struct PlateInfoFlow: Layout {
    var spacing: CGFloat

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if !row.items.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            if !row.items.isEmpty { row.width += spacing }
            row.items.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * 6
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + 6
        }
    }
}
