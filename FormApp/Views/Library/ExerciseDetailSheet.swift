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
    @State private var showAllHistory: Bool = false
    @State private var expandedSessionIds: Set<String> = []
    @State private var initializedFirstSessionId: String? = nil
    @State private var selectedWorkoutRecordForDetail: WorkoutSessionRecord? = nil

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
        Group {
            if showAllHistory {
                let stats = PersonalRecordTracker.computeExerciseHistoryStats(
                    history: store.state.history,
                    exerciseName: currentExercise.name,
                    exerciseDisplayName: currentExercise.displayName
                )
                ExerciseHistoryArchiveView(
                    exercise: currentExercise,
                    sessions: stats.recentSessions,
                    weightUnit: store.weightUnit,
                    onBack: { showAllHistory = false },
                    onSelectWorkoutRecord: { record in
                        selectedWorkoutRecordForDetail = record
                    }
                )
            } else {
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

                                let latestSessions = Array(stats.recentSessions.prefix(5))
                                let autoExpandId = latestSessions.first?.id

                                VStack(spacing: 12) {
                                    ForEach(latestSessions) { session in
                                        let isFirst = session.id == autoExpandId
                                        let isExpanded = expandedSessionIds.contains(session.id) || (isFirst && initializedFirstSessionId == nil)
                                        ExerciseSessionHistoryCard(
                                            session: session,
                                            isExpanded: isExpanded,
                                            weightUnit: store.weightUnit,
                                            onToggleExpand: {
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if isFirst && initializedFirstSessionId == nil {
                                                        initializedFirstSessionId = session.id
                                                        expandedSessionIds.remove(session.id)
                                                    } else if expandedSessionIds.contains(session.id) {
                                                        expandedSessionIds.remove(session.id)
                                                    } else {
                                                        expandedSessionIds.insert(session.id)
                                                    }
                                                }
                                            },
                                            onOpenWorkout: {
                                                if let rec = store.state.history.first(where: { $0.id == session.sessionId }) {
                                                    selectedWorkoutRecordForDetail = rec
                                                }
                                            }
                                        )
                                    }

                                    if stats.recentSessions.count > 0 {
                                        Button(action: { showAllHistory = true }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "calendar.badge.clock")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(AppColors.accent)

                                                Text(LanguageManager.t("exercise.history.viewAll", ["count": "\(stats.recentSessions.count)"]))
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.white)

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(AppColors.secondaryText)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 14)
                                            .background(AppColors.surfaceRaised)
                                            .cornerRadius(14)
                                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
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
        .sheet(item: $selectedWorkoutRecordForDetail) { record in
            WorkoutDetailSheet(
                record: record,
                onDismiss: { selectedWorkoutRecordForDetail = nil },
                weightUnit: store.weightUnit
            )
        }
    }
}

public typealias ExerciseDetailSheet = ExerciseDetailView

struct ExerciseHistoryStatsRow: View {
    let stats: ExerciseHistoryStats
    let weightUnit: WeightUnit
    @State private var show1RmInfoSheet = false

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
                    subtitleColor: AppColors.historyStatCardTitle,
                    onTap: { show1RmInfoSheet = true }
                )
            }

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
        .sheet(isPresented: $show1RmInfoSheet) {
            Estimated1RmInfoSheet(
                stats: stats,
                weightUnit: weightUnit,
                onDismiss: { show1RmInfoSheet = false }
            )
        }
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
    var onTap: (() -> Void)? = nil

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

                if onTap != nil {
                    Spacer(minLength: 2)
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.muted)
                }
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
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {
            onTap?()
        }
    }
}

