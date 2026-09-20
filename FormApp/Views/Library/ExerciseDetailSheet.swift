import SwiftUI

public enum ExerciseDetailTab: String, CaseIterable {
    case main
    case technique
    case history

    public var titleKey: String {
        switch self {
        case .main: return "exercise.tab.main"
        case .technique: return "exercise.tab.technique"
        case .history: return "exercise.tab.history"
        }
    }
}

public struct ExerciseDetailView: View {
    @ObservedObject var store: AppStore = AppStore.shared
    let initialExercise: Exercise
    var onBack: () -> Void

    @State private var selectedTab: ExerciseDetailTab = .main
    @State private var showVideoLinks: Bool = false
    @State private var showReportSheet: Bool = false

    public init(exercise: Exercise, initialTab: ExerciseDetailTab = .main, onBack: @escaping () -> Void) {
        self.initialExercise = exercise
        self.onBack = onBack
        self._selectedTab = State(initialValue: initialTab)
    }

    public init(exercise: Exercise, initialTab: ExerciseDetailTab = .main, onDismiss: @escaping () -> Void) {
        self.initialExercise = exercise
        self.onBack = onDismiss
        self._selectedTab = State(initialValue: initialTab)
    }

    private var currentExercise: Exercise {
        let key = initialExercise.name.trimmingCharacters(in: .whitespaces).lowercased()
        if let catalogExercise = store.exerciseCatalogue.first(where: { $0.key == key })?.exercise {
            if !catalogExercise.videos.isEmpty || initialExercise.videos.isEmpty {
                return catalogExercise
            }
        }
        return initialExercise
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar matching Android
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.back"))

                Text(LanguageManager.t("library.details"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Persistent Exercise Header & Segmented Tabs
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentExercise.displayName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Text(currentExercise.metadataSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.accent)
                        .tracking(0.7)
                }

                // Segmented Tab Selector
                HStack(spacing: 4) {
                    ForEach(ExerciseDetailTab.allCases, id: \.self) { tab in
                        let isSelected = tab == selectedTab
                        Button(action: { selectedTab = tab }) {
                            Text(LanguageManager.t(tab.titleKey))
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? AppColors.text : AppColors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(isSelected ? AppColors.surfaceRaised : Color.clear)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? AppColors.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .main:
                        ExerciseDetailVideo(exerciseId: currentExercise.exerciseId)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.exerciseVideoSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                        ExerciseMusclesCard(exerciseId: currentExercise.exerciseId)

                        ExerciseVideosView(
                            exercise: currentExercise,
                            onAddVideo: { showVideoLinks = true },
                            onRemoveVideo: { urlToRemove in
                                let remaining = currentExercise.videos.filter { $0 != urlToRemove }
                                store.setExerciseVideos(exerciseName: currentExercise.name, videoUrls: remaining)
                            }
                        )

                        HStack {
                            Spacer()
                            Button(action: {
                                showReportSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(LanguageManager.t("report.action"))
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(AppColors.danger)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 40)
                                .background(AppColors.danger.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppColors.danger.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    case .technique:
                        let cuesText = currentExercise.displayCues.trimmingCharacters(in: .whitespacesAndNewlines)
                        let avoidText = currentExercise.displayAvoid.trimmingCharacters(in: .whitespacesAndNewlines)

                        if cuesText.isEmpty && avoidText.isEmpty {
                            VStack(spacing: 8) {
                                Text(LanguageManager.t("exercise.technique.empty"))
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        } else {
                            if !cuesText.isEmpty {
                                TechniqueSectionView(
                                    title: LanguageManager.t("modal.exercise.cues"),
                                    text: cuesText,
                                    accent: AppColors.accent,
                                    isAvoid: false,
                                    initiallyExpanded: true,
                                    collapsible: false
                                )
                            }

                            if !avoidText.isEmpty {
                                TechniqueSectionView(
                                    title: LanguageManager.t("modal.exercise.avoid"),
                                    text: avoidText,
                                    accent: AppColors.danger,
                                    isAvoid: true,
                                    initiallyExpanded: true,
                                    collapsible: false
                                )
                            }
                        }

                    case .history:
                        let stats = PersonalRecordTracker.computeExerciseHistoryStats(
                            history: store.state.history,
                            exerciseName: currentExercise.name,
                            exerciseDisplayName: currentExercise.displayName
                        )

                        if stats.lifetimeSets == 0 {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppColors.muted)

                                Text(LanguageManager.t("exercise.history.empty"))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                                    .multilineTextAlignment(.center)

                                Text(LanguageManager.t("exercise.history.emptyHint"))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(3)
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.surface)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                        } else {
                            ExerciseHistoryStatsRow(
                                stats: stats,
                                weightUnit: store.weightUnit
                            )

                            if !stats.recentSessions.isEmpty {
                                HStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(AppColors.historyStatPrGreen.opacity(0.12))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle()
                                                    .stroke(AppColors.historyStatPrGreen.opacity(0.35), lineWidth: 1)
                                            )
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(AppColors.historyStatPrGreen)
                                    }

                                    Text(LanguageManager.t("exercise.history.recent"))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)

                                    Spacer()
                                        .frame(width: 4)

                                    Rectangle()
                                        .fill(AppColors.historyStatCardBorder.opacity(0.6))
                                        .frame(height: 1)
                                }
                                .padding(.top, 4)

                                VStack(spacing: 12) {
                                    ForEach(stats.recentSessions) { session in
                                        VStack(alignment: .leading, spacing: 0) {
                                            HStack {
                                                Text(session.workoutTitle.isEmpty ? "Workout" : session.workoutTitle)
                                                    .font(.system(size: 15, weight: .bold))
                                                    .foregroundColor(.white)

                                                Spacer()

                                                Text(formatSessionDate(session.date))
                                                    .font(.system(size: 13))
                                                    .foregroundColor(AppColors.historyStatCardTitle)
                                            }

                                            Rectangle()
                                                .fill(AppColors.historyStatCardBorder.opacity(0.6))
                                                .frame(height: 1)
                                                .padding(.vertical, 12)

                                            ForEach(Array(session.sets.enumerated()), id: \.offset) { index, setLog in
                                                if index > 0 {
                                                    Rectangle()
                                                        .fill(AppColors.historyStatCardBorder.opacity(0.4))
                                                        .frame(height: 1)
                                                        .padding(.vertical, 10)
                                                }

                                                HStack {
                                                    Text("Set \(setLog.setNumber)")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(AppColors.historyStatCardTitle)

                                                    Spacer()

                                                    let setDetail: String = {
                                                        if let w = setLog.weightKg, w > 0.0 {
                                                            return "\(store.weightUnit.formatWeight(w)) \(store.weightUnit.label) × \(setLog.reps ?? 0)"
                                                        } else {
                                                            return "\(setLog.reps ?? 0) reps"
                                                        }
                                                    }()

                                                    Text(setDetail)
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        }
                                        .padding(16)
                                        .background(AppColors.historyStatCardBg)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(AppColors.historyStatCardBorder, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .sheet(isPresented: $showVideoLinks) {
            ExerciseVideoLinksSheet(
                exercise: currentExercise,
                onDismiss: { showVideoLinks = false }
            )
        }
        .sheet(isPresented: $showReportSheet) {
            ExerciseReportSheet(
                exercise: currentExercise,
                onDismiss: { showReportSheet = false },
                onSubmit: { report in
                    ExerciseReportStore.shared.saveReport(report)
                    showReportSheet = false
                    store.showNotice(LanguageManager.t("report.submitted"))
                }
            )
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.startLocation.x < 50 && value.translation.width > 80 {
                        onBack()
                    }
                }
        )
    }
}

public typealias ExerciseDetailSheet = ExerciseDetailView

struct ExerciseHistoryStatsRow: View {
    let stats: ExerciseHistoryStats
    let weightUnit: WeightUnit

    var body: some View {
        VStack(spacing: 10) {
            // Row 1: Personal Best & Estimated 1RM
            HStack(spacing: 10) {
                // Card 1: Personal Best
                let prValue: String = {
                    if let w = stats.prWeightKg, w > 0.0 {
                        return "\(weightUnit.formatWeight(w)) \(weightUnit.label)"
                    } else if let r = stats.prReps, r > 0 {
                        return "\(r) \(LanguageManager.t("exercise.history.reps"))"
                    } else {
                        return "—"
                    }
                }()
                let prSubtitle: String = {
                    if let w = stats.prWeightKg, w > 0.0, let r = stats.prReps, r > 0 {
                        return "× \(r) \(LanguageManager.t("exercise.history.reps"))"
                    } else if let w = stats.prWeightKg, w > 0.0 {
                        return "—"
                    } else if let r = stats.prReps, r > 0 {
                        return LanguageManager.t("exercise.history.bodyweight")
                    } else {
                        return "—"
                    }
                }()

                HistoryStatCard(
                    title: LanguageManager.t("exercise.history.personalBestTitle").uppercased(),
                    iconName: "trophy.fill",
                    iconColor: AppColors.historyStatPrGreen,
                    value: prValue,
                    valueColor: .white,
                    subtitle: prSubtitle,
                    subtitleColor: AppColors.historyStatPrGreen
                )

                // Card 2: Estimated 1RM
                let est1rmValue: String = {
                    if let est = stats.estimated1rmKg {
                        return "\(weightUnit.formatWeight(est)) \(weightUnit.label)"
                    } else {
                        return "—"
                    }
                }()

                HistoryStatCard(
                    title: LanguageManager.t("exercise.history.estimated1rmTitle").uppercased(),
                    iconName: "chart.bar.fill",
                    iconColor: AppColors.historyStat1RmAmber,
                    value: est1rmValue,
                    valueColor: AppColors.historyStat1RmAmber,
                    subtitle: LanguageManager.t("exercise.history.brzyckiEq"),
                    subtitleColor: AppColors.historyStatCardTitle
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                if let source = stats.estimateSourceSet {
                    Text(LanguageManager.t("form_lab.achieved_with", [
                        "weight": "\(weightUnit.formatWeight(source.weightKg ?? 0)) \(weightUnit.label)",
                        "reps": "\(source.reps ?? 0)",
                        "date": formatSessionDate(stats.estimateSourceDate ?? ""),
                        "formula": "Brzycki"
                    ]))
                    .foregroundColor(AppColors.secondaryText)
                } else {
                    Text(LanguageManager.t("form_lab.no_weighted_sets"))
                        .foregroundColor(AppColors.secondaryText)
                }
                Text(LanguageManager.t("form_lab.estimate_policy"))
                    .foregroundColor(AppColors.muted)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
            .cornerRadius(12)

            // Row 2: Total Sets & Total Volume
            HStack(spacing: 10) {
                // Card 3: Total Sets
                HistoryStatCard(
                    title: LanguageManager.t("exercise.history.totalSetsTitle").uppercased(),
                    iconName: "repeat",
                    iconColor: AppColors.historyStatCyan,
                    value: "\(stats.lifetimeSets)",
                    valueColor: .white,
                    subtitle: LanguageManager.t("exercise.history.lifetimeSetsSubtitle"),
                    subtitleColor: AppColors.historyStatCardTitle
                )

                // Card 4: Total Volume
                let volumeValue: String = {
                    if stats.totalVolumeKg > 0.0 {
                        return "\(weightUnit.formatVolume(stats.totalVolumeKg)) \(weightUnit.label)"
                    } else {
                        return "—"
                    }
                }()

                HistoryStatCard(
                    title: LanguageManager.t("exercise.history.totalVolumeTitle").uppercased(),
                    iconName: "dumbbell.fill",
                    iconColor: AppColors.historyStatPurple,
                    value: volumeValue,
                    valueColor: .white,
                    subtitle: LanguageManager.t("exercise.history.lifetimeVolumeSubtitle"),
                    subtitleColor: AppColors.historyStatCardTitle
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct HistoryStatCard: View {
    let title: String
    let iconName: String
    let iconColor: Color
    let value: String
    let valueColor: Color
    let subtitle: String
    let subtitleColor: Color

    var body: some View {
        VStack(spacing: 0) {
            // Header Row: Circular Icon Badge + Title
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Circle()
                        .stroke(iconColor.opacity(0.35), lineWidth: 1)
                        .frame(width: 28, height: 28)
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.historyStatCardTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .kerning(0.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(valueColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(subtitleColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 114)
        .background(AppColors.historyStatCardBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.historyStatCardBorder, lineWidth: 1)
        )
    }
}

private func formatSessionDate(_ isoString: String) -> String {
    guard !isoString.isEmpty else { return "" }
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFormatter.date(from: isoString)
    if date == nil {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: isoString)
    }
    if date == nil && isoString.count == 10 && isoString.contains("-") {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        date = df.date(from: isoString)
    }
    guard let parsedDate = date else {
        return String(isoString.prefix(10))
    }
    let displayFormatter = DateFormatter()
    displayFormatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
    displayFormatter.dateFormat = "d MMM yyyy"
    return displayFormatter.string(from: parsedDate)
}

struct TechniqueSectionView: View {
    let title: String
    let text: String
    let accent: Color
    let isAvoid: Bool
    let collapsible: Bool
    @State private var isExpanded: Bool

    init(title: String, text: String, accent: Color, isAvoid: Bool, initiallyExpanded: Bool = false, collapsible: Bool = true) {
        self.title = title
        self.text = text
        self.accent = accent
        self.isAvoid = isAvoid
        self.collapsible = collapsible
        self._isExpanded = State(initialValue: collapsible ? initiallyExpanded : true)
    }

    private var effectiveExpanded: Bool {
        collapsible ? isExpanded : true
    }

    var body: some View {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: effectiveExpanded ? 12 : 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)

                Spacer()

                if collapsible {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.muted)
                        .rotationEffect(.degrees(effectiveExpanded ? 180 : 0))
                }
            }

            if effectiveExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: isAvoid ? "xmark" : "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(accent)
                                .padding(.top, 3)

                            let cleanLine = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
                            Text(LanguageManager.content(cleanLine))
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isAvoid ? AppColors.avoidBg : AppColors.cuesBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isAvoid ? AppColors.avoidBorder : AppColors.cuesBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            guard collapsible else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
