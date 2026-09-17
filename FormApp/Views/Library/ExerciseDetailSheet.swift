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

                        Button(action: {
                            showReportSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "flag")
                                    .font(.system(size: 14, weight: .medium))
                                Text(LanguageManager.t("report.action"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AppColors.muted)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.plain)
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
                            // Summary card
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    let prText: String = {
                                        if let w = stats.prWeightKg, w > 0.0 {
                                            return "\(store.weightUnit.formatWeight(w)) \(store.weightUnit.label) × \(stats.prReps ?? 0)"
                                        } else if let r = stats.prReps, r > 0 {
                                            return "\(r) reps"
                                        } else {
                                            return "—"
                                        }
                                    }()

                                    HistoryMetricTile(
                                        label: LanguageManager.t("exercise.history.pr"),
                                        value: prText,
                                        highlight: true
                                    )

                                    let est1rmText: String = {
                                        if let est = stats.estimated1rmKg {
                                            return "\(store.weightUnit.formatWeight(est)) \(store.weightUnit.label)"
                                        } else {
                                            return "—"
                                        }
                                    }()

                                    HistoryMetricTile(
                                        label: LanguageManager.t("exercise.history.estimated1rm"),
                                        value: est1rmText,
                                        highlight: false
                                    )
                                }

                                HStack(spacing: 12) {
                                    let volumeText: String = {
                                        if stats.totalVolumeKg > 0.0 {
                                            return "\(store.weightUnit.formatVolume(stats.totalVolumeKg)) \(store.weightUnit.label)"
                                        } else {
                                            return "0 \(store.weightUnit.label)"
                                        }
                                    }()

                                    HistoryMetricTile(
                                        label: LanguageManager.t("exercise.history.volume"),
                                        value: volumeText,
                                        highlight: false
                                    )

                                    HistoryMetricTile(
                                        label: LanguageManager.t("exercise.history.sets"),
                                        value: "\(stats.lifetimeSets)",
                                        highlight: false
                                    )
                                }
                            }
                            .padding(16)
                            .background(AppColors.surface)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))

                            if !stats.recentSessions.isEmpty {
                                Text(LanguageManager.t("exercise.history.recent"))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                                    .padding(.top, 4)

                                ForEach(stats.recentSessions) { session in
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(session.workoutTitle.isEmpty ? "Workout" : session.workoutTitle)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(AppColors.text)

                                            Spacer()

                                            Text(formatSessionDate(session.date))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(session.sets, id: \.self) { setLog in
                                                HStack {
                                                    Text("Set \(setLog.setNumber)")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(AppColors.secondaryText)

                                                    Spacer()

                                                    let setDetail: String = {
                                                        if let w = setLog.weightKg, w > 0.0 {
                                                            return "\(store.weightUnit.formatWeight(w)) \(store.weightUnit.label) × \(setLog.reps ?? 0)"
                                                        } else {
                                                            return "\(setLog.reps ?? 0) reps"
                                                        }
                                                    }()

                                                    Text(setDetail)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(AppColors.text)
                                                }
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(AppColors.surface)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
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

struct HistoryMetricTile: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(highlight ? AppColors.accent : AppColors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.background)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
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
