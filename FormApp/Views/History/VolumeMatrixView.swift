import SwiftUI

public struct VolumeMatrixView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared

    @State private var isPlannedMode: Bool = false
    @State private var selectedWeekKey: String = ""
    @State private var selectedMuscleKey: String = "chest"
    @State private var currentView: String = "front"
    @State private var showInfoSheet: Bool = false

    private let customHistory: [WorkoutSessionRecord]?

    public init(store: AppStore, customHistory: [WorkoutSessionRecord]? = nil) {
        self.store = store
        self.customHistory = customHistory
    }

    private var currentWeekKey: String {
        let date = Date()
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    private var effectiveWeekKey: String {
        selectedWeekKey.isEmpty ? currentWeekKey : selectedWeekKey
    }

    private var report: VolumeMatrixReport {
        guard let catalog = ExerciseMuscleCatalog.shared else {
            return VolumeMatrixReport(
                weekKey: effectiveWeekKey,
                isPlannedRoutine: isPlannedMode,
                muscleSummaries: [:],
                totalEffectiveSets: 0,
                optimalMuscleCount: 0,
                underTrainedCount: 0,
                highFatigueCount: 0
            )
        }

        if isPlannedMode {
            let program = store.state.programs.first(where: { $0.id == store.state.activeProgramId })
                ?? store.state.programs.first
                ?? Program(id: "empty", name: "", workouts: [])
            return VolumeMatrixEngine.computePlannedRoutineVolume(
                program: program,
                catalog: catalog,
                language: language.currentLanguage
            )
        } else {
            return VolumeMatrixEngine.computeLoggedVolume(
                targetWeekKey: effectiveWeekKey,
                history: customHistory ?? store.state.history,
                activeSession: effectiveWeekKey == currentWeekKey ? store.activeSession : nil,
                catalog: catalog,
                language: language.currentLanguage
            )
        }
    }

    public var body: some View {
        let report = self.report
        return VStack(spacing: 16) {
            Text(LanguageManager.t("matrix.limitations"))
                .font(.system(size: 13))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Mode Selector: Logged Volume vs Planned Routine
            HStack(spacing: 4) {
                Button(action: { isPlannedMode = false }) {
                    Text(LanguageManager.t("matrix.mode.completed"))
                        .font(.system(size: 14, weight: !isPlannedMode ? .bold : .medium))
                        .foregroundColor(!isPlannedMode ? .white : Color(hex: 0x7E8B9B))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(
                            colors: !isPlannedMode ? [Color(hex: 0x0C292A), Color(hex: 0x0D2224)] : [.clear, .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(!isPlannedMode ? Color(hex: 0x1D5350) : Color.clear, lineWidth: 1.5)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: { isPlannedMode = true }) {
                    Text(LanguageManager.t("matrix.mode.planned"))
                        .font(.system(size: 14, weight: isPlannedMode ? .bold : .medium))
                        .foregroundColor(isPlannedMode ? .white : Color(hex: 0x7E8B9B))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(
                            colors: isPlannedMode ? [Color(hex: 0x0C292A), Color(hex: 0x0D2224)] : [.clear, .clear],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isPlannedMode ? Color(hex: 0x1D5350) : Color.clear, lineWidth: 1.5)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 48)
            .padding(4)
            .background(Color(hex: 0x0F1518))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x2B373C), lineWidth: 1))
            .cornerRadius(16)

            // Week Navigator (for Logged Mode)
            if !isPlannedMode {
                ZStack {
                    // Dark teal base and a low-contrast tone crossing behind the week label.
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        context.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .linearGradient(
                                Gradient(colors: [Color(hex: 0x0C2427), Color(hex: 0x071719)]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: w, y: h)
                            )
                        )
                        var path = Path()
                        path.move(to: CGPoint(x: w * 0.34, y: h))
                        path.addCurve(
                            to: CGPoint(x: w * 0.89, y: 0),
                            control1: CGPoint(x: w * 0.62, y: h * 1.02),
                            control2: CGPoint(x: w * 0.76, y: h * 0.4)
                        )
                        path.addLine(to: CGPoint(x: w, y: 0))
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()

                        context.fill(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [Color(hex: 0x071D20), Color(hex: 0x062527)]),
                                startPoint: CGPoint(x: w * 0.34, y: h),
                                endPoint: CGPoint(x: w, y: 0)
                            )
                        )

                        var line = Path()
                        line.move(to: CGPoint(x: w * 0.34, y: h))
                        line.addCurve(
                            to: CGPoint(x: w * 0.89, y: 0),
                            control1: CGPoint(x: w * 0.62, y: h * 1.02),
                            control2: CGPoint(x: w * 0.76, y: h * 0.4)
                        )
                        context.stroke(line, with: .color(Color(hex: 0x3A817C).opacity(0.14)), lineWidth: 1.2)
                    }

                    HStack {
                        // Left circular button
                        Button(action: { shiftWeek(-1) }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: 0xD0D9E3))
                                .frame(width: 36, height: 36)
                                .background(Color(hex: 0x161E26))
                                .overlay(Circle().stroke(Color(hex: 0x26323E), lineWidth: 1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        VStack(spacing: 2) {
                            Text(effectiveWeekKey == currentWeekKey ? LanguageManager.t("matrix.thisWeek") : effectiveWeekKey)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            Text(effectiveWeekKey)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: 0x7E8B9B))
                        }

                        Spacer()

                        // Right circular button
                        Button(action: { shiftWeek(1) }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(effectiveWeekKey < currentWeekKey ? Color(hex: 0xD0D9E3) : Color(hex: 0x7E8B9B).opacity(0.35))
                                .frame(width: 36, height: 36)
                                .background(Color(hex: 0x161E26))
                                .overlay(Circle().stroke(Color(hex: 0x26323E), lineWidth: 1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(effectiveWeekKey >= currentWeekKey)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(height: 70)
                .background(Color(hex: 0x0A1B1E))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0x1A4547), lineWidth: 1))
                .cornerRadius(18)
            }

            if isPlannedMode {
                Text(LanguageManager.t("matrix.cycleNote"))
                    .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if store.state.programs.isEmpty {
                    Text(LanguageManager.t("matrix.noProgram")).foregroundColor(AppColors.muted)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                kpiCard(title: LanguageManager.t(report.isPlannedRoutine ? "matrix.stat.plannedSets" : "matrix.stat.totalSets"),
                    value: "\(report.totalWorkingSets)", subtitle: LanguageManager.t("matrix.setsUnit"), icon: "dumbbell.fill", color: AppColors.purple, tone: .purple)
                kpiCard(title: LanguageManager.t("matrix.stat.credits"), value: String(format: "%.1f", report.totalEffectiveSets),
                    subtitle: LanguageManager.t("matrix.creditsUnit"), icon: "chart.bar.fill", color: AppColors.accent, tone: .teal)
            }
            Text(LanguageManager.t("matrix.creditNote"))
                .font(.system(size: 12)).foregroundColor(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !report.unmappedExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LanguageManager.t("matrix.unmapped", ["count": report.unmappedExercises.values.reduce(0, +)]))
                        .font(.system(size: 13)).foregroundColor(AppColors.text)
                    ForEach(report.unmappedExercises.keys.sorted(), id: \.self) { name in
                        let count = report.unmappedExercises[name] ?? 0
                        Text("\(name) · \(count) " + LanguageManager.t(count == 1 ? "matrix.setUnit" : "matrix.setsUnit"))
                            .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(AppColors.surface).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
            }

            // Heatmap Figure Card ("Athlete Window")
            if let catalog = ExerciseMuscleCatalog.shared {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 14) {
                        heatmapFigure(catalog: catalog, report: report)
                            .frame(height: 280)

                        // Front / Back Toggle
                        HStack(spacing: 2) {
                            ForEach(["front", "back"], id: \.self) { view in
                                let isSelected = currentView == view
                                Button(action: { currentView = view }) {
                                    Text(LanguageManager.t(view == "front" ? "anatomy.front" : "anatomy.back"))
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundColor(isSelected ? AppColors.purple : AppColors.muted)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(isSelected ? AppColors.purpleBg : Color.clear)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 180, height: 34)
                        .padding(3)
                        .background(AppColors.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppColors.border, lineWidth: 1))
                        .cornerRadius(11)

                        // Volume Zone Legend (FlowLayout to cleanly center and wrap on any screen width)
                        FlowLayout(alignment: .center, horizontalSpacing: 10, verticalSpacing: 6) {
                            ForEach(VolumeZone.allCases.filter { report.isPlannedRoutine ? $0 == .noWeeklyReference : $0 != .noWeeklyReference }, id: \.self) { zone in
                                HStack(alignment: .center, spacing: 5) {
                                    Circle()
                                        .fill(zone.color)
                                        .frame(width: 7, height: 7)
                                    Text(LanguageManager.t(zone.titleKey))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.muted)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .background(AppColors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColors.border, lineWidth: 1))
                    .cornerRadius(20)

                    // Circled "i" info button top-right corner of the athlete window
                    Button(action: { showInfoSheet = true }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Muscle Selectors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(VolumeMatrixEngine.canonicalMuscles, id: \.self) { muscleKey in
                        let summary = report.muscleSummaries[muscleKey]
                        let isSelected = muscleKey == selectedMuscleKey
                        let zoneColor = summary?.zone.color ?? Color(hex: 0x627485)

                        Button(action: {
                            selectedMuscleKey = muscleKey
                            if let defView = summary?.defaultView, currentView != defView {
                                currentView = defView
                            }
                        }) {
                            HStack(spacing: 6) {
                                Circle().fill(zoneColor).frame(width: 7, height: 7)
                                Text(summary?.localizedName ?? muscleKey)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? AppColors.text : AppColors.secondaryText)
                                Text(String(format: "%.1f", summary?.totalEffectiveSets ?? 0))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(zoneColor)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppColors.surfaceRaised : AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Detail Card
            if let selected = report.muscleSummaries[selectedMuscleKey] {
                muscleDetailCard(summary: selected)
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            VolumeMatrixInfoSheet()
        }
    }

    private struct KpiTone {
        let surfaceTop: Color
        let surfaceBottom: Color
        let waveStart: Color
        let waveEnd: Color
        let border: Color
        let waveLine: Color

        static let purple = KpiTone(
            surfaceTop: Color(hex: 0x191A25), surfaceBottom: Color(hex: 0x10151C),
            waveStart: Color(hex: 0x171824), waveEnd: Color(hex: 0x201F2D),
            border: Color(hex: 0x3A3452), waveLine: Color(hex: 0x55496E)
        )
        static let teal = KpiTone(
            surfaceTop: Color(hex: 0x0C1E1E), surfaceBottom: Color(hex: 0x091517),
            waveStart: Color(hex: 0x0A1E1E), waveEnd: Color(hex: 0x0D2725),
            border: Color(hex: 0x1B4841), waveLine: Color(hex: 0x286A5D)
        )
    }

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, color: Color, tone: KpiTone) -> some View {
        ZStack(alignment: .topLeading) {
            // The full surface shifts in tone; the curved band adds a second, quieter layer.
            Canvas { context, size in
                let w = size.width
                let h = size.height
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [tone.surfaceTop, tone.surfaceBottom]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: w, y: h)
                    )
                )

                var wave = Path()
                wave.move(to: CGPoint(x: w * 0.05, y: h * 1.02))
                wave.addCurve(
                    to: CGPoint(x: w, y: h * 0.66),
                    control1: CGPoint(x: w * 0.48, y: h * 1.05),
                    control2: CGPoint(x: w * 0.62, y: h * 0.82)
                )
                wave.addLine(to: CGPoint(x: w, y: h))
                wave.closeSubpath()

                context.fill(
                    wave,
                    with: .linearGradient(
                        Gradient(colors: [tone.waveStart, tone.waveEnd]),
                        startPoint: CGPoint(x: w * 0.05, y: h),
                        endPoint: CGPoint(x: w, y: h * 0.66)
                    )
                )

                var stroke = Path()
                stroke.move(to: CGPoint(x: w * 0.05, y: h * 1.02))
                stroke.addCurve(
                    to: CGPoint(x: w, y: h * 0.66),
                    control1: CGPoint(x: w * 0.48, y: h * 1.05),
                    control2: CGPoint(x: w * 0.62, y: h * 0.82)
                )
                context.stroke(stroke, with: .color(tone.waveLine.opacity(0.3)), lineWidth: 1.2)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Top row: Icon badge + Title
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(color.opacity(0.14))
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(color.opacity(0.32), lineWidth: 1)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(color)
                    }
                    .frame(width: 32, height: 32)

                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(hex: 0xD1D8E0))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                // Bottom group: Value + Subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 114)
        .background(tone.surfaceBottom)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tone.border, lineWidth: 1))
        .cornerRadius(18)
    }

    private func heatmapFigure(catalog: ExerciseMuscleCatalog, report: VolumeMatrixReport) -> some View {
        let anatomy = catalog.views[currentView]
        let paths = catalog.parsedPaths(for: currentView)

        return Canvas { context, size in
            guard let anatomy, let image = ExerciseMuscleCatalog.images[currentView] else { return }
            let scale = min(size.width / catalog.width, size.height / catalog.height)
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.translateBy(x: (size.width - catalog.width * scale) / 2, y: (size.height - catalog.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.draw(Image(uiImage: image), in: CGRect(x: 0, y: 0, width: catalog.width, height: catalog.height))
            context.translateBy(x: -anatomy.offsetX, y: 0)
            for (muscle, path) in paths {
                let summary = report.muscleSummaries[muscle]
                let zone = summary?.zone ?? .underMev
                let isSelected = (muscle == selectedMuscleKey)
                let p = Path(path)

                if zone == .underMev || zone == .noWeeklyReference {
                    var baseContext = context
                    baseContext.blendMode = .color
                    baseContext.opacity = 0.50
                    baseContext.fill(p, with: .color(zone.color))
                } else {
                    // Active worked muscle: rich, vibrant color pass
                    var colorContext = context
                    colorContext.blendMode = .color
                    colorContext.opacity = isSelected ? 1.0 : 0.92
                    colorContext.fill(p, with: .color(zone.color))

                    // Luminous screen pass to lift dark shadows and make the colors pop
                    var screenContext = context
                    screenContext.blendMode = .screen
                    screenContext.opacity = isSelected ? 0.32 : 0.20
                    screenContext.fill(p, with: .color(zone.color))

                    // Subtle contour outline for muscle separation
                    var strokeContext = context
                    strokeContext.blendMode = .normal
                    strokeContext.stroke(
                        p,
                        with: .color(zone.color.opacity(isSelected ? 0.90 : 0.40)),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
                }
            }
        }
    }

    private func muscleDetailCard(summary: MuscleVolumeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.localizedName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.text)
                Text(LanguageManager.t(summary.zone.titleKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(summary.zone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(summary.zone.badgeBgColor)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(summary.zone.color.opacity(0.5), lineWidth: 1))
                    .cornerRadius(8)
                Text(LanguageManager.t("matrix.breakdown", [
                    "credits": String(format: "%.1f", summary.totalEffectiveSets),
                    "direct": summary.directSets,
                    "indirect": summary.indirectSets
                ]))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.secondaryText)
            }

            Text(LanguageManager.t(summary.zone.descriptionKey))
                .font(.system(size: 12))
                .foregroundColor(AppColors.muted)

            // Landmark Gauge
            if summary.zone != .noWeeklyReference { landmarkGauge(summary: summary) }

            if !summary.contributions.isEmpty {
                Divider().background(AppColors.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text(LanguageManager.t("matrix.contributingExercises"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    ForEach(summary.contributions) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.exerciseName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                Text((item.isPrimary ? LanguageManager.t("anatomy.primary") : LanguageManager.t("anatomy.secondary")) + (item.date.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 11))
                                    .foregroundColor(item.isPrimary ? AppColors.purple : AppColors.secondaryText)
                            }
                            Spacer()
                            Text(LanguageManager.t("matrix.contribution", ["sets": item.completedSets, "credits": String(format: "%.1f", item.effectiveSets)]))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.text)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(18)
    }

    private func landmarkGauge(summary: MuscleVolumeSummary) -> some View {
        let maxScale = max(summary.landmarks.mrv * 1.25, 24)
        let fraction = CGFloat(min(max(summary.totalEffectiveSets / maxScale, 0), 1))

        return VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColors.background)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(summary.zone.color)
                        .frame(width: geo.size.width * fraction, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text("MEV: \(Int(summary.landmarks.mev))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.muted)
                Spacer()
                Text("MAV: \(Int(summary.landmarks.mavMin))–\(Int(summary.landmarks.mavMax))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: 0x20D791))
                Spacer()
                Text("MRV: \(Int(summary.landmarks.mrv))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: 0xFF897B))
            }
        }
    }

    private func shiftWeek(_ delta: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        let parts = effectiveWeekKey.split(separator: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return }

        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week + delta
        comps.weekday = 2
        if let d = calendar.date(from: comps) {
            let newYear = calendar.component(.yearForWeekOfYear, from: d)
            let newWeek = calendar.component(.weekOfYear, from: d)
            selectedWeekKey = String(format: "%04d-W%02d", newYear, newWeek)
        }
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .center
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 6

    init(
        alignment: HorizontalAlignment = .center,
        horizontalSpacing: CGFloat = 10,
        verticalSpacing: CGFloat = 6
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    private struct Row {
        var subviewIndices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()

        for (index, subview) in subviews.enumerated() {
            let itemProposal = ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil)
            let size = subview.sizeThatFits(itemProposal)
            if !currentRow.subviewIndices.isEmpty && currentRow.width + horizontalSpacing + size.width > maxWidth {
                rows.append(currentRow)
                currentRow = Row()
            }
            if !currentRow.subviewIndices.isEmpty {
                currentRow.width += horizontalSpacing
            }
            currentRow.subviewIndices.append(index)
            currentRow.sizes.append(size)
            currentRow.width += size.width
            currentRow.height = max(currentRow.height, size.height)
        }

        if !currentRow.subviewIndices.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }

        let totalHeight = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        let maxRowWidth = rows.reduce(0) { max($0, $1.width) }
        let width = (proposal.width != nil && proposal.width!.isFinite) ? proposal.width! : maxRowWidth

        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let xOffset: CGFloat
            switch alignment {
            case .leading:
                xOffset = 0
            case .trailing:
                xOffset = max(0, bounds.width - row.width)
            default:
                xOffset = max(0, (bounds.width - row.width) / 2.0)
            }
            var x = bounds.minX + xOffset

            for (index, subviewIndex) in row.subviewIndices.enumerated() {
                let size = row.sizes[index]
                let yOffset = (row.height - size.height) / 2.0
                subviews[subviewIndex].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }

            y += row.height + verticalSpacing
        }
    }
}
