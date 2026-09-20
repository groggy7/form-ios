import SwiftUI

public struct VolumeMatrixView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared

    @State private var isPlannedMode: Bool = false
    @State private var selectedWeekKey: String = ""
    @State private var selectedMuscleKey: String = "chest"
    @State private var currentView: String = "front"
    @State private var showInfoSheet: Bool = false

    public init(store: AppStore) {
        self.store = store
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

        if isPlannedMode, let program = store.state.programs.first(where: { $0.id == store.state.activeProgramId }) ?? store.state.programs.first {
            return VolumeMatrixEngine.computePlannedRoutineVolume(
                program: program,
                catalog: catalog,
                language: language.currentLanguage
            )
        } else {
            return VolumeMatrixEngine.computeLoggedVolume(
                targetWeekKey: effectiveWeekKey,
                history: store.state.history,
                catalog: catalog,
                language: language.currentLanguage
            )
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
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
                        .background(!isPlannedMode ? Color(hex: 0x0E2528) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(!isPlannedMode ? Color(hex: 0x20D791) : Color.clear, lineWidth: 1.5)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Button(action: { isPlannedMode = true }) {
                    Text(LanguageManager.t("matrix.mode.planned"))
                        .font(.system(size: 14, weight: isPlannedMode ? .bold : .medium))
                        .foregroundColor(isPlannedMode ? .white : Color(hex: 0x7E8B9B))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isPlannedMode ? Color(hex: 0x0E2528) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isPlannedMode ? Color(hex: 0x20D791) : Color.clear, lineWidth: 1.5)
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 48)
            .padding(4)
            .background(Color(hex: 0x0C1014))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x1E2630), lineWidth: 1))
            .cornerRadius(16)

            // Week Navigator (for Logged Mode)
            if !isPlannedMode {
                ZStack {
                    // Ambient diagonal teal wave canvas
                    Canvas { context, size in
                        let w = size.width
                        let h = size.height
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: h * 0.85))
                        path.addCurve(
                            to: CGPoint(x: w, y: h * 0.35),
                            control1: CGPoint(x: w * 0.3, y: h * 0.45),
                            control2: CGPoint(x: w * 0.7, y: h * 0.95)
                        )
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.addLine(to: CGPoint(x: 0, y: h))
                        path.closeSubpath()

                        context.fill(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [Color(hex: 0x0F3B3F).opacity(0.30), Color.clear]),
                                startPoint: CGPoint(x: 0, y: h),
                                endPoint: CGPoint(x: w, y: 0)
                            )
                        )

                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: h * 0.85))
                        line.addCurve(
                            to: CGPoint(x: w, y: h * 0.35),
                            control1: CGPoint(x: w * 0.3, y: h * 0.45),
                            control2: CGPoint(x: w * 0.7, y: h * 0.95)
                        )
                        context.stroke(line, with: .color(Color(hex: 0x1EC98B).opacity(0.16)), lineWidth: 1.2)
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
                .background(Color(hex: 0x11171D))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0x1E2833), lineWidth: 1))
                .cornerRadius(18)
            }

            // KPI Metrics (2x2 grid with atmospheric wave badges)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    kpiCard(title: LanguageManager.t("matrix.stat.totalSets"), value: String(format: "%.1f", report.totalEffectiveSets), subtitle: LanguageManager.t("matrix.setsUnit"), icon: "dumbbell.fill", color: AppColors.purple)
                    kpiCard(title: LanguageManager.t("matrix.stat.optimal"), value: "\(report.optimalMuscleCount)", subtitle: "MAV", icon: "checkmark.circle.fill", color: Color(hex: 0x20D791))
                }
                HStack(spacing: 10) {
                    kpiCard(title: LanguageManager.t("matrix.stat.undertrained"), value: "\(report.underTrainedCount)", subtitle: "< MEV", icon: "hourglass", color: Color(hex: 0x8E9BAE))
                    kpiCard(title: LanguageManager.t("matrix.stat.highFatigue"), value: "\(report.highFatigueCount)", subtitle: "> MAV", icon: "flame.fill", color: Color(hex: 0xFFFF6B6B))
                }
            }

            // Heatmap Figure Card ("Athlete Window")
            if let catalog = ExerciseMuscleCatalog.shared {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 14) {
                        heatmapFigure(catalog: catalog)
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

                        // Adaptive columns keep localized reference labels readable.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 8) {
                            ForEach(VolumeZone.allCases, id: \.self) { zone in
                                HStack(alignment: .top, spacing: 4) {
                                    Circle()
                                        .fill(zone.color)
                                        .frame(width: 7, height: 7)
                                        .padding(.top, 3)
                                    Text(LanguageManager.t(zone.titleKey))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
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
                        let zoneColor = summary?.zone.color ?? Color(hex: 0x62717E)

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

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        ZStack(alignment: .topLeading) {
            // Ambient corner wave glow matching theme color
            Canvas { context, size in
                let w = size.width
                let h = size.height

                var wave = Path()
                wave.move(to: CGPoint(x: w * 0.35, y: h))
                wave.addCurve(
                    to: CGPoint(x: w, y: h * 0.62),
                    control1: CGPoint(x: w * 0.55, y: h * 0.95),
                    control2: CGPoint(x: w * 0.75, y: h * 0.78)
                )
                wave.addLine(to: CGPoint(x: w, y: h))
                wave.closeSubpath()

                context.fill(
                    wave,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.22), color.opacity(0.04)]),
                        startPoint: CGPoint(x: w * 0.5, y: h),
                        endPoint: CGPoint(x: w, y: h * 0.62)
                    )
                )

                var stroke = Path()
                stroke.move(to: CGPoint(x: w * 0.35, y: h))
                stroke.addCurve(
                    to: CGPoint(x: w, y: h * 0.62),
                    control1: CGPoint(x: w * 0.55, y: h * 0.95),
                    control2: CGPoint(x: w * 0.75, y: h * 0.78)
                )
                context.stroke(stroke, with: .color(color.opacity(0.18)), lineWidth: 1.5)
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
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 114)
        .background(Color(hex: 0x10151B))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0x1F2732), lineWidth: 1))
        .cornerRadius(18)
    }

    private func heatmapFigure(catalog: ExerciseMuscleCatalog) -> some View {
        let anatomy = catalog.views[currentView]
        let paths: [(String, CGPath)] = (anatomy?.regions ?? [:]).compactMap { (muscle, pathString) in
            return (muscle, SVGPathParser.parse(pathString))
        }

        return Canvas { context, size in
            guard let anatomy, let image = ExerciseMuscleCatalog.images[currentView] else { return }
            let scale = min(size.width / catalog.width, size.height / catalog.height)
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            context.translateBy(x: (size.width - catalog.width * scale) / 2, y: (size.height - catalog.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.draw(Image(uiImage: image), in: CGRect(x: 0, y: 0, width: catalog.width, height: catalog.height))
            context.translateBy(x: -anatomy.offsetX, y: 0)
            context.blendMode = .color

            for (muscle, path) in paths {
                let summary = report.muscleSummaries[muscle]
                let zone = summary?.zone ?? .underMev
                let isSelected = (muscle == selectedMuscleKey)
                context.opacity = isSelected ? 0.95 : 0.80
                context.fill(Path(path), with: .color(zone.color))
            }
        }
    }

    private func muscleDetailCard(summary: MuscleVolumeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.localizedName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.text)
                    Text("\(String(format: "%.1f", summary.totalEffectiveSets)) \(LanguageManager.t("matrix.setsUnit")) (\(summary.directSets) direct, \(summary.indirectSets) indirect)")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Text(LanguageManager.t(summary.zone.titleKey))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(summary.zone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(summary.zone.badgeBgColor)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(summary.zone.color.opacity(0.5), lineWidth: 1))
                    .cornerRadius(8)
            }

            Text(LanguageManager.t(summary.zone.descriptionKey))
                .font(.system(size: 12))
                .foregroundColor(AppColors.muted)

            // Landmark Gauge
            landmarkGauge(summary: summary)

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
                            Text("\(item.completedSets) sets (\(String(format: "%.1f", item.effectiveSets)))")
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