struct Estimated1RmInfoSheet: View {
    let stats: ExerciseHistoryStats
    let weightUnit: WeightUnit
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.historyStat1RmAmber.opacity(0.15))
                            .frame(width: 36, height: 36)
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.historyStat1RmAmber.opacity(0.4), lineWidth: 1)
                            .frame(width: 36, height: 36)
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.historyStat1RmAmber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("exercise.history.estimated1rmTitle"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppColors.text)
                        Text(LanguageManager.t("exercise.history.brzyckiEq"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.muted)
                    }

                    Spacer()

                    FormModalCloseButton(action: onDismiss)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 16) {
                        // Calculation highlight card
                        let est1rmValue: String = {
                            if let est = stats.estimated1rmKg {
                                return "\(weightUnit.formatWeight(est)) \(weightUnit.label)"
                            } else {
                                return "—"
                            }
                        }()

                        VStack(spacing: 8) {
                            Text(est1rmValue)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(AppColors.historyStat1RmAmber)

                            let sourceText: String = {
                                if let source = stats.estimateSourceSet {
                                    return LanguageManager.t("form_lab.achieved_with", [
                                        "weight": "\(weightUnit.formatWeight(source.weightKg ?? 0)) \(weightUnit.label)",
                                        "reps": "\(source.reps ?? 0)",
                                        "date": formatSessionDate(stats.estimateSourceDate ?? ""),
                                        "formula": "Brzycki"
                                    ])
                                } else {
                                    return LanguageManager.t("form_lab.no_weighted_sets")
                                }
                            }()

                            Text(sourceText)
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(AppColors.historyStatCardBg)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppColors.historyStatCardBorder, lineWidth: 1)
                        )

                        // Formula card
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LanguageManager.t("form_lab.info_brzycki_epley_title"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.text)
                            Text(LanguageManager.t("form_lab.info_brzycki_epley_desc"))
                                .font(.system(size: 12))
                                .lineSpacing(3)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppColors.border, lineWidth: 1)
                        )

                        // Policy card
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LanguageManager.t("form_lab.estimate_policy"))
                                .font(.system(size: 12))
                                .lineSpacing(3)
                                .foregroundColor(AppColors.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .background(AppColors.surface.ignoresSafeArea())
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
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

private func extractMonthKeyAndTitle(_ isoString: String) -> (key: String, title: String) {
    guard !isoString.isEmpty else { return ("unknown", "Unknown") }
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFormatter.date(from: isoString)
    if date == nil {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: isoString)
    }
    if date == nil && isoString.count >= 10 {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        date = df.date(from: String(isoString.prefix(10)))
    }
    guard let parsedDate = date else {
        let prefix = String(isoString.prefix(7))
        return (prefix, prefix)
    }
    let keyFormatter = DateFormatter()
    keyFormatter.dateFormat = "yyyy-MM"
    let key = keyFormatter.string(from: parsedDate)

    let titleFormatter = DateFormatter()
    titleFormatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
    titleFormatter.dateFormat = "MMMM yyyy"
    let title = titleFormatter.string(from: parsedDate)

    return (key, title)
}

struct ExerciseSessionHistoryCard: View {
    let session: ExerciseSessionHistoryEntry
    let isExpanded: Bool
    let weightUnit: WeightUnit
    let onToggleExpand: () -> Void
    var onOpenWorkout: (() -> Void)? = nil

