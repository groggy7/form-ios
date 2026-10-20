import SwiftUI

private func formatBodyDate(_ date: String) -> String {
    guard let parsed = WorkoutCalendar.parseDate(date) else { return date }
    let formatter = DateFormatter()
    formatter.locale = LanguageManager.locale
    formatter.dateStyle = .medium
    return formatter.string(from: parsed)
}

private func unitLabel(_ metric: BodyMetric, _ unit: WeightUnit) -> String {
    metric.isLength ? LanguageManager.t(BodyUnits.lengthLabelKey(unit)) : unit.label
}

private func formatValue(_ metric: BodyMetric, _ canonical: Double, _ unit: WeightUnit) -> String {
    "\(BodyUnits.formatCanonical(metric, canonical, unit: unit)) \(unitLabel(metric, unit))"
}

/// A signed change in display units, with a true minus sign.
private func formatChange(_ metric: BodyMetric, _ canonicalChange: Double, _ unit: WeightUnit) -> String {
    let display = BodyUnits.format(BodyUnits.toDisplay(metric, abs(canonicalChange), unit: unit))
    let sign = display == "0" ? "" : canonicalChange > 0 ? "+" : "−"
    return sign + display
}

/// Progress → Calendar's entry point: the latest bodyweight, or a prompt to log the first one.
struct BodySummaryCard: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let entries: [BodyEntry]
    let weightUnit: WeightUnit
    let onOpen: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        let latestWeight = entries.last { $0.bodyweightKg != nil }
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: "scalemass")
                    .font(.system(size: 20)).foregroundStyle(AppColors.secondaryText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("body.title")).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
                    if let latestWeight, let kg = latestWeight.bodyweightKg {
                        Text(formatValue(.bodyweight, kg, weightUnit)).font(.system(size: 18, weight: .semibold)).foregroundStyle(AppColors.text)
                        Text(LanguageManager.t("body.card.lastLogged", ["date": formatBodyDate(latestWeight.date)]))
                            .font(.system(size: 12)).foregroundStyle(AppColors.muted)
                    } else if let latest = entries.last {
                        Text(LanguageManager.t("body.card.lastLogged", ["date": formatBodyDate(latest.date)]))
                            .font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                    } else {
                        Text(LanguageManager.t("body.card.empty")).font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(LanguageManager.t("body.log"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("body-card")
    }
}

/// The body log (docs/design/body-and-joint-journal.md): free logging, Pro trend and relative strength.
struct BodyLogView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject private var proManager = ProAccessManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var date: String = BodyDay.today()
    @State private var inputs: [BodyMetric: String] = [:]
    @State private var loadedDate: String?
    @State private var showMeasurements = false
    @State private var error: String?
    @State private var saved = false
    @State private var confirmDelete = false
    @State private var showPaywall = false

    private var today: String { BodyDay.today() }
    private var entries: [BodyEntry] { store.state.bodyEntries ?? [] }
    private var existing: BodyEntry? { entries.first { $0.date == date } }
    private var unit: WeightUnit { store.weightUnit }
    private var trendsUnlocked: Bool { proManager.isFeatureUnlocked(.bodyTrends) }

    var body: some View {
        let _ = themeManager.currentTheme
        let report = trendsUnlocked ? BodyTrends.report(entries: entries, history: store.state.history, today: today) : nil
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        logCard.id("log")
                        if let report {
                            trendCard(report)
                            strengthCard(report.relativeStrength)
                        } else {
                            lockedCard(title: "body.trend.title", identifier: "body-trend-locked")
                            lockedCard(title: "body.strength.title", identifier: "body-strength-locked")
                        }
                        Text(LanguageManager.t("body.entries")).font(.system(size: 17, weight: .semibold)).foregroundStyle(AppColors.text)
                            .padding(.top, 6)
                        if entries.isEmpty {
                            Text(LanguageManager.t("body.noEntries")).font(.system(size: 13)).foregroundStyle(AppColors.muted)
                        }
                        ForEach(entries.reversed()) { entry in
                            entryRow(entry) {
                                select(entry.date)
                                withAnimation { proxy.scrollTo("log", anchor: .top) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("body.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { FormCloseToolbarItem(accessibilityIdentifier: "body-close") { dismiss() } }
        }
        .accessibilityIdentifier("body-screen")
        .onAppear { syncForm() }
        .onChange(of: date) { _, _ in syncForm() }
        .onChange(of: existing) { _, _ in syncForm() }
        .alert(LanguageManager.t("body.deleteTitle"), isPresented: $confirmDelete) {
            Button(LanguageManager.t("modal.delete"), role: .destructive) {
                if store.deleteBodyEntry(date: date) {
                    inputs = [:]
                    loadedDate = nil
                    date = today
                }
            }
            Button(LanguageManager.t("modal.cancel"), role: .cancel) {}
        } message: {
            Text(LanguageManager.t("body.deleteMessage", ["date": formatBodyDate(date)]))
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallSheet(feature: .bodyTrends, onDismiss: { showPaywall = false })
        }
    }

    // MARK: Log

    /// A date with an entry loads it for editing; leaving it clears the form again.
    private func syncForm() {
        if let existing, loadedDate != date {
            var loaded: [BodyMetric: String] = [:]
            for metric in BodyMetric.allCases {
                if let value = existing.value(metric) { loaded[metric] = BodyUnits.formatCanonical(metric, value, unit: unit) }
            }
            inputs = loaded
            if BodyMetric.measurements.contains(where: { existing.value($0) != nil }) { showMeasurements = true }
            loadedDate = date
        } else if existing == nil && loadedDate != nil {
            inputs = [:]
            loadedDate = nil
        }
    }

    private func select(_ newDate: String) {
        date = newDate
        error = nil
        saved = false
    }

    private func buildEntry() -> (BodyEntry?, String?) {
        var entry = BodyEntry(date: date)
        for metric in BodyMetric.allCases {
            let text = (inputs[metric] ?? "").trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            let original = existing?.value(metric)
            // An untouched field keeps its stored value, so unit conversion never drifts it.
            let canonical: Double?
            if let original, text == BodyUnits.formatCanonical(metric, original, unit: unit) {
                canonical = original
            } else {
                canonical = BodyUnits.parse(text).map { BodyUnits.toCanonical(metric, $0, unit: unit) }
            }
            guard let canonical, metric.canonicalRange.contains(canonical) else {
                let (low, high) = BodyUnits.displayRange(metric, unit: unit)
                let label = unitLabel(metric, unit)
                return (nil, metric == .bodyweight
                    ? LanguageManager.t("body.invalidBodyweight", ["min": low, "max": high, "unit": label])
                    : LanguageManager.t("body.invalidMeasurement", ["name": LanguageManager.t(metric.labelKey), "min": low, "max": high, "unit": label]))
            }
            entry = entry.with(metric, canonical)
        }
        return entry.hasValue ? (entry, nil) : (nil, LanguageManager.t("body.emptyEntry"))
    }

    private func save() {
        let (entry, problem) = buildEntry()
        error = problem
        guard let entry else { return }
        if store.saveBodyEntry(entry) {
            loadedDate = nil
            syncForm()
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { saved = false }
        } else {
            error = LanguageManager.t("body.saveFailed")
        }
    }

    private var logCard: some View {
        card(title: LanguageManager.t(existing != nil ? "body.editTitle" : "body.logTitle"), identifier: "body-log") {
            dateStepper
            if existing != nil {
                Text(LanguageManager.t("body.replaceNotice", ["date": formatBodyDate(date)]))
                    .font(.system(size: 12)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-replace-notice")
            }
            field(.bodyweight)
            Button { showMeasurements.toggle() } label: {
                Text(LanguageManager.t(showMeasurements ? "body.hideMeasurements" : "body.showMeasurements"))
                    .font(.system(size: 13)).foregroundStyle(AppColors.secondaryText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-toggle-measurements")
            if showMeasurements {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 10) {
                        field(BodyMetric.measurements[row * 2])
                        field(BodyMetric.measurements[row * 2 + 1])
                    }
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(AppColors.danger).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-error")
            }
            Button(action: save) {
                Text(LanguageManager.t("body.save"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-save")
            if saved {
                Text(LanguageManager.t("body.saved")).font(.system(size: 12)).foregroundStyle(AppColors.accent)
                    .accessibilityIdentifier("body-saved")
            }
            if existing != nil {
                HStack(spacing: 16) {
                    if date != today {
                        Button(LanguageManager.t("body.cancelEdit")) { select(today) }
                            .font(.system(size: 13)).foregroundStyle(AppColors.secondaryText).frame(minHeight: 44)
                    }
                    Button(LanguageManager.t("body.deleteEntry")) { confirmDelete = true }
                        .font(.system(size: 13)).foregroundStyle(AppColors.danger).frame(minHeight: 44)
                        .accessibilityIdentifier("body-delete")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateStepper: some View {
        let number = BodyDay.number(date) ?? BodyDay.number(today) ?? 0
        let todayNumber = BodyDay.number(today) ?? number
        let canGoForward = number < todayNumber
        return HStack(spacing: 0) {
            Button { select(BodyDay.string(number - 1)) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.secondaryText)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LanguageManager.t("body.previousDay"))
            .accessibilityIdentifier("body-date-previous")
            VStack(spacing: 1) {
                Text(LanguageManager.t("body.date")).font(.system(size: 11)).foregroundStyle(AppColors.muted)
                Text(date == today ? LanguageManager.t("nav.today") : formatBodyDate(date))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    .accessibilityIdentifier("body-date")
            }
            .frame(maxWidth: .infinity)
            Button { select(BodyDay.string(number + 1)) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGoForward ? AppColors.secondaryText : AppColors.muted.opacity(0.3))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel(LanguageManager.t("body.nextDay"))
            .accessibilityIdentifier("body-date-next")
        }
        .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }

    private func field(_ metric: BodyMetric) -> some View {
        let binding = Binding<String>(
            get: { inputs[metric] ?? "" },
            set: { text in
                guard text.range(of: #"^\d{0,4}([.,]\d?)?$"#, options: .regularExpression) != nil else { return }
                inputs[metric] = text
                error = nil
                saved = false
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(LanguageManager.t(metric.labelKey)) (\(unitLabel(metric, unit)))")
                .font(.system(size: 12)).foregroundStyle(AppColors.muted).lineLimit(1)
            TextField("", text: binding)
                .keyboardType(.decimalPad)
                .font(.system(size: 16, weight: .medium)).foregroundStyle(AppColors.text)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                .accessibilityLabel(LanguageManager.t(metric.labelKey))
                .accessibilityIdentifier("body-input-\(metric.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pro cards

    private func lockedCard(title: String, identifier: String) -> some View {
        card(title: LanguageManager.t(title), identifier: identifier, trailing: AnyView(ProBadge())) {
            Text(LanguageManager.t("body.locked")).font(.system(size: 13)).lineSpacing(3).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button { showPaywall = true } label: {
                Text(LanguageManager.t("body.unlock"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func trendCard(_ report: BodyTrendReport) -> some View {
        card(title: LanguageManager.t("body.trend.title"), identifier: "body-trend") {
            Text(LanguageManager.t("body.trend.subtitle")).font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let latest = report.latest {
                HStack(alignment: .top, spacing: 10) {
                    tile(LanguageManager.t("body.trend.current"), formatValue(.bodyweight, latest.trendKg, unit), muted: false)
                        .accessibilityIdentifier("body-trend-value")
                    tile(LanguageManager.t("body.trend.weekly"),
                         report.weeklyChangeKg.map { LanguageManager.t("body.trend.perWeek", ["value": formatChange(.bodyweight, $0, unit), "unit": unit.label]) }
                            ?? LanguageManager.t("body.trend.needMore"),
                         muted: report.weeklyChangeKg == nil)
                        .accessibilityIdentifier("body-trend-weekly")
                }
                .fixedSize(horizontal: false, vertical: true)
                let todayNumber = BodyDay.number(today) ?? 0
                let chartPoints = report.points.filter { (BodyDay.number($0.date)).map { todayNumber - $0 < BodyTrends.chartDays } ?? false }
                if chartPoints.count >= 2 { chart(chartPoints) }
                if !report.measurements.isEmpty {
                    Text(LanguageManager.t("body.trend.measurements")).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                        .padding(.top, 4)
                    ForEach(report.measurements, id: \.metric) { change in
                        HStack(alignment: .top) {
                            Text(LanguageManager.t(change.metric.labelKey)).font(.system(size: 13)).foregroundStyle(AppColors.secondaryText)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatValue(change.metric, change.latestCm, unit)).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                                Text(LanguageManager.t("body.trend.since", [
                                    "change": "\(formatChange(change.metric, change.changeCm, unit)) \(unitLabel(change.metric, unit))",
                                    "date": formatBodyDate(change.since)]))
                                    .font(.system(size: 11)).foregroundStyle(AppColors.muted)
                            }
                        }
                    }
                }
            } else {
                Text(LanguageManager.t("body.trend.noData")).font(.system(size: 13)).foregroundStyle(AppColors.muted)
            }
        }
    }

    private func tile(_ title: String, _ value: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(AppColors.muted)
            Text(value).font(.system(size: muted ? 12 : 17, weight: muted ? .regular : .semibold))
                .foregroundStyle(muted ? AppColors.secondaryText : AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }

    private func chart(_ points: [BodyTrendPoint]) -> some View {
        let values = points.flatMap { [$0.weightKg, $0.trendKg] }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 1)
        let todayNumber = BodyDay.number(today) ?? 0
        let start = todayNumber - (BodyTrends.chartDays - 1)
        let days = Double(BodyTrends.chartDays - 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(formatValue(.bodyweight, high, unit)).font(.system(size: 10)).foregroundStyle(AppColors.muted)
            GeometryReader { geometry in
                let size = geometry.size
                let positions = points.compactMap { point -> (CGPoint, CGPoint)? in
                    guard let day = BodyDay.number(point.date) else { return nil }
                    let x = CGFloat(Double(day - start) / days) * size.width
                    func y(_ kg: Double) -> CGFloat { size.height - CGFloat((kg - low) / span) * size.height }
                    return (CGPoint(x: x, y: y(point.weightKg)), CGPoint(x: x, y: y(point.trendKg)))
                }
                ZStack {
                    ForEach(Array(positions.enumerated()), id: \.offset) { _, position in
                        Circle().fill(AppColors.secondaryText.opacity(0.7)).frame(width: 5, height: 5).position(position.0)
                    }
                    Path { path in
                        for (index, position) in positions.enumerated() {
                            if index == 0 { path.move(to: position.1) } else { path.addLine(to: position.1) }
                        }
                    }
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 120)
            .accessibilityElement()
            .accessibilityLabel(LanguageManager.t("body.trend.chartLabel"))
            .accessibilityIdentifier("body-trend-chart")
            HStack {
                Text(formatValue(.bodyweight, low, unit)).font(.system(size: 10)).foregroundStyle(AppColors.muted)
                Spacer()
                Text(formatBodyDate(BodyDay.string(start)) + " – " + formatBodyDate(today)).font(.system(size: 10)).foregroundStyle(AppColors.muted)
            }
        }
    }

    private func strengthCard(_ report: RelativeStrengthReport) -> some View {
        card(title: LanguageManager.t("body.strength.title"), identifier: "body-strength") {
            Text(LanguageManager.t("body.strength.subtitle")).font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            switch report {
            case .needsWeighIn:
                Text(LanguageManager.t("body.strength.needWeighIn")).font(.system(size: 13)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .noLifts:
                Text(LanguageManager.t("body.strength.noLifts")).font(.system(size: 13)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .rows(_, let rows):
                ForEach(rows, id: \.exerciseName) { row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: row.exerciseName))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LanguageManager.t("body.strength.estimate", ["weight": "\(unit.formatDisplayWeight(row.estimated1RmKg)) \(unit.label)"]))
                                .font(.system(size: 11)).foregroundStyle(AppColors.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(LanguageManager.t("body.strength.ratio", ["ratio": String(format: "%.2f", locale: LanguageManager.locale, row.ratio)]))
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("body-strength-row")
                }
            }
        }
    }

    // MARK: Entries

    private func entryRow(_ entry: BodyEntry, onTap: @escaping () -> Void) -> some View {
        let measurements = BodyMetric.measurements.compactMap { metric in
            entry.value(metric).map { "\(LanguageManager.t(metric.labelKey)) \(BodyUnits.formatCanonical(metric, $0, unit: unit))" }
        }
        let selected = entry.date == date
        return Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBodyDate(entry.date)).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    if !measurements.isEmpty {
                        Text(measurements.joined(separator: " · ") + " " + LanguageManager.t(BodyUnits.lengthLabelKey(unit)))
                            .font(.system(size: 12)).foregroundStyle(AppColors.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let kg = entry.bodyweightKg {
                    Text(formatValue(.bodyweight, kg, unit)).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("body-entry-\(entry.date)")
    }

    private func card<Content: View>(title: String, identifier: String, trailing: AnyView? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing { trailing }
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
