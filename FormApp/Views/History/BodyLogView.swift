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

/// Progress → Calendar's entry point: the latest bodyweight, or a prompt to log the first one. The card opens the
/// Body screen; Log opens a short sheet for today's weight.
struct BodySummaryCard: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let entries: [BodyEntry]
    let weightUnit: WeightUnit
    let onOpen: () -> Void
    var onLog: (() -> Void)? = nil

    var body: some View {
        let _ = themeManager.currentTheme
        let latestWeight = entries.last { $0.bodyweightKg != nil }
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 20)).foregroundStyle(AppColors.secondaryText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(LanguageManager.t("body.title")).font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppColors.muted)
                        }
                        if let latestWeight, let kg = latestWeight.bodyweightKg {
                            Text(formatValue(.bodyweight, kg, weightUnit)).font(.app(size: 18, weight: .semibold)).foregroundStyle(AppColors.text)
                            Text(LanguageManager.t("body.card.lastLogged", ["date": formatBodyDate(latestWeight.date)]))
                                .font(.app(size: 12)).foregroundStyle(AppColors.muted)
                        } else if let latest = entries.last {
                            Text(LanguageManager.t("body.card.lastLogged", ["date": formatBodyDate(latest.date)]))
                                .font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
                        } else {
                            Text(LanguageManager.t("body.card.empty")).font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-card")
            Button(action: onLog ?? onOpen) {
                Text(LanguageManager.t("body.log"))
                    .font(.app(size: 13, weight: .semibold)).foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                    .frame(minWidth: 48, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LanguageManager.t("body.quickLogTitle"))
            .accessibilityIdentifier("body-card-log")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
    }
}

/// The system date picker for a body entry, up to today.
struct BodyDatePicker: View {
    @Binding var date: String

    var body: some View {
        let selection = Binding<Date>(
            get: { WorkoutCalendar.parseDate(date) ?? Date() },
            set: { date = BodyDay.today($0) })
        DatePicker(selection: selection, in: ...Date(), displayedComponents: .date) {
            Text(LanguageManager.t("body.date")).font(.app(size: 14)).foregroundStyle(AppColors.secondaryText)
        }
        .datePickerStyle(.compact)
        .environment(\.locale, LanguageManager.locale)
        .tint(AppColors.accent)
        .frame(minHeight: 48)
        .accessibilityIdentifier("body-date-picker")
    }
}

