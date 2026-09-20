import SwiftUI

public enum FormLabTab: String, CaseIterable, Identifiable {
    case repMax = "rep_max"
    case curves = "curves"
    case balance = "balance"
    case mirror = "mirror"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .repMax: return "form_lab.tab_rep_max"
        case .curves: return "form_lab.tab_curves"
        case .balance: return "form_lab.tab_balance"
        case .mirror: return "form_lab.tab_mirror"
        }
    }
}

public struct FormLabView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared

    @State private var activeTab: FormLabTab = .repMax
    @State private var selectedExercise: String = "Barbell Bench Press"
    @State private var selectedFormula: RepMaxFormula = .brzycki
    @State private var selectedTimeframe: StrengthCurveTimeframe = .sixMonths
    @State private var balanceTimeframe: StrengthCurveTimeframe = .allTime
    @State private var showInfoSheet: Bool = false

    // Cloud mirror state
    @State private var isMirrorEnabled: Bool = CloudMirrorManager.shared.isEnabled
    @State private var isMirrorEncrypted: Bool = CloudMirrorManager.shared.isEncrypted
    @State private var mirrorPassphrase: String = ""
    @State private var syncStatusMessage: String? = nil
    @State private var showRestoreConfirm: Bool = false
    @State private var lastSyncTime: Date? = CloudMirrorManager.shared.getStatus().lastSyncTimestamp.map { Date(timeIntervalSince1970: $0) }

    // Interactive chart scrubber
    @State private var selectedPointIndex: Int? = nil

    private let customHistory: [WorkoutSessionRecord]?

    public init(store: AppStore, initialTab: FormLabTab = .repMax, customHistory: [WorkoutSessionRecord]? = nil) {
        self.store = store
        self._activeTab = State(initialValue: initialTab)
        self.customHistory = customHistory
    }

    private var effectiveHistory: [WorkoutSessionRecord] {
        customHistory ?? store.state.history
    }

    private var distinctExercises: [String] {
        var names = Set<String>()
        for record in effectiveHistory {
            for log in record.exerciseLogs {
                if !log.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty {
                    names.insert(log.exerciseName)
                }
            }
        }
        if names.isEmpty {
            names.insert("Barbell Bench Press")
            names.insert("Barbell Squat")
            names.insert("Barbell Deadlift")
        }
        return names.sorted()
    }

    private var currentExerciseSummary: ExerciseRepMaxSummary? {
        FormLabEngine.computeExerciseRepMax(
            exerciseName: selectedExercise,
            history: effectiveHistory,
            formula: selectedFormula
        )
    }

    private var currentCurveReport: LongitudinalCurveReport {
        FormLabEngine.computeLongitudinalCurve(
            exerciseName: selectedExercise,
            history: effectiveHistory,
            timeframe: selectedTimeframe,
            formula: selectedFormula
        )
    }

    private var balanceReport: AntagonistBalanceReport {
        FormLabEngine.computeAntagonistBalance(
            history: effectiveHistory,
            timeframe: balanceTimeframe
        )
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header with Sub-tab buttons and Info button
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FormLabTab.allCases) { tab in
                            Button(action: { activeTab = tab }) {
                                Text(LanguageManager.t(tab.titleKey))
                                    .font(.system(size: 13, weight: activeTab == tab ? .semibold : .medium))
                                    .foregroundColor(activeTab == tab ? AppColors.text : AppColors.muted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(activeTab == tab ? AppColors.surfaceRaised : AppColors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(activeTab == tab ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1)
                                    )
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: { showInfoSheet = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Tab Content
            switch activeTab {
            case .repMax:
                repMaxMatrixTab
            case .curves:
                strengthCurvesTab
            case .balance:
                structuralBalanceTab
            case .mirror:
                cloudMirrorTab
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            FormLabInfoSheet()
        }
        .alert(LanguageManager.t("form_lab.mirror_restore_confirm"), isPresented: $showRestoreConfirm) {
            Button(LanguageManager.t("form_lab.restore_btn"), role: .destructive) {
                restoreFromMirror()
            }
            Button(LanguageManager.t("table.deleteSet"), role: .cancel) {}
        } message: {
            Text(LanguageManager.t("form_lab.mirror_restore_warning"))
        }
        .onAppear {
            if !distinctExercises.contains(selectedExercise), let first = distinctExercises.first {
                selectedExercise = first
            }
        }
    }

    // MARK: - 1. Rep Max Matrix Tab

    private var repMaxMatrixTab: some View {
        VStack(spacing: 16) {
            Text(LanguageManager.t("form_lab.estimate_policy"))
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Exercise picker & Formula selector card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("form_lab.rep_max_matrix_title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        Text(LanguageManager.t("form_lab.rep_max_matrix_subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }

                // Exercise Menu
                Menu {
                    ForEach(distinctExercises, id: \.self) { ex in
                        Button(action: { selectedExercise = ex }) {
                            Text(ex)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedExercise)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(10)
                }

                // Formula Toggle (Brzycki vs Epley)
                HStack(spacing: 8) {
                    Text(LanguageManager.t("form_lab.formula_toggle") + ":")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)

                    Spacer()

                    HStack(spacing: 2) {
                        Button(action: { selectedFormula = .brzycki }) {
                            Text(LanguageManager.t("form_lab.formula.brzycki"))
                                .font(.system(size: 12, weight: selectedFormula == .brzycki ? .bold : .medium))
                                .foregroundColor(selectedFormula == .brzycki ? AppColors.accent : AppColors.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedFormula == .brzycki ? AppColors.positiveBg : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button(action: { selectedFormula = .epley }) {
                            Text(LanguageManager.t("form_lab.formula.epley"))
                                .font(.system(size: 12, weight: selectedFormula == .epley ? .bold : .medium))
                                .foregroundColor(selectedFormula == .epley ? AppColors.accent : AppColors.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedFormula == .epley ? AppColors.positiveBg : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(3)
                    .background(AppColors.surface)
                    .cornerRadius(10)
                }
            }
            .padding(16)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)

            // PR Set Traceability Banner
            if let summary = currentExerciseSummary {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0xF59E0B))

                    let dateStr = summary.achievedDate.map { formatAchievedDate($0) } ?? ""
                    let displayWeight = store.weightUnit.toDisplay(summary.bestWeightKg)
                    let unitStr = store.weightUnit.label
                    let formatted = LanguageManager.t(
                        "form_lab.achieved_with",
                        [
                            "weight": String(format: "%.1f %@", displayWeight, unitStr),
                            "reps": "\(summary.bestReps)",
                            "date": dateStr,
                            "formula": LanguageManager.t(selectedFormula.titleKey)
                        ]
                    )

                    Text(formatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.text)

                    Spacer()
                }
                .padding(12)
                .background(Color(hex: 0xF59E0B).opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xF59E0B).opacity(0.4), lineWidth: 1))
                .cornerRadius(10)
            }

            // Rep Max Targets Grid
            if let targets = currentExerciseSummary?.targets, !targets.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(targets) { target in
                        repMaxCard(target: target)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 32))
                        .foregroundColor(AppColors.muted)
                    Text(LanguageManager.t("form_lab.no_weighted_sets"))
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(AppColors.surfaceRaised)
                .cornerRadius(16)
            }
        }
    }

    private func repMaxCard(target: RepMaxTarget) -> some View {
        let displayVal = store.weightUnit.toDisplay(target.estimatedWeightKg)
        let unitStr = store.weightUnit.label

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(target.reps)RM")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppColors.accent)
                Spacer()
                Text(target.reps == 1 ? "100%" : "\(Int(target.percentageOf1RM))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.muted)
            }

            Text(String(format: "%.1f %@", displayVal, unitStr))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.text)

            Text(LanguageManager.t("form_lab.estimated_label"))
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(14)
    }

    // MARK: - 2. Longitudinal Strength Curves Tab

    private var strengthCurvesTab: some View {
        let report = currentCurveReport

        return VStack(spacing: 16) {
            Text(LanguageManager.t("form_lab.estimate_policy"))
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(LanguageManager.t("form_lab.formula_used", ["formula": LanguageManager.t(selectedFormula.titleKey)]))
                .font(.system(size: 12))
                .foregroundColor(AppColors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Exercise picker & Timeframe selector
            VStack(spacing: 12) {
                // Exercise Menu
                Menu {
                    ForEach(distinctExercises, id: \.self) { ex in
                        Button(action: { selectedExercise = ex }) {
                            Text(ex)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedExercise)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(10)
                }

                // Timeframe Selector
                HStack(spacing: 6) {
                    ForEach(StrengthCurveTimeframe.allCases) { tf in
                        Button(action: { selectedTimeframe = tf }) {
                            Text(LanguageManager.t(tf.labelKey))
                                .font(.system(size: 12, weight: selectedTimeframe == tf ? .bold : .medium))
                                .foregroundColor(selectedTimeframe == tf ? AppColors.accent : AppColors.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(selectedTimeframe == tf ? AppColors.positiveBg : AppColors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedTimeframe == tf ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1)
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)

            // Headline Stats (Start 1RM, Current 1RM, Net Gain)
            HStack(spacing: 10) {
                statCard(
                    title: LanguageManager.t("form_lab.start_1rm"),
                    value: report.start1rmKg != nil ? formatWeight(report.start1rmKg!) : "—",
                    color: AppColors.text
                )
                statCard(
                    title: LanguageManager.t("form_lab.current_1rm"),
                    value: report.current1rmKg != nil ? formatWeight(report.current1rmKg!) : "—",
                    color: AppColors.accent
                )
                statCard(
                    title: LanguageManager.t("form_lab.net_gain"),
                    value: report.points.count >= 2 ? String(format: "%@ (%.1f%%)", formatDelta(report.deltaKg), report.percentageGain) : "—",
                    color: report.deltaKg >= 0 ? AppColors.accent : Color.red
                )
            }

            // Interactive Progression Chart Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("form_lab.curves_title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        let count = report.points.count
                        Text(LanguageManager.t("form_lab.sessions_tracked", ["count": "\(count)"]))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                }

                if report.points.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.muted)
                        Text(LanguageManager.t("form_lab.no_weighted_sets"))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                } else {
                    // Touch scrubber detail tooltip if active
                    if let pt = selectedPointIndex.flatMap({ report.points.indices.contains($0) ? report.points[$0] : nil }) ?? report.points.last {
                        VStack(alignment: .leading, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LanguageManager.t("form_lab.achieved_with", [
                                    "weight": formatWeight(pt.topWeightKg),
                                    "reps": "\(pt.topReps)",
                                    "date": formatAchievedDate(pt.dateString),
                                    "formula": LanguageManager.t(selectedFormula.titleKey)
                                ]))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.muted)
                            }
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(LanguageManager.t("exercise.history.estimated1rmTitle"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                                Text(formatWeight(pt.estimated1rmKg))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                        .padding(10)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.accent.opacity(0.4), lineWidth: 1))
                    }

                    // Canvas Line Chart
                    StrengthLineChart(
                        points: report.points,
                        selectedIndex: $selectedPointIndex,
                        weightUnit: store.weightUnit
                    )
                    .frame(height: 200)
                }
            }
            .padding(16)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: - 3. Structural Balance Tab

    private var structuralBalanceTab: some View {
        let balance = balanceReport

        return VStack(spacing: 16) {
            // Timeframe Selector
            HStack(spacing: 6) {
                ForEach(StrengthCurveTimeframe.allCases) { tf in
                    Button(action: { balanceTimeframe = tf }) {
                        Text(LanguageManager.t(tf.labelKey))
                            .font(.system(size: 12, weight: balanceTimeframe == tf ? .bold : .medium))
                            .foregroundColor(balanceTimeframe == tf ? AppColors.accent : AppColors.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(balanceTimeframe == tf ? AppColors.positiveBg : AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(balanceTimeframe == tf ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(14)

            // Balance Summary Header
            VStack(alignment: .leading, spacing: 4) {
                Text(LanguageManager.t("form_lab.balance_title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t("form_lab.balance_subtitle"))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)

            // Antagonist Ratio Cards
            antagonistRatioCard(ratio: balance.pushPull)
            antagonistRatioCard(ratio: balance.quadHamstring)
            antagonistRatioCard(ratio: balance.upperLower)
        }
    }

    private func antagonistRatioCard(ratio: AntagonistRatio) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title & Status Badge
            VStack(alignment: .leading, spacing: 6) {
                Text(LanguageManager.t(ratio.titleKey))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.text)

                Text(LanguageManager.t(ratio.status.labelKey))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(statusColor(ratio.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(ratio.status).opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(statusColor(ratio.status).opacity(0.5), lineWidth: 1))
                    .cornerRadius(6)
            }

            // Sets breakdown
            HStack {
                Text("\(LanguageManager.t(ratio.primaryLabelKey)): \(ratio.primarySets) \(LanguageManager.t("matrix.setsUnit"))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text(ratio.ratio.map { String(format: "Ratio: %.2f", $0) } ?? "Ratio: —")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor(ratio.status))
                Spacer()
                Text("\(LanguageManager.t(ratio.antagonistLabelKey)): \(ratio.antagonistSets) \(LanguageManager.t("matrix.setsUnit"))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
            }

            // Visual Dual Meter
            GeometryReader { geo in
                let total = ratio.primarySets + ratio.antagonistSets
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.surface)
                        .frame(height: 8)

                    if total > 0 {
                        let primaryFrac = CGFloat(ratio.primarySets) / CGFloat(total)
                        HStack(spacing: 2) {
                            if ratio.primarySets > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ratio.status == .primaryDominant ? Color(hex: 0xF59E0B) : AppColors.accent)
                                    .frame(width: max(4, geo.size.width * primaryFrac - (ratio.antagonistSets > 0 ? 1 : 0)))
                            }
                            if ratio.antagonistSets > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(ratio.status == .antagonistDominant ? Color.red : Color(hex: 0x3B82F6))
                                    .frame(width: max(4, geo.size.width * (1.0 - primaryFrac) - (ratio.primarySets > 0 ? 1 : 0)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .frame(height: 8)

            // Alert / Recommendation Note
            VStack(alignment: .leading, spacing: 4) {
                Text(LanguageManager.t(ratio.alertMessageKey))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ratio.status == .optimal ? AppColors.accent : (ratio.status == .insufficientData ? AppColors.muted : Color(hex: 0xF59E0B)))

                Text(LanguageManager.t(ratio.recommendationKey))
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .cornerRadius(8)
        }
        .padding(16)
        .background(AppColors.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(16)
    }

    private func statusColor(_ status: AntagonistStatus) -> Color {
        switch status {
        case .optimal: return AppColors.accent
        case .primaryDominant, .antagonistDominant: return Color(hex: 0xF59E0B)
        case .insufficientData: return AppColors.muted
        }
    }

    // MARK: - 4. Cloud Mirror Tab

    private var cloudMirrorTab: some View {
        VStack(spacing: 16) {
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(LanguageManager.t("form_lab.mirror_title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t("form_lab.mirror_subtitle"))
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)

            // Status Card
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                    Text("iCloud Drive & Cloud Mirror")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.text)
                    Spacer()
                    Circle()
                        .fill(isMirrorEnabled ? AppColors.accent : AppColors.muted)
                        .frame(width: 8, height: 8)
                }

                Divider().background(AppColors.border)

                HStack {
                    Text(LanguageManager.t("form_lab.mirror_toggle"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.text)
                    Spacer()
                    Toggle("", isOn: $isMirrorEnabled)
                        .labelsHidden()
                        .onChange(of: isMirrorEnabled) { val in
                            CloudMirrorManager.shared.isEnabled = val
                        }
                }

                HStack {
                    Text(LanguageManager.t("form_lab.mirror_encrypted_toggle"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.text)
                    Spacer()
                    Toggle("", isOn: $isMirrorEncrypted)
                        .labelsHidden()
                        .onChange(of: isMirrorEncrypted) { val in
                            CloudMirrorManager.shared.isEncrypted = val
                        }
                }

                if isMirrorEncrypted {
                    SecureField(LanguageManager.t("form_lab.mirror_passphrase_label"), text: $mirrorPassphrase)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                }

                if let syncTime = lastSyncTime {
                    Text(LanguageManager.t("form_lab.mirror_last_synced", ["time": formatSyncTime(syncTime)]))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                } else {
                    Text(LanguageManager.t("form_lab.mirror_never_synced"))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                }

                if let msg = syncStatusMessage {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(16)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(16)

            // Action Buttons
            VStack(spacing: 10) {
                Button(action: syncNow) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                        Text(LanguageManager.t("form_lab.mirror_sync_now"))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(AppColors.background)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.accent)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: { showRestoreConfirm = true }) {
                    Text(LanguageManager.t("form_lab.mirror_restore_cta"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func syncNow() {
        let json = store.exportBackupJson()
        let pass = mirrorPassphrase.trimmingCharacters(in: .whitespaces).isEmpty ? nil : mirrorPassphrase
        do {
            _ = try CloudMirrorManager.shared.syncNow(backupJson: json, passphrase: pass)
            lastSyncTime = Date()
            syncStatusMessage = LanguageManager.t("form_lab.mirror_success")
        } catch {
            syncStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func restoreFromMirror() {
        let pass = mirrorPassphrase.trimmingCharacters(in: .whitespaces).isEmpty ? nil : mirrorPassphrase
        do {
            let json = try CloudMirrorManager.shared.readLatestSnapshot(passphrase: pass)
            store.restoreBackupJson(json)
            syncStatusMessage = LanguageManager.t("notice.backupRestored")
        } catch {
            syncStatusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Format Helpers

    private func formatWeight(_ kg: Double) -> String {
        let val = store.weightUnit.toDisplay(kg)
        return String(format: "%.1f %@", val, store.weightUnit.label)
    }

    private func formatDelta(_ kg: Double) -> String {
        let val = store.weightUnit.toDisplay(kg)
        let prefix = val >= 0 ? "+" : ""
        return String(format: "%@%.1f %@", prefix, val, store.weightUnit.label)
    }

    private func formatSyncTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm, dd MMM"
        return df.string(from: date)
    }
}

// MARK: - Canvas Progression Chart

private struct StrengthLineChart: View {
    let points: [StrengthDataPoint]
    @Binding var selectedIndex: Int?
    let weightUnit: WeightUnit

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let padH: CGFloat = 16
            let padV: CGFloat = 20

            let values = points.map { $0.estimated1rmKg }
            let minVal = (values.min() ?? 0.0) * 0.95
            let maxVal = max(minVal + 1.0, (values.max() ?? 100.0) * 1.05)
            let valRange = maxVal - minVal

            let count = points.count
            let xStep = (w - 2 * padH) / CGFloat(max(1, count - 1))

            let coords: [CGPoint] = points.indices.map { i in
                let x = padH + CGFloat(i) * xStep
                let normalizedY = CGFloat((points[i].estimated1rmKg - minVal) / valRange)
                let y = h - padV - normalizedY * (h - 2 * padV)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Background Gradient Fill
                Path { path in
                    guard let first = coords.first else { return }
                    path.move(to: CGPoint(x: first.x, y: h - padV))
                    path.addLine(to: first)
                    for pt in coords.dropFirst() {
                        path.addLine(to: pt)
                    }
                    if let last = coords.last {
                        path.addLine(to: CGPoint(x: last.x, y: h - padV))
                    }
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.35), AppColors.accent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Line Path
                Path { path in
                    guard let first = coords.first else { return }
                    path.move(to: first)
                    for pt in coords.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Point Markers
                ForEach(coords.indices, id: \.self) { i in
                    let pt = coords[i]
                    let isSelected = selectedIndex == i

                    Circle()
                        .fill(isSelected ? AppColors.text : AppColors.accent)
                        .frame(width: isSelected ? 10 : 6, height: isSelected ? 10 : 6)
                        .overlay(
                            Circle()
                                .stroke(AppColors.background, lineWidth: 1.5)
                        )
                        .position(pt)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let touchX = value.location.x
                        var closestIndex = 0
                        var minDistance = CGFloat.greatestFiniteMagnitude
                        for (i, pt) in coords.enumerated() {
                            let dist = abs(pt.x - touchX)
                            if dist < minDistance {
                                minDistance = dist
                                closestIndex = i
                            }
                        }
                        selectedIndex = closestIndex
                    }
            )
        }
    }
}

private func formatAchievedDate(_ dateStr: String) -> String {
    guard !dateStr.isEmpty else { return "" }
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFormatter.date(from: dateStr)
    if date == nil {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: dateStr)
    }
    if date == nil && dateStr.count == 10 && dateStr.contains("-") {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        date = df.date(from: dateStr)
    }
    guard let parsedDate = date else {
        return String(dateStr.prefix(10))
    }
    let displayFormatter = DateFormatter()
    displayFormatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
    displayFormatter.dateFormat = "d MMM yyyy"
    return displayFormatter.string(from: parsedDate)
}
