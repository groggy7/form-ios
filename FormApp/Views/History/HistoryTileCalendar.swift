import SwiftUI

/// Card corner of the tiled calendar, also used by its tour highlight.
let tileCalendarCornerRadius: CGFloat = 16

// Proportions measured from the supplied reference (docs/design/form-design-system.md, "History calendar styles").
private let tileGapFraction: CGFloat = 0.0177
private let tileCornerFraction: CGFloat = 0.177
private let legendCornerFraction: CGFloat = 0.25
private let tileGlowSteps = 6

/// Optional Progress calendar style: every date is a rounded tile, status days are lit from their rim,
/// today has a separated ring and the legend sits inside the card. Navigation and selection behave
/// exactly like the classic pill calendar.
struct HistoryTileCalendarCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let monthTitle: String
    let weekdaySymbols: [String]
    let weeks: [[Date?]]
    let todayStr: String
    let statuses: [String: WorkoutDayStatus]
    let selectedDateString: String?
    let canGoBack: Bool
    let canGoForward: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onSelectDay: (String) -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    monthButton("chevron.left", label: LanguageManager.t("history.previousMonth"),
                        enabled: canGoBack, action: onPreviousMonth)
                    Text(monthTitle)
                        .font(.app(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    monthButton("chevron.right", label: LanguageManager.t("history.nextMonth"),
                        enabled: canGoForward, action: onNextMonth)
                }
                Spacer().frame(height: 10)
                TileGridLayout(square: false) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.app(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer().frame(height: 8)
                TileGridLayout(square: true) {
                    ForEach(Array(weeks.joined().enumerated()), id: \.offset) { _, date in
                        TileDayCell(date: date, todayStr: todayStr, statuses: statuses,
                            selectedDateString: selectedDateString, onSelectDay: onSelectDay)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer().frame(height: 18)
            Rectangle()
                .fill(LinearGradient(stops: [
                    .init(color: AppColors.border.opacity(0.25), location: 0),
                    .init(color: AppColors.border.opacity(0.9), location: 0.5),
                    .init(color: AppColors.border.opacity(0.25), location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)

            // Whole entries wrap onto a second line when one row does not fit (narrow widths, larger text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    Spacer(minLength: 8)
                    legendItems
                }
                VStack(alignment: .leading, spacing: 10) {
                    legendItem(AppColors.calendarCompletedTile, label: LanguageManager.t("history.completed"))
                    legendItem(AppColors.calendarUnfinishedTile, label: LanguageManager.t("history.unfinished"))
                    legendItem(AppColors.calendarMissedTile, label: LanguageManager.t("history.missed"))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("history-calendar-legend")
        }
        .background(
            RoundedRectangle(cornerRadius: tileCalendarCornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [AppColors.calendarSurfaceStart, AppColors.calendarSurfaceEnd],
                    startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: tileCalendarCornerRadius, style: .continuous)
                        .strokeBorder(AppColors.border.opacity(0.7), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-calendar-tiles")
    }

    @ViewBuilder
    private var legendItems: some View {
        legendItem(AppColors.calendarCompletedTile, label: LanguageManager.t("history.completed"))
        Spacer(minLength: 8)
        legendItem(AppColors.calendarUnfinishedTile, label: LanguageManager.t("history.unfinished"))
        Spacer(minLength: 8)
        legendItem(AppColors.calendarMissedTile, label: LanguageManager.t("history.missed"))
        Spacer(minLength: 8)
    }

    private func legendItem(_ colors: AppColors.CalendarTileColors, label: String) -> some View {
        HStack(spacing: 10) {
            CalendarTileMaterial(colors: colors, selected: false, ring: nil, legend: true)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.app(size: 13))
                .foregroundStyle(AppColors.text.opacity(0.88))
                .fixedSize()
        }
    }

    private func monthButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? AppColors.text.opacity(0.88) : AppColors.muted.opacity(0.3))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.surfaceRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(AppColors.border, lineWidth: 1)
                        )
                )
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Seven equal columns separated by 1.77% of the width; rows of tiles are square and spaced 1.2× the gap.
private struct TileGridLayout: Layout {
    var square: Bool

    private func metrics(_ width: CGFloat) -> (tile: CGFloat, gap: CGFloat) {
        let gap = width * tileGapFraction
        return ((width - gap * 6) / 7, gap)
    }

    private func rowHeight(tile: CGFloat, subviews: Subviews) -> CGFloat {
        square ? tile : subviews.map { $0.sizeThatFits(ProposedViewSize(width: tile, height: nil)).height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 353
        let (tile, gap) = metrics(width)
        let rows = (subviews.count + 6) / 7
        let height = rowHeight(tile: tile, subviews: subviews)
        return CGSize(width: width, height: CGFloat(rows) * height + CGFloat(max(rows - 1, 0)) * gap * 1.2)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (tile, gap) = metrics(bounds.width)
        let height = rowHeight(tile: tile, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let column = CGFloat(index % 7)
            let row = CGFloat(index / 7)
            subview.place(at: CGPoint(x: bounds.minX + column * (tile + gap), y: bounds.minY + row * (height + gap * 1.2)),
                proposal: ProposedViewSize(width: tile, height: height))
        }
    }
}

private struct TileDayCell: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let date: Date?
    let todayStr: String
    let statuses: [String: WorkoutDayStatus]
    let selectedDateString: String?
    let onSelectDay: (String) -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        if let date {
            let dateString = WorkoutCalendar.formatDate(date)
            let status = statuses[dateString]
            let isToday = dateString == todayStr
            let isSelected = dateString == selectedDateString
            let colors = Self.colors(for: status)
            let ring: Color? = !isToday ? nil : (status != nil ? colors.ink : AppColors.calendarTodayBorder)
            let ink: Color = status == nil && dateString > todayStr
                ? Color.mix(AppColors.secondaryText, AppColors.muted, 0.5) : colors.ink
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack {
                    CalendarTileMaterial(colors: colors, selected: isSelected, ring: ring)
                    // Numerals keep one line inside their fixed tile, shrinking only when large text would overflow it.
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.app(size: 16, weight: status != nil ? .bold : (isToday ? .semibold : .regular)))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 3)
                }
                .frame(width: width, height: geometry.size.height)
                .contentShape(RoundedRectangle(cornerRadius: width * tileCornerFraction, style: .continuous))
                .onTapGesture {
                    if status != nil { onSelectDay(dateString) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(historyCalendarDayLabel(date: date, dateString: dateString, todayStr: todayStr, status: status))
            .accessibilityAddTraits(status != nil ? (isSelected ? [.isButton, .isSelected] : .isButton) : [])
            .accessibilityIdentifier("history-day-\(dateString)")
        } else {
            // Days outside the month keep the grid's structure as blank tiles.
            CalendarTileMaterial(colors: AppColors.calendarNeutralTile, selected: false, ring: nil)
                .accessibilityHidden(true)
        }
    }

    private static func colors(for status: WorkoutDayStatus?) -> AppColors.CalendarTileColors {
        switch status {
        case .completed: return AppColors.calendarCompletedTile
        case .unfinished: return AppColors.calendarUnfinishedTile
        case .missed: return AppColors.calendarMissedTile
        case nil: return AppColors.calendarNeutralTile
        }
    }
}

/// The full date, its status and whether it is today, as the Android calendar announces them.
func historyCalendarDayLabel(date: Date, dateString: String, todayStr: String, status: WorkoutDayStatus?) -> String {
    let formatter = DateFormatter()
    formatter.locale = LanguageManager.locale
    formatter.dateStyle = .full
    let statusLabel: String
    switch status {
    case .completed: statusLabel = LanguageManager.t("history.completed")
    case .unfinished: statusLabel = LanguageManager.t("history.unfinished")
    case .missed: statusLabel = LanguageManager.t("history.missed")
    case nil: statusLabel = LanguageManager.t(dateString > todayStr ? "history.future" : "history.neutral")
    }
    let today = dateString == todayStr ? ", \(LanguageManager.t("nav.today"))" : ""
    return "\(formatter.string(from: date)), \(statusLabel)\(today)"
}

/// Tile material: a vertical fill, an inner glow that fades in from the rim, and the rim itself.
/// Selection lights the rim in the tile's ink; today adds a ring outside the tile, separated by a gap.
struct CalendarTileMaterial: View {
    let colors: AppColors.CalendarTileColors
    let selected: Bool
    let ring: Color?
    var legend = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let radius = width * (legend ? legendCornerFraction : tileCornerFraction)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let rimWidth: CGFloat = selected ? 1.5 : (legend ? 1.25 : max(1 / UIScreen.main.scale, width * 0.022))
            let rim: Color = selected ? colors.ink : (legend ? Color.mix(colors.rim, colors.ink, 0.55) : colors.rim)
            let glowReach = width * (selected ? 0.11 : 0.075)
            let glowPeak: Double = selected ? 1 : 0.65
            let band = glowReach / CGFloat(tileGlowSteps)
            let ringWidth = max(1.5, width * 0.04)
            let ringOffset = max(1, width * 0.027) + ringWidth / 2
            ZStack {
                // Legend swatches are a little brighter so the small squares read at a glance, as in the reference.
                shape.fill(LinearGradient(colors: legend
                    ? [Color.mix(colors.fillTop, colors.rim, 0.3), Color.mix(colors.fillBottom, colors.rim, 0.3)]
                    : [colors.fillTop, colors.fillBottom], startPoint: .top, endPoint: .bottom))
                // Equal bands fade the glow linearly from the rim towards the centre.
                ForEach(0..<tileGlowSteps, id: \.self) { step in
                    let inset = rimWidth + band * (CGFloat(step) + 0.5)
                    RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous)
                        .stroke(colors.glow.opacity(glowPeak * (1 - Double(step) / Double(tileGlowSteps))), lineWidth: band)
                        .frame(width: max(0, width - inset * 2), height: max(0, height - inset * 2))
                }
                shape.strokeBorder(rim, lineWidth: rimWidth)
                if let ring {
                    RoundedRectangle(cornerRadius: radius + ringOffset, style: .continuous)
                        .stroke(ring, lineWidth: ringWidth)
                        .frame(width: width + ringOffset * 2, height: height + ringOffset * 2)
                }
            }
            .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