/// Today's bodyweight in one step from the Progress card. Measurements stay on the Body screen and are kept.
struct BodyQuickLogSheet: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject private var health = HealthWeights.shared
    @Environment(\.dismiss) private var dismiss
    @State private var date = BodyDay.today()
    @State private var weight = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var unit: WeightUnit { store.weightUnit }

    var body: some View {
        let _ = themeManager.currentTheme
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BodyDatePicker(date: $date)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(LanguageManager.t("body.bodyweight")) (\(unit.label))")
                        .font(.app(size: 12)).foregroundStyle(AppColors.muted).lineLimit(1)
                    TextField("", text: Binding(get: { weight }, set: { text in
                        guard text.range(of: #"^\d{0,4}([.,]\d?)?$"#, options: .regularExpression) != nil else { return }
                        weight = text
                        error = nil
                    }))
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.app(size: 16, weight: .medium)).foregroundStyle(AppColors.text)
                    .padding(.horizontal, 12).frame(minHeight: 48)
                    .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                    .accessibilityLabel(LanguageManager.t("body.bodyweight"))
                    .accessibilityIdentifier("body-quick-weight")
                }
                if let error {
                    Text(error).font(.app(size: 12)).foregroundStyle(AppColors.danger).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body-quick-error")
                }
                Button(action: save) {
                    Text(LanguageManager.t("body.save"))
                        .font(.app(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("body-quick-save")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(LanguageManager.t("body.quickLogTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { FormCloseToolbarItem(accessibilityIdentifier: "body-quick-close") { dismiss() } }
        }
        .presentationDetents([.medium])
        .tint(AppColors.accent)
        .accessibilityIdentifier("body-quick-log")
        .onAppear { load(); focused = true }
        .onChange(of: date) { _, _ in load() }
    }

    /// Shows the date's current weight, typed or from Health, so saving unchanged changes nothing.
    private func load() {
        let shown = health.shownLog(store.state)
        weight = shown.entries.first { $0.date == date }?.bodyweightKg.map { BodyUnits.formatCanonical(.bodyweight, $0, unit: unit) } ?? ""
        error = nil
    }

    private func save() {
        let shown = health.shownLog(store.state)
        // The date's measurements go in unchanged, so only the weight can change.
        let inputs = BodyLog.quickLogInputs(shown: shown.entries.first { $0.date == date }, weight: weight, unit: unit)
        switch BodyLog.resolveForm(date: date, inputs: inputs, stored: store.state.bodyEntries?.first { $0.date == date },
                                   healthKg: shown.health[date], unit: unit) {
        case .invalid:
            let (low, high) = BodyUnits.displayRange(.bodyweight, unit: unit)
            error = LanguageManager.t("body.invalidBodyweight", ["min": low, "max": high, "unit": unit.label])
        case .empty:
            error = LanguageManager.t("body.emptyEntry")
        case .save(let stored, let hideHealth):
            if store.applyBodyEdit(date: date, stored: stored, hideHealth: hideHealth) {
                store.showNotice(LanguageManager.t("body.saved"))
                dismiss()
            } else {
                error = LanguageManager.t("body.saveFailed")
            }
        }
    }
}

/// Opt-in reading of Apple Health weigh-ins (docs/design/body-and-joint-journal.md#connecting).
/// The system Health sheet appears only after Connect, never at launch.
struct BodyHealthCard: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let isEnabled: Bool
    let status: String?
    let isBusy: Bool
    let onConnect: () -> Void
    let onTurnOff: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        if isEnabled { connectedRow } else { offCard }
    }

    /// Reading is on: one line with the latest weigh-in, beside the entries it fills.
    private var connectedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square").font(.system(size: 18)).foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LanguageManager.t("body.health.title")).font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                Text(status ?? LanguageManager.t("body.health.onText")).font(.app(size: 12)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-health-status")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onTurnOff) {
                Text(LanguageManager.t("body.health.turnOff")).font(.app(size: 13, weight: .semibold)).foregroundStyle(AppColors.secondaryText)
                    .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("body-health-turn-off")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-health")
    }

    private var offCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LanguageManager.t("body.health.title")).font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
            Text(LanguageManager.t(isEnabled ? "body.health.onText" : "body.health.offText"))
                .font(.app(size: 13)).lineSpacing(3).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let status {
                Text(status).font(.app(size: 12)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-health-status")
            }
            Button(action: isEnabled ? onTurnOff : onConnect) {
                Text(LanguageManager.t(isEnabled ? "body.health.turnOff" : "body.health.connect"))
                    .font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("body-health-connect")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-health")
    }
}

