import SwiftUI

public struct HistoryDayDetailData: Identifiable {
    public var id: String { dateString }
    public let date: Date
    public let dateString: String
    public let status: WorkoutDayStatus
    public let sessionRecord: WorkoutSessionRecord?
    public let workout: Workout?

    public init(
        date: Date,
        dateString: String,
        status: WorkoutDayStatus,
        sessionRecord: WorkoutSessionRecord?,
        workout: Workout?
    ) {
        self.date = date
        self.dateString = dateString
        self.status = status
        self.sessionRecord = sessionRecord
        self.workout = workout
    }
}

public struct HistoryView: View {
    @ObservedObject var store: AppStore
    var onOpenSettings: () -> Void
    var onSelectRecord: (WorkoutSessionRecord) -> Void

    public enum HistoryTab {
        case calendar
        case volumeMatrix
        case formLab
    }

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var activeTab: HistoryTab = .calendar
    @State private var activePaywallFeature: ProFeature? = nil
    @State private var displayedDate: Date = Date()
    @State private var selectedDateString: String? = nil

    public init(
        store: AppStore,
        initialTab: HistoryTab = .calendar,
        onOpenSettings: @escaping () -> Void,
        onSelectRecord: @escaping (WorkoutSessionRecord) -> Void
    ) {
        self.store = store
        self._activeTab = State(initialValue: initialTab)
        self.onOpenSettings = onOpenSettings
        self.onSelectRecord = onSelectRecord
    }

