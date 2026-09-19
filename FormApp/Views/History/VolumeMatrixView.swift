import SwiftUI

public struct VolumeMatrixView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared

    @State private var isPlannedMode: Bool = false
    @State private var selectedWeekKey: String = ""
    @State private var selectedMuscleKey: String = "chest"
    @State private var currentView: String = "front"

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
            // Mode Selector: Logged vs Planned
            HStack(spacing: 4) {
                Button(action: { isPlannedMode = false }) {
                    Text(LanguageManager.t("matrix.mode.completed"))
                        .font(.system(size: 13, weight: !isPlannedMode ? .semibold : .medium))
                        .foregroundColor(!isPlannedMode ? AppColors.text : AppColors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(!isPlannedMode ? AppColors.surfaceRaised : Color.clear)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)

                Button(action: { isPlannedMode = true }) {
                    Text(LanguageManager.t("matrix.mode.planned"))
                        .font(.system(size: 13, weight: isPlannedMode ? .semibold : .medium))
                        .foregroundColor(isPlannedMode ? AppColors.text : AppColors.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isPlannedMode ? AppColors.surfaceRaised : Color.clear)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 44)
            .padding(4)
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(12)

            // Week Navigator (for Logged Mode)
            if !isPlannedMode {
                HStack {
                    Button(action: { shiftWeek(-1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 36, height: 36)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(effectiveWeekKey == currentWeekKey ? LanguageManager.t("matrix.thisWeek") : effectiveWeekKey)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.text)
                        Text(effectiveWeekKey)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.muted)
                    }

                    Spacer()

                    Button(action: { shiftWeek(1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(effectiveWeekKey < currentWeekKey ? AppColors.secondaryText : AppColors.muted.opacity(0.3))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(effectiveWeekKey >= currentWeekKey)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                .cornerRadius(14)
            }

            // KPI Metrics
            HStack(spacing: 8) {
                kpiCard(title: LanguageManager.t("matrix.stat.totalSets"), value: String(format: "%.1f", report.totalEffectiveSets), subtitle: LanguageManager.t("matrix.setsUnit"), icon: "dumbbell.fill", color: AppColors.purple)
                kpiCard(title: LanguageManager.t("matrix.stat.optimal"), value: "\(report.optimalMuscleCount)", subtitle: "MAV", icon: "checkmark.circle.fill", color: Color(hex: 0x20D791))
                kpiCard(title: LanguageManager.t("matrix.stat.undertrained"), value: "\(report.underTrainedCount)", subtitle: "< MEV", icon: "hourglass", color: Color(hex: 0x8E9BAE))
                kpiCard(title: LanguageManager.t("matrix.stat.highFatigue"), value: "\(report.highFatigueCount)", subtitle: "> MAV", icon: "flame.fill", color: Color(hex: 0xFF897B))
            }

            // Heatmap Figure Card
            if let catalog = ExerciseMuscleCatalog.shared {
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

                    // Zone Legend (2 centered rows for clean, unclipped presentation on any screen size)
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            ForEach([VolumeZone.underMev, VolumeZone.progressive, VolumeZone.optimalMav], id: \.self) { zone in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(zone.color)
                                        .frame(width: 7, height: 7)
                                    Text(LanguageManager.t(zone.titleKey))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.muted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            ForEach([VolumeZone.highFatigue, VolumeZone.overMrv], id: \.self) { zone in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(zone.color)
                                        .frame(width: 7, height: 7)
                                    Text(LanguageManager.t(zone.titleKey))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(AppColors.muted)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
                .background(AppColors.surface)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColors.border, lineWidth: 1))
                .cornerRadius(20)
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
    }

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppColors.muted)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(AppColors.text)
            Text(subtitle)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(AppColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .cornerRadius(14)
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