/// The body log (docs/design/body-and-joint-journal.md): free logging, Pro trend and relative strength.
struct BodyLogView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @ObservedObject private var proManager = ProAccessManager.shared
    @ObservedObject private var health = HealthWeights.shared
    @Environment(\.dismiss) private var dismiss

    @State private var date: String = BodyDay.today()
    @State private var inputs: [BodyMetric: String] = [:]
    @State private var loadedDate: String?
    @State private var showMeasurements = false
    @State private var error: String?
    @State private var saved = false
    /// The entry waiting for delete confirmation, from the Log card or an entry's menu.
    @State private var deleteDate: String?
    @State private var showPaywall = false

    private var today: String { BodyDay.today() }
    /// Typed entries joined with Apple Health weigh-ins (docs/design/body-and-joint-journal.md#merge-rules).
    private var shown: ShownBodyLog { health.shownLog(store.state) }
    private var entries: [BodyEntry] { shown.entries }
    private var existing: BodyEntry? { entries.first { $0.date == date } }
    private var storedEntry: BodyEntry? { store.state.bodyEntries?.first { $0.date == date } }
    /// The date's Health weigh-in when not hidden, even where a typed weight wins.
    private var healthKg: Double? { shown.health[date] }
    private var unit: WeightUnit { store.weightUnit }
    private var trendsUnlocked: Bool { proManager.isFeatureUnlocked(.bodyTrends) }

    var body: some View {
        let _ = themeManager.currentTheme
        let shown = self.shown
        let entries = shown.entries
        let report = trendsUnlocked ? BodyTrends.report(entries: entries, history: store.state.history, today: today) : nil
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        logCard.id("log")
                        // Connecting is offered under the form; once reading, Health is a status line by the entries.
                        if health.isAvailable && !health.isEnabled { healthCard }
                        if let report {
                            trendCard(report)
                            strengthCard(report.relativeStrength)
                        } else {
                            lockedCard
                        }
                        Text(LanguageManager.t("body.entries")).font(.app(size: 17, weight: .semibold)).foregroundStyle(AppColors.text)
                            .padding(.top, 6)
                        if health.isAvailable && health.isEnabled { healthCard }
                        if entries.isEmpty {
                            Text(LanguageManager.t("body.noEntries")).font(.app(size: 13)).foregroundStyle(AppColors.muted)
                        }
                        ForEach(entries.reversed()) { entry in
                            entryRow(entry, fromHealth: shown.healthDates.contains(entry.date)) {
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
        .task { await health.refresh() }
        .onChange(of: date) { _, _ in syncForm() }
        .onChange(of: existing) { _, _ in syncForm() }
        .alert(LanguageManager.t("body.deleteTitle"), isPresented: Binding(get: { deleteDate != nil }, set: { if !$0 { deleteDate = nil } }),
               presenting: deleteDate) { target in
            Button(LanguageManager.t("modal.delete"), role: .destructive) {
                if store.deleteBodyEntry(date: target, hideHealth: shown.health[target] != nil), target == date {
                    inputs = [:]
                    loadedDate = nil
                    date = today
                }
                deleteDate = nil
            }
            Button(LanguageManager.t("modal.cancel"), role: .cancel) { deleteDate = nil }
        } message: { target in
            Text(LanguageManager.t("body.deleteMessage", ["date": formatBodyDate(target)])
                 + (shown.health[target] != nil ? " " + LanguageManager.t("body.health.deleteNotice") : ""))
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

    private func invalidMessage(_ metric: BodyMetric) -> String {
        let (low, high) = BodyUnits.displayRange(metric, unit: unit)
        let label = unitLabel(metric, unit)
        return metric == .bodyweight
            ? LanguageManager.t("body.invalidBodyweight", ["min": low, "max": high, "unit": label])
            : LanguageManager.t("body.invalidMeasurement", ["name": LanguageManager.t(metric.labelKey), "min": low, "max": high, "unit": label])
    }

    private func save() {
        switch BodyLog.resolveForm(date: date, inputs: inputs, stored: storedEntry, healthKg: healthKg, unit: unit) {
        case .invalid(let metric):
            error = invalidMessage(metric)
        case .empty:
            error = LanguageManager.t("body.emptyEntry")
        case .save(let stored, let hideHealth):
            error = nil
            if store.applyBodyEdit(date: date, stored: stored, hideHealth: hideHealth) {
                loadedDate = nil
                syncForm()
                saved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { saved = false }
            } else {
                error = LanguageManager.t("body.saveFailed")
            }
        }
    }

    private var logCard: some View {
        card(title: LanguageManager.t(existing != nil ? "body.editTitle" : "body.logTitle"), identifier: "body-log") {
            BodyDatePicker(date: Binding(get: { date }, set: { select($0) }))
            if storedEntry != nil {
                Text(LanguageManager.t("body.replaceNotice", ["date": formatBodyDate(date)]))
                    .font(.app(size: 12)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-replace-notice")
            }
            if shown.healthDates.contains(date) {
                Text(LanguageManager.t("body.health.editNotice"))
                    .font(.app(size: 12)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-health-notice")
            }
            field(.bodyweight)
            Button { showMeasurements.toggle() } label: {
                Text(LanguageManager.t(showMeasurements ? "body.hideMeasurements" : "body.showMeasurements"))
                    .font(.app(size: 13)).foregroundStyle(AppColors.secondaryText)
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
                Text(error).font(.app(size: 12)).foregroundStyle(AppColors.danger).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("body-error")
            }
            Button(action: save) {
                Text(LanguageManager.t("body.save"))
                    .font(.app(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("body-save")
            if saved {
                Text(LanguageManager.t("body.saved")).font(.app(size: 12)).foregroundStyle(AppColors.accent)
                    .accessibilityIdentifier("body-saved")
            }
            if existing != nil {
                HStack(spacing: 16) {
                    if date != today {
                        Button(LanguageManager.t("body.cancelEdit")) { select(today) }
                            .font(.app(size: 13)).foregroundStyle(AppColors.secondaryText).frame(minHeight: 44)
                    }
                    Button(LanguageManager.t("body.deleteEntry")) { deleteDate = date }
                        .font(.app(size: 13)).foregroundStyle(AppColors.danger).frame(minHeight: 44)
                        .accessibilityIdentifier("body-delete")
                }
                .buttonStyle(.plain)
            }
        }
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
                .font(.app(size: 12)).foregroundStyle(AppColors.muted).lineLimit(1)
            TextField("", text: binding)
                .keyboardType(.decimalPad)
                .font(.app(size: 16, weight: .medium)).foregroundStyle(AppColors.text)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                .accessibilityLabel(LanguageManager.t(metric.labelKey))
                .accessibilityIdentifier("body-input-\(metric.rawValue)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Apple Health

    private var healthStatus: String? {
        switch health.status {
        case .idle: return nil
        case .failed: return LanguageManager.t("body.health.readFailed")
        case .loaded:
            return health.latestDate.map { LanguageManager.t("body.health.latest", ["date": formatBodyDate($0)]) }
                ?? LanguageManager.t("body.health.none")
        }
    }

    private var healthCard: some View {
        BodyHealthCard(isEnabled: health.isEnabled, status: healthStatus, isBusy: health.isConnecting,
                       onConnect: { Task { await health.connect() } }, onTurnOff: { health.turnOff() })
    }

    // MARK: Pro cards

    /// A fixed, made-up trend for the locked card: 13 weigh-ins drifting down over the last 12 weeks.
    private var samplePoints: [BodyTrendPoint] {
        let todayNumber = BodyDay.number(today) ?? 0
        let weights = [82.4, 82.9, 82.1, 81.8, 82.2, 81.5, 81.2, 81.6, 80.9, 80.6, 80.9, 80.3, 80.1]
        let entries = weights.enumerated().map { index, kg in
            BodyEntry(date: BodyDay.string(todayNumber - (weights.count - 1 - index) * 7), bodyweightKg: kg)
        }
        return BodyTrends.trend(entries)
    }

    /// Free users see one card for both Premium views, with a sample chart of what the trend looks like.
    private var lockedCard: some View {
        card(title: LanguageManager.t("body.lockedTitle"), identifier: "body-trends-locked", trailing: AnyView(ProBadge())) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LanguageManager.t("tour.sampleData")).font(.app(size: 11, weight: .semibold)).foregroundStyle(AppColors.muted)
                chart(samplePoints).opacity(0.55).accessibilityHidden(true)
            }
            Text(LanguageManager.t("body.locked")).font(.app(size: 13)).lineSpacing(3).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button { showPaywall = true } label: {
                Text(LanguageManager.t("body.unlock"))
                    .font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func trendCard(_ report: BodyTrendReport) -> some View {
        card(title: LanguageManager.t("body.trend.title"), identifier: "body-trend") {
            Text(LanguageManager.t("body.trend.subtitle")).font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
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
                    Text(LanguageManager.t("body.trend.measurements")).font(.app(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                        .padding(.top, 4)
                    ForEach(report.measurements, id: \.metric) { change in
                        HStack(alignment: .top) {
                            Text(LanguageManager.t(change.metric.labelKey)).font(.app(size: 13)).foregroundStyle(AppColors.secondaryText)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(formatValue(change.metric, change.latestCm, unit)).font(.app(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                                Text(LanguageManager.t("body.trend.since", [
                                    "change": "\(formatChange(change.metric, change.changeCm, unit)) \(unitLabel(change.metric, unit))",
                                    "date": formatBodyDate(change.since)]))
                                    .font(.app(size: 11)).foregroundStyle(AppColors.muted)
                            }
                        }
                    }
                }
            } else {
                Text(LanguageManager.t("body.trend.noData")).font(.app(size: 13)).foregroundStyle(AppColors.muted)
            }
        }
    }

    private func tile(_ title: String, _ value: String, muted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(size: 11)).foregroundStyle(AppColors.muted)
            Text(value).font(.app(size: muted ? 12 : 17, weight: muted ? .regular : .semibold))
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
            Text(formatValue(.bodyweight, high, unit)).font(.app(size: 10)).foregroundStyle(AppColors.muted)
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
                Text(formatValue(.bodyweight, low, unit)).font(.app(size: 10)).foregroundStyle(AppColors.muted)
                Spacer()
                Text(formatBodyDate(BodyDay.string(start)) + " – " + formatBodyDate(today)).font(.app(size: 10)).foregroundStyle(AppColors.muted)
            }
        }
    }

    private func strengthCard(_ report: RelativeStrengthReport) -> some View {
        card(title: LanguageManager.t("body.strength.title"), identifier: "body-strength") {
            Text(LanguageManager.t("body.strength.subtitle")).font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            switch report {
            case .needsWeighIn:
                Text(LanguageManager.t("body.strength.needWeighIn")).font(.app(size: 13)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .noLifts:
                Text(LanguageManager.t("body.strength.noLifts")).font(.app(size: 13)).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            case .rows(_, let rows):
                ForEach(rows, id: \.exerciseName) { row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: row.exerciseName))
                                .font(.app(size: 13, weight: .semibold)).foregroundStyle(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LanguageManager.t("body.strength.estimate", ["weight": "\(unit.formatDisplayWeight(row.estimated1RmKg)) \(unit.label)"]))
                                .font(.app(size: 11)).foregroundStyle(AppColors.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(LanguageManager.t("body.strength.ratio", ["ratio": String(format: "%.2f", locale: LanguageManager.locale, row.ratio)]))
                            .font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("body-strength-row")
                }
            }
        }
    }

    // MARK: Entries

    private func entryRow(_ entry: BodyEntry, fromHealth: Bool, onTap: @escaping () -> Void) -> some View {
        let measurements = BodyMetric.measurements.compactMap { metric in
            entry.value(metric).map { "\(LanguageManager.t(metric.labelKey)) \(BodyUnits.formatCanonical(metric, $0, unit: unit))" }
        }
        let selected = entry.date == date
        return Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatBodyDate(entry.date)).font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                    if fromHealth {
                        Text(LanguageManager.t("body.health.from")).font(.app(size: 12)).foregroundStyle(AppColors.muted)
                    }
                    if !measurements.isEmpty {
                        Text(measurements.joined(separator: " · ") + " " + LanguageManager.t(BodyUnits.lengthLabelKey(unit)))
                            .font(.app(size: 12)).foregroundStyle(AppColors.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let kg = entry.bodyweightKg {
                    Text(formatValue(.bodyweight, kg, unit)).font(.app(size: 14, weight: .semibold)).foregroundStyle(AppColors.text)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { deleteDate = entry.date } label: {
                Label(LanguageManager.t("body.deleteEntry"), systemImage: "trash")
            }
        }
        .accessibilityAction(named: LanguageManager.t("body.deleteEntry")) { deleteDate = entry.date }
        .accessibilityIdentifier("body-entry-\(entry.date)")
    }

    private func card<Content: View>(title: String, identifier: String, trailing: AnyView? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title).font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
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