    private var bestSetString: String? {
        session.bestSet(weightUnit: weightUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: full-bleed interactive area
            Button(action: onToggleExpand) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text(session.workoutTitle.isEmpty ? "Workout" : session.workoutTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(formatSessionDate(session.date))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.historyStatCardTitle)
                    }

                    HStack(spacing: 8) {
                        Text(LanguageManager.t("exercise.history.setsCount", ["count": "\(session.sets.count)"]))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColors.surfaceRaised)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppColors.border.opacity(0.8), lineWidth: 1))

                        if let best = bestSetString {
                            HStack(spacing: 4) {
                                Text("\(LanguageManager.t("exercise.history.best")):")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.muted)
                                Text(best)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                            }
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.muted)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(AppColors.historyStatCardBorder.opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                // Sets section: also interactive to toggle collapse
                Button(action: onToggleExpand) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.sets.enumerated()), id: \.offset) { index, setLog in
                            if index > 0 {
                                Rectangle()
                                    .fill(AppColors.historyStatCardBorder.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.vertical, 10)
                            }

                            HStack {
                                HStack(spacing: 6) {
                                    Text("Set \(setLog.setNumber)")
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.historyStatCardTitle)

                                    if setLog.isWarmup {
                                        Text("W")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppColors.historyStat1RmAmber)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(AppColors.historyStat1RmAmber.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                }

                                Spacer()

                                let setDetail: String = {
                                    if let w = setLog.weightKg, w > 0.0 {
                                        return "\(weightUnit.formatWeight(w)) \(weightUnit.label) × \(setLog.reps ?? 0)"
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, onOpenWorkout != nil ? 4 : 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onOpenWorkout = onOpenWorkout {
                    Button(action: onOpenWorkout) {
                        HStack(spacing: 4) {
                            Text(LanguageManager.t("exercise.history.viewWorkout"))
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(AppColors.historyStatCardBg)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.historyStatCardBorder, lineWidth: 1)
        )
    }
}

struct ExerciseHistoryArchiveView: View {
    let exercise: Exercise
    let sessions: [ExerciseSessionHistoryEntry]
    let weightUnit: WeightUnit
    let onBack: () -> Void
    var onSelectWorkoutRecord: ((WorkoutSessionRecord) -> Void)? = nil

    @ObservedObject private var store = AppStore.shared
    @State private var selectedMonthKey: String = "ALL"
    @State private var expandedSessionIds: Set<String> = []
    @State private var loadedCount: Int = 20

    struct MonthOption: Identifiable, Hashable {
        var id: String { key }
        let key: String
        let title: String
        let count: Int
    }

    private var monthOptions: [MonthOption] {
        var map: [String: (title: String, count: Int)] = [:]
        for session in sessions {
            let (key, title) = extractMonthKeyAndTitle(session.date)
            let current = map[key] ?? (title: title, count: 0)
            map[key] = (title: title, count: current.count + 1)
        }
        return map.keys.sorted(by: >).map { key in
            MonthOption(key: key, title: map[key]!.title, count: map[key]!.count)
        }
    }

    private var filteredSessions: [ExerciseSessionHistoryEntry] {
        if selectedMonthKey == "ALL" {
            return sessions
        }
        return sessions.filter { extractMonthKeyAndTitle($0.date).key == selectedMonthKey }
    }

    private var visibleSessions: [ExerciseSessionHistoryEntry] {
        Array(filteredSessions.prefix(loadedCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .lineLimit(1)
                    Text("\(LanguageManager.t("exercise.history.archive")) · \(sessions.count) \(LanguageManager.t("exercise.history.sessionsCount", ["count": "\(sessions.count)"]))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Month picker / filter
            VStack(spacing: 10) {
                HStack {
                    Menu {
                        Button(action: {
                            selectedMonthKey = "ALL"
                            loadedCount = 20
                        }) {
                            HStack {
                                Text("\(LanguageManager.t("exercise.history.allMonths")) (\(sessions.count))")
                                if selectedMonthKey == "ALL" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(monthOptions) { opt in
                            Button(action: {
                                selectedMonthKey = opt.key
                                loadedCount = 20
                            }) {
                                HStack {
                                    Text("\(opt.title) (\(opt.count))")
                                    if selectedMonthKey == opt.key {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.accent)

                            let currentTitle: String = {
                                if selectedMonthKey == "ALL" {
                                    return "\(LanguageManager.t("exercise.history.allMonths")) (\(sessions.count))"
                                }
                                let title = monthOptions.first(where: { $0.key == selectedMonthKey })?.title ?? selectedMonthKey
                                let count = filteredSessions.count
                                return "\(title) (\(count))"
                            }()

                            Text(currentTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                    }

                    Spacer()

                    if selectedMonthKey != "ALL" {
                        Button(action: {
                            selectedMonthKey = "ALL"
                            loadedCount = 20
                        }) {
                            Text(LanguageManager.t("common.clear"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // Quick horizontal month chips strip
                if !monthOptions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let isAllSelected = selectedMonthKey == "ALL"
                            Button(action: {
                                selectedMonthKey = "ALL"
                                loadedCount = 20
                            }) {
                                Text("\(LanguageManager.t("exercise.history.allMonths"))")
                                    .font(.system(size: 12, weight: isAllSelected ? .bold : .medium))
                                    .foregroundColor(isAllSelected ? .white : AppColors.secondaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isAllSelected ? AppColors.accent.opacity(0.2) : AppColors.surface)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isAllSelected ? AppColors.accent : AppColors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)

                            ForEach(monthOptions) { opt in
                                let isSelected = selectedMonthKey == opt.key
                                Button(action: {
                                    selectedMonthKey = opt.key
                                    loadedCount = 20
                                }) {
                                    Text("\(opt.title) (\(opt.count))")
                                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .white : AppColors.secondaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? AppColors.accent.opacity(0.2) : AppColors.surface)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 12)

            // Scrollable progressive list of sessions
            ScrollView {
                LazyVStack(spacing: 12) {
                    if visibleSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 28))
                                .foregroundColor(AppColors.muted)
                            Text(LanguageManager.t("exercise.history.noSessionsInMonth"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(visibleSessions) { session in
                            ExerciseSessionHistoryCard(
                                session: session,
                                isExpanded: expandedSessionIds.contains(session.id),
                                weightUnit: weightUnit,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedSessionIds.contains(session.id) {
                                            expandedSessionIds.remove(session.id)
                                        } else {
                                            expandedSessionIds.insert(session.id)
                                        }
                                    }
                                },
                                onOpenWorkout: {
                                    if let rec = store.state.history.first(where: { $0.id == session.sessionId }) {
                                        onSelectWorkoutRecord?(rec)
                                    }
                                }
                            )
                        }

                        // Progressive batching / pagination trigger
                        if visibleSessions.count < filteredSessions.count {
                            Button(action: {
                                withAnimation {
                                    loadedCount += 20
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("\(LanguageManager.t("exercise.history.loadMore")) (\(filteredSessions.count - visibleSessions.count))")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(AppColors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppColors.surfaceRaised)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            .onAppear {
                                if loadedCount < filteredSessions.count {
                                    loadedCount += 20
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
    }
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