    public var body: some View {
        if let detailDay = store.selectedHistoryDetailDay,
           let detail = resolveDayDetail(for: detailDay) {
            HistoryDetailView(
                detail: detail,
                history: store.state.history,
                onBack: {
                    store.selectedHistoryDetailDay = nil
                },
                onActionWorkout: {
                    store.selectedHistoryDetailDay = nil
                    handleWorkoutAction(detail: detail)
                },
                weightUnit: store.weightUnit
            )
        } else {
            let calendar = Calendar.current
            let today = Date()
            let todayStr = WorkoutCalendar.formatDate(today)
            let isCurrentMonth = calendar.isDate(displayedDate, equalTo: today, toGranularity: .month)
            let statuses = store.calendarStatuses(today: today)
            let weeks = WorkoutCalendar.monthWeeks(for: displayedDate)

            let currentSelectedDetail: HistoryDayDetailData? = {
                guard let explicit = selectedDateString else { return nil }
                return resolveDayDetail(for: explicit)
            }()

            VStack(spacing: 16) {
                // Header row
                HStack(alignment: .center) {
                    Text(LanguageManager.t("nav.history"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Spacer()

                    if activeTab == .calendar && !isCurrentMonth {
                        Button(action: {
                            displayedDate = Date()
                            selectedDateString = nil
                        }) {
                            Text(LanguageManager.t("history.thisMonth"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }

                    FormHeaderIconButton(
                        icon: "gearshape.fill",
                        contentDescription: LanguageManager.t("settings.title"),
                        onClick: onOpenSettings
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Segmented Control: Calendar vs Volume Matrix vs Form Lab
                HStack(spacing: 3) {
                    Button(action: { activeTab = .calendar }) {
                        Text(LanguageManager.t("history.calendar"))
                            .font(.system(size: 13, weight: activeTab == .calendar ? .semibold : .medium))
                            .foregroundColor(activeTab == .calendar ? AppColors.text : AppColors.muted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(activeTab == .calendar ? AppColors.surfaceRaised : Color.clear)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        activeTab = .volumeMatrix
                    }) {
                        HStack(spacing: 3) {
                            Text(LanguageManager.t("history.volumeMatrix"))
                                .font(.system(size: 11, weight: activeTab == .volumeMatrix ? .semibold : .medium))
                                .foregroundColor(activeTab == .volumeMatrix ? AppColors.text : AppColors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            ProBadge()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(activeTab == .volumeMatrix ? AppColors.surfaceRaised : Color.clear)
                        .cornerRadius(9)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        activeTab = .formLab
                    }) {
                        HStack(spacing: 3) {
                            Text(LanguageManager.t("history.formLab"))
                                .font(.system(size: 11, weight: activeTab == .formLab ? .semibold : .medium))
                                .foregroundColor(activeTab == .formLab ? AppColors.text : AppColors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            ProBadge()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(activeTab == .formLab ? AppColors.surfaceRaised : Color.clear)
                        .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 44)
                .padding(3)
                .background(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .cornerRadius(12)
                .padding(.horizontal, 20)

                if activeTab == .volumeMatrix {
                    if proManager.isFeatureUnlocked(.volumeMatrix) {
                        ScrollView {
                            VolumeMatrixView(store: store)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    } else {
                        let effectiveHistory = ProPreviewData.hasWorkingHistory(store.state.history) ? store.state.history : ProPreviewData.previewHistory()
                        ZStack {
                            ScrollView(showsIndicators: false) {
                                VolumeMatrixView(store: store, customHistory: effectiveHistory)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 24)
                            }
                            .scrollDisabled(true)
                            .blur(radius: 6)
                            .opacity(0.85)
                            .allowsHitTesting(false)

                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.12),
                                    Color.black.opacity(0.25),
                                    Color.black.opacity(0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)

                            ProPaywallPreview(feature: .volumeMatrix) {
                                activePaywallFeature = .volumeMatrix
                            }
                            .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activePaywallFeature = .volumeMatrix
                        }
                    }
                } else if activeTab == .formLab {
                    if proManager.isFeatureUnlocked(.formLab) {
                        ScrollView {
                            FormLabView(store: store)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    } else {
                        let effectiveHistory = ProPreviewData.hasWorkingHistory(store.state.history) ? store.state.history : ProPreviewData.previewHistory()
                        ZStack {
                            ScrollView(showsIndicators: false) {
                                FormLabView(store: store, customHistory: effectiveHistory)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 24)
                            }
                            .scrollDisabled(true)
                            .blur(radius: 6)
                            .opacity(0.85)
                            .allowsHitTesting(false)

                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.12),
                                    Color.black.opacity(0.25),
                                    Color.black.opacity(0.42)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)

                            ProPaywallPreview(feature: .formLab) {
                                activePaywallFeature = .formLab
                            }
                            .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activePaywallFeature = .formLab
                        }
                    }
                } else {
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(spacing: 16) {
                                // Month Calendar Card
                                VStack(spacing: 10) {
                        // Month navigation row
                        HStack {
                            Button(action: { changeMonth(by: -1) }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text(monthYearString(from: displayedDate))
                                .font(.system(size: 19, weight: .medium))
                                .foregroundColor(AppColors.text)

                            Spacer()

                            Button(action: { changeMonth(by: 1) }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isCurrentMonth ? AppColors.muted.opacity(0.3) : AppColors.secondaryText)
                                    .frame(width: 36, height: 36)
                            }
                            .disabled(isCurrentMonth)
                            .buttonStyle(.plain)
                        }

                        // Weekday headers
                        HStack(spacing: 0) {
                            ForEach(weekdaySymbols(), id: \.self) { symbol in
                                Text(symbol)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.muted)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        // Weeks grid
                        VStack(spacing: 4) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                HStack(spacing: 0) {
                                    ForEach(Array(week.enumerated()), id: \.offset) { _, dateOpt in
                                        BoxDayCell(
                                            dateOpt: dateOpt,
                                            todayStr: todayStr,
                                            statuses: statuses,
                                            isSelected: (dateOpt != nil && WorkoutCalendar.formatDate(dateOpt!) == selectedDateString),
                                            onSelectDay: { date, dateString, status in
                                                if selectedDateString == dateString {
                                                    selectedDateString = nil
                                                } else {
                                                    selectedDateString = dateString
                                                }
                                            }
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 20)

                    // Calendar Legend Row
                    HStack {
                        Spacer()
                        legendItem(color: AppColors.completedGreen, label: LanguageManager.t("history.completed"))
                        Spacer()
                        legendItem(color: AppColors.unfinishedOrange, label: LanguageManager.t("history.unfinished"))
                        Spacer()
                        legendItem(color: AppColors.missedRed, label: LanguageManager.t("history.missed"))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)

                    // Inline Preview Card
                    if let detail = currentSelectedDetail {
                        HistoryDayPreviewCard(
                            detail: detail,
                            history: store.state.history,
                            onOpenDetail: {
                                store.selectedHistoryDetailDay = detail.dateString
                            },
                            weightUnit: store.weightUnit
                        )
                        .id("history-day-preview-card")
                        .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 24)
                        .id("history-bottom-anchor")
                }
                .onChange(of: selectedDateString) { _, newDate in
                    if newDate != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.easeInOut(duration: 0.55)) {
                                proxy.scrollTo("history-bottom-anchor", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}
    .sheet(item: $activePaywallFeature) { feat in
        ProPaywallSheet(feature: feat, onDismiss: { activePaywallFeature = nil })
    }
}
}

    private func handleWorkoutAction(detail: HistoryDayDetailData) {
        guard let workout = detail.workout else { return }
        let programId = store.activeProgram?.id
            ?? store.state.programs.first(where: { $0.workouts.contains(where: { $0.id == workout.id }) })?.id
        guard let progId = programId else { return }

        if let active = store.activeSession, active.workout.id == workout.id {
            store.currentView = .today
            return
        }

        if store.startActiveSession(
            programId: progId,
            workout: workout,
            allowPast: true,
            unfinishedRecordId: detail.sessionRecord?.id
        ) {
            store.currentView = .today
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText)
        }
    }

    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedDate) {
            displayedDate = newDate
            selectedDateString = nil
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func weekdaySymbols() -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        cal.firstWeekday = 2 // Monday
        let symbols = cal.shortWeekdaySymbols
        return [symbols[1], symbols[2], symbols[3], symbols[4], symbols[5], symbols[6], symbols[0]]
    }

    private func resolveDayDetail(for dateString: String) -> HistoryDayDetailData? {
        guard let date = WorkoutCalendar.parseDate(dateString) ?? WorkoutCalendar.parseIsoTimestamp(dateString) else {
            return nil
        }
        let statuses = store.calendarStatuses(today: Date())
        let status = statuses[dateString]

        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date)
        let dayOfWeek = (weekday + 5) % 7 + 1 // 1=Mon..7=Sun

        let activeRecord: WorkoutSessionRecord? = {
            guard let draft = store.activeSession else { return nil }
            let activeDay = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })?.date
                ?? WorkoutCalendar.localDate(from: draft.startedAt)
                ?? WorkoutCalendar.scheduledDate(forWeekday: draft.workout.day, relativeTo: Date())
            if activeDay == dateString {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                return SessionProgress.from(draft: draft, nowEpochMillis: now)
                    .record(draft: draft, completedAtEpochMillis: now)
            }
            return nil
        }()

        let sessionRecord: WorkoutSessionRecord? = activeRecord ?? store.state.history.first { rec in
            if let calDate = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == dateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == dateString || completedDate == dateString
        }

        let workout: Workout?
        if let rec = sessionRecord {
            workout = store.activeProgram?.workouts.first(where: { $0.id == rec.workoutId })
                ?? store.state.programs.flatMap(\.workouts).first(where: { $0.id == rec.workoutId })
                ?? store.activeProgram?.workouts.first(where: { $0.day == dayOfWeek })
        } else {
            workout = store.activeProgram?.workouts.first(where: { $0.day == dayOfWeek })
                ?? store.state.programs.flatMap(\.workouts).first(where: { $0.day == dayOfWeek })
        }

        let hasSets: Bool = {
            if let rec = sessionRecord {
                if rec.totalCompletedSets > 0 { return true }
                return rec.exerciseLogs.contains { log in
                    log.sets.contains { ($0.reps ?? 0) > 0 || ($0.weightKg ?? 0) > 0 }
                }
            }
            if let active = store.activeSession {
                let allSets = active.setsByExercise.values.flatMap { $0 }
                if allSets.contains(where: { $0.isCompleted }) { return true }
            }
            return false
        }()
        let isToday = (dateString == WorkoutCalendar.formatDate(Date()))
        let effectiveStatus: WorkoutDayStatus = {
            if sessionRecord?.isComplete == true {
                return .completed
            }
            if isToday {
                return hasSets ? .unfinished : (status ?? .unfinished)
            } else {
                return hasSets ? .unfinished : .missed
            }
        }()

        return HistoryDayDetailData(
            date: date,
            dateString: dateString,
            status: effectiveStatus,
            sessionRecord: sessionRecord,
            workout: workout
        )
    }
}

// MARK: - Calendar Day Cell
private struct BoxDayCell: View {
    let dateOpt: Date?
    let todayStr: String
    let statuses: [String: WorkoutDayStatus]
    let isSelected: Bool
    let onSelectDay: (Date, String, WorkoutDayStatus) -> Void

    var body: some View {
        ZStack {
            if let date = dateOpt {
                let dateString = WorkoutCalendar.formatDate(date)
                let status = statuses[dateString]
                let isToday = (dateString == todayStr)
                let calendar = Calendar.current
                let dayNumber = calendar.component(.day, from: date)
                let isClickable = (status == .unfinished || status == .missed || status == .completed)

                ZStack {
                    // Outer border ring for selected day or today
                    if isSelected {
                        Circle()
                            .stroke(AppColors.accent, lineWidth: 2)
                            .frame(width: 38, height: 38)
                    } else if isToday {
                        Circle()
                            .stroke(AppColors.text.opacity(0.8), lineWidth: 1)
                            .frame(width: 38, height: 38)
                    }

                    // Status colored circle
                    if let status = status {
                        let color: Color = {
                            switch status {
                            case .completed: return AppColors.completedGreen
                            case .unfinished: return AppColors.unfinishedOrange
                            case .missed: return AppColors.missedRed
                            }
                        }()

                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)

                        Text("\(dayNumber)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.background)
                    } else {
                        Text("\(dayNumber)")
                            .font(.system(size: 15, weight: isToday ? .semibold : .regular))
                            .foregroundColor(dateString > todayStr ? AppColors.muted.opacity(0.45) : AppColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isClickable, let status = status {
                        onSelectDay(date, dateString, status)
                    }
                }
                .accessibilityIdentifier("history-day-\(dateString)")
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - History Day Detail Sheet
public struct HistoryDayDetailSheet: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var onDismiss: () -> Void
    var onActionWorkout: (() -> Void)? = nil

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord] = [],
        onDismiss: @escaping () -> Void,
        onActionWorkout: (() -> Void)? = nil,
        initiallyExpanded: Bool = false
    ) {
        self.detail = detail
        self.history = history
        self.onDismiss = onDismiss
        self.onActionWorkout = onActionWorkout
    }

    public var body: some View {
        let formattedDate = formattedFullDate(for: detail.date)

        let workoutTitle = detail.sessionRecord?.workoutTitle
            ?? detail.workout?.title
            ?? LanguageManager.t("history.scheduledWorkout")

        let items = exerciseProgressList()
        let allCompleted = !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let effectiveStatus: WorkoutDayStatus = (detail.status == .unfinished && allCompleted) ? .completed : detail.status
        let isMissed = effectiveStatus == .missed || (!items.isEmpty && items.allSatisfy { $0.completedSets == 0 } && detail.date < Calendar.current.startOfDay(for: Date()))
        let showActionButton = onActionWorkout != nil && !allCompleted
        let actionButtonText = isMissed ? LanguageManager.t("history.startWorkout") : LanguageManager.t("history.resumeWorkout")

        let completedExercises = items.filter { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let halfwayExercises = items.filter { $0.completedSets > 0 && $0.completedSets < $0.plannedSets }
        let unstartedExercises = items.filter { $0.completedSets == 0 }

        let totalCompletedSets = detail.sessionRecord?.totalCompletedSets ?? items.reduce(0) { $0 + $1.completedSets }
        let totalPlannedSets = max(1, items.reduce(0) { $0 + $1.plannedSets })
        let displayCompletedSets = effectiveStatus == .missed ? 0 : totalCompletedSets
        let durationSeconds = detail.sessionRecord?.durationSeconds ?? 0
        let totalVolumeKg = detail.sessionRecord?.totalVolumeKg ?? 0.0

        let progressFraction: Double = effectiveStatus == .missed ? 0.0 : min(1.0, max(0.0, Double(totalCompletedSets) / Double(totalPlannedSets)))
        let progressPercent = Int(progressFraction * 100)

        let formattedDuration: String = {
            let isTr = LanguageManager.shared.currentLanguage.lowercased().hasPrefix("tr")
            if effectiveStatus == .missed || durationSeconds <= 0 {
                return isTr ? "0dk 0sn" : "0m 0s"
            }
            if durationSeconds >= 3600 {
                let hours = durationSeconds / 3600
                let mins = (durationSeconds % 3600) / 60
                return isTr ? "\(hours)sa \(mins)dk" : "\(hours)h \(mins)m"
            } else {
                let mins = durationSeconds / 60
                let secs = durationSeconds % 60
                return isTr ? "\(mins)dk \(secs)sn" : "\(mins)m \(secs)s"
            }
        }()

        let formattedVolume: String = {
            if effectiveStatus == .missed { return "0" }
            return WorkoutSessionUtils.formatWeight(totalVolumeKg)
        }()

        let (statusColor, statusBg, statusText): (Color, Color, String) = {
            switch effectiveStatus {
            case .unfinished:
                return (AppColors.unfinishedOrange, AppColors.unfinishedOrange.opacity(0.15), LanguageManager.t("history.unfinished"))
            case .missed:
                return (AppColors.missedRed, AppColors.missedRed.opacity(0.15), LanguageManager.t("history.missed"))
            case .completed:
                return (AppColors.completedGreen, AppColors.completedGreen.opacity(0.15), LanguageManager.t("history.completed"))
            }
        }()

        ZStack(alignment: .bottom) {
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header (close button removed as back navigation is handled by top-left bar)
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)

                    Text(workoutTitle)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppColors.text)
                }

                // Status Pill Tag
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(statusBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(statusColor.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .accessibilityIdentifier("history-detail-status")

                // Key Stats (Sets | Duration | Volume)
                HStack(spacing: 0) {
                    // Sets
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("history.sets").isEmpty ? "Sets" : LanguageManager.t("history.sets"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(displayCompletedSets) / \(totalPlannedSets)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 36)

                    // Duration
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("history.duration").isEmpty ? "Duration" : LanguageManager.t("history.duration"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text(formattedDuration)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)

                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 36)

                    // Volume
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t("history.volume").isEmpty ? "Volume" : LanguageManager.t("history.volume"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(formattedVolume) kg")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                }

                // Progress Bar + Percentage Row
                HStack(spacing: 12) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.progressTrack)
                                .frame(height: 8)

                            Capsule()
                                .fill(effectiveStatus == .completed ? AppColors.completedGreen : AppColors.accent)
                                .frame(width: geometry.size.width * CGFloat(progressFraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text(LanguageManager.formatPercent(progressPercent))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.text)
                }

                // Content Sections
                if allCompleted {
                    // Completed Day (Picture 1)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LanguageManager.t("history.exercises").isEmpty ? "Exercises" : LanguageManager.t("history.exercises"))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppColors.text)
                            Spacer()
                            Text("\(items.count)")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 20, alignment: .center)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                exerciseRow(item: item, isCompleted: true)
                                if index < items.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                } else if isMissed {
                    // Missed Day (Unstarted past day)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LanguageManager.t("history.exercises").isEmpty ? "Exercises" : LanguageManager.t("history.exercises"))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppColors.text)
                            Spacer()
                            Text("\(items.count)")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(AppColors.secondaryText)
                                .frame(width: 20, alignment: .center)
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                exerciseRow(item: item, isCompleted: false)
                                if index < items.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                } else {
                    // Half-Done / In-Progress Workout (Picture 2)
                    VStack(alignment: .leading, spacing: 20) {
                        // Section 1: Continue Workout Card (Compact, Chevron, No Resume Button)
                        if !halfwayExercises.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LanguageManager.t("history.continueWorkout").isEmpty ? "Continue workout" : LanguageManager.t("history.continueWorkout"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)

                                ForEach(halfwayExercises) { item in
                                    let setsLeft = max(0, item.plannedSets - item.completedSets)
                                    let progress = min(1.0, max(0.0, Double(item.completedSets) / Double(max(1, item.plannedSets))))

                                    Button(action: { onActionWorkout?() }) {
                                        VStack(alignment: .leading, spacing: 10) {
                                            // Row 1: Exercise title & Sets left badge
                                            HStack {
                                                Text(item.name)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(AppColors.text)
                                                    .lineLimit(1)

                                                Spacer()

                                                Text(LanguageManager.formatSetsLeft(setsLeft))
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(AppColors.accent)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                            .fill(Color(hex: 0x15322F))
                                                    )
                                            }

                                            // Row 2: Subtitle & Chevron right
                                            HStack {
                                                let setsText = LanguageManager.formatExerciseSetsCompleted(completed: item.completedSets, planned: item.plannedSets)
                                                let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                                                let repsLabel = LanguageManager.shared.currentLanguage.lowercased().hasPrefix("tr") ? "tekrar" : "reps"
                                                let detailText: String = {
                                                    if let w = item.topSetWeight, let r = item.topSetReps {
                                                        return "\(setsText) · \(topLabel): \(WorkoutSessionUtils.formatWeight(w)) kg × \(r) \(repsLabel)"
                                                    }
                                                    return setsText
                                                }()

                                                Text(detailText)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(AppColors.secondaryText)
                                                    .lineLimit(1)

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(AppColors.secondaryText)
                                            }

                                            // Row 3: Mini Progress Bar
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color(hex: 0x192524))
                                                        .frame(height: 6)
                                                    Capsule()
                                                        .fill(AppColors.accent)
                                                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                                                }
                                            }
                                            .frame(height: 6)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill(AppColors.toContinueSurface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(AppColors.accent, lineWidth: 1.5)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("history-continue-card")
                                }
                            }
                        }

                        // Section 2: Completed Exercises
                        if !completedExercises.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(LanguageManager.t("history.completedSection").isEmpty ? "Completed" : LanguageManager.t("history.completedSection"))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppColors.text)
                                    Spacer()
                                    Text("\(completedExercises.count)")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(width: 20, alignment: .center)
                                }

                                VStack(spacing: 0) {
                                    ForEach(Array(completedExercises.enumerated()), id: \.element.id) { index, item in
                                        exerciseRow(item: item, isCompleted: true)
                                        if index < completedExercises.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.08))
                                        }
                                    }
                                }
                            }
                        }

                        // Section 3: Remaining Exercises
                        if !unstartedExercises.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(LanguageManager.t("history.remainingSection").isEmpty ? "Remaining" : LanguageManager.t("history.remainingSection"))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppColors.text)
                                    Spacer()
                                    Text("\(unstartedExercises.count)")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                        .frame(width: 20, alignment: .center)
                                }

                                VStack(spacing: 0) {
                                    ForEach(Array(unstartedExercises.enumerated()), id: \.element.id) { index, item in
                                        exerciseRow(item: item, isCompleted: false)
                                        if index < unstartedExercises.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.08))
                                        }
                                    }
                                }
                            }
                        }

                        }
                    }

                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, showActionButton ? 96 : 24)
            }

            if showActionButton, let action = onActionWorkout {
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            AppColors.surface.opacity(0),
                            AppColors.surface.opacity(0.85),
                            AppColors.surface
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)

                    Button(action: action) {
                        Text(actionButtonText)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history-action-button")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .background(AppColors.surface)
                }
            }
        }
        .background(AppColors.surface.ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func exerciseRow(item: ExerciseProgressItem, isCompleted: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .lineLimit(1)

                    if item.isPr {
                        Text("PR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.orangePrText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(AppColors.orangePrBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(AppColors.orangePrBorder, lineWidth: 1)
                                    )
                            )
                    }
                }

                let subText: String = {
                    if isCompleted {
                        let setsFraction = LanguageManager.formatSetsFraction(completed: item.completedSets, total: item.plannedSets)
                        let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                        if let w = item.topSetWeight, let r = item.topSetReps {
                            return "\(setsFraction) · \(topLabel): \(WorkoutSessionUtils.formatWeight(w)) kg × \(r)"
                        }
                        return setsFraction
                    } else {
                        return item.prescription.isEmpty
                            ? LanguageManager.formatSetsFraction(completed: item.completedSets, total: item.plannedSets)
                            : item.prescription
                    }
                }()

                Text(subText)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: 0x3DDB84))
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppColors.missedRed)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("history-exercise-\(item.name)")
    }

    private func formattedFullDate(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        df.dateStyle = .full
        return df.string(from: date).capitalized
    }

    private func formattedShortDate(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        df.dateFormat = "MMM d"
        return df.string(from: date).capitalized
    }

    private struct ExerciseProgressItem: Identifiable {
        var id: String { name }
        let name: String
        let prescription: String
        let completedSets: Int
        let plannedSets: Int
        let topSetWeight: Double?
        let topSetReps: Int?
        let isPr: Bool
    }

    private func exerciseProgressList() -> [ExerciseProgressItem] {
        let isExplicitlyCompleted = detail.status == .completed || detail.sessionRecord?.isComplete == true
        let prExercises: Set<String> = {
            if let rec = detail.sessionRecord {
                return PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: rec)
            }
            return []
        }()

        func extractTopSet(log: SessionExerciseLog?) -> (Double?, Int?) {
            guard let validSets = log?.sets.filter({ ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }), !validSets.isEmpty else {
                return (nil, nil)
            }
            let top = validSets.max { a, b in
                if (a.weightKg ?? 0.0) != (b.weightKg ?? 0.0) {
                    return (a.weightKg ?? 0.0) < (b.weightKg ?? 0.0)
                }
                return (a.reps ?? 0) < (b.reps ?? 0)
            }
            return (top?.weightKg, top?.reps)
        }

        if isExplicitlyCompleted, let rec = detail.sessionRecord, !rec.exerciseLogs.isEmpty {
            return rec.exerciseLogs.map { log in
                let logKey = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                let exercise = detail.workout?.exercises.first { ex in
                    ex.name.trimmingCharacters(in: .whitespaces).lowercased() == logKey ||
                    ex.displayName.trimmingCharacters(in: .whitespaces).lowercased() == logKey
                }
                let name = exercise?.displayName ?? ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName)
                let prescription: String = {
                    if let ex = exercise {
                        if let targetSets = log.targetSets, let reps = ex.reps {
                            return "\(targetSets) × \(reps.displayText)"
                        }
                        return ex.displayPrescription
                    }
                    return ""
                }()
                let completed = log.sets.count
                let planned = log.targetSets ?? (exercise.map { WorkoutSessionUtils.initialSetCount(exercise: $0) } ?? max(log.sets.count, 1))
                let (topWeight, topReps) = extractTopSet(log: log)
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(log.exerciseName))
                return ExerciseProgressItem(
                    name: name,
                    prescription: prescription,
                    completedSets: completed,
                    plannedSets: planned,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr
                )
            }
        }

        let plannedExercises = detail.workout?.exercises ?? []
        if !plannedExercises.isEmpty {
            let planned = plannedExercises.map { ex in
                let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()
                let log = detail.sessionRecord?.exerciseLogs.first { l in
                    let logKey = l.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                    return logKey == nameKey || logKey == displayKey
                }
                let plannedCount = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: ex)
                let completed = log?.sets.count ?? (isExplicitlyCompleted && detail.sessionRecord == nil ? plannedCount : 0)
                let prescription: String = {
                    if let targetSets = log?.targetSets, let reps = ex.reps {
                        return "\(targetSets) × \(reps.displayText)"
                    }
                    return ex.displayPrescription
                }()
                let (topWeight, topReps) = extractTopSet(log: log)
                let rawName = log?.exerciseName ?? ex.name
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(rawName))
                return ExerciseProgressItem(
                    name: ex.displayName,
                    prescription: prescription,
                    completedSets: completed,
                    plannedSets: plannedCount,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr
                )
            }
            let extraLogs = (detail.sessionRecord?.exerciseLogs ?? []).filter { log in
                let logKey = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                return !plannedExercises.contains { ex in
                    ex.name.trimmingCharacters(in: .whitespaces).lowercased() == logKey ||
                    ex.displayName.trimmingCharacters(in: .whitespaces).lowercased() == logKey
                }
            }.map { log in
                let planned = log.targetSets ?? max(log.sets.count, 1)
                let (topWeight, topReps) = extractTopSet(log: log)
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(log.exerciseName))
                return ExerciseProgressItem(
                    name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    prescription: "",
                    completedSets: log.sets.count,
                    plannedSets: planned,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr
                )
            }
            return planned + extraLogs
        } else if let rec = detail.sessionRecord {
            return rec.exerciseLogs.map { log in
                let planned = log.targetSets ?? max(log.sets.count, 1)
                let (topWeight, topReps) = extractTopSet(log: log)
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(log.exerciseName))
                return ExerciseProgressItem(
                    name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    prescription: "",
                    completedSets: log.sets.count,
                    plannedSets: planned,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr
                )
            }
        }
        return []
    }
}

