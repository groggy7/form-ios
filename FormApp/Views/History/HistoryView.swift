import SwiftUI

public struct HistoryDayExerciseProgress: Identifiable, Equatable {
    public var id: String { occurrenceID ?? "\(name)-\(prescription)" }
    public let occurrenceID: String?
    public let name: String
    public let prescription: String
    public let completedSets: Int
    public let plannedSets: Int
    public let topSetWeight: Double?
    public let topSetReps: Int?
    public let isPr: Bool

    public init(
        name: String,
        prescription: String,
        completedSets: Int,
        plannedSets: Int,
        topSetWeight: Double? = nil,
        topSetReps: Int? = nil,
        isPr: Bool = false,
        occurrenceID: String? = nil
    ) {
        self.occurrenceID = occurrenceID
        self.name = name
        self.prescription = prescription
        self.completedSets = completedSets
        self.plannedSets = plannedSets
        self.topSetWeight = topSetWeight
        self.topSetReps = topSetReps
        self.isPr = isPr
    }
}

public enum HistoryScheduleSource {
    case recorded, workoutSnapshot, currentPlan, unknown
}

public struct WorkoutDaySection: Identifiable {
    public var id: String { sessionRecord?.id ?? workout?.id ?? workoutTitle }
    public let sessionRecord: WorkoutSessionRecord?
    public let workout: Workout?
    public let workoutTitle: String
    public let scheduledDate: Date?
    public let scheduleSource: HistoryScheduleSource
    public let isLiveSession: Bool
    public let isCurrentPlanMatch: Bool
    public let originDate: Date?
    public let originDateFormatted: String?
    public let completedSets: Int
    public let plannedSets: Int
    public let totalVolumeKg: Double
    public let durationSeconds: Int
    public let isComplete: Bool
    public let exerciseItems: [HistoryDayExerciseProgress]

    public init(
        sessionRecord: WorkoutSessionRecord? = nil,
        workout: Workout? = nil,
        workoutTitle: String = "",
        originDate: Date? = nil,
        originDateFormatted: String? = nil,
        completedSets: Int = 0,
        plannedSets: Int = 0,
        totalVolumeKg: Double = 0.0,
        durationSeconds: Int = 0,
        isComplete: Bool = false,
        exerciseItems: [HistoryDayExerciseProgress] = [],
        scheduledDate: Date? = nil,
        scheduleSource: HistoryScheduleSource = .unknown,
        isLiveSession: Bool = false,
        isCurrentPlanMatch: Bool = false
    ) {
        self.sessionRecord = sessionRecord
        self.workout = workout
        self.workoutTitle = workoutTitle
        self.scheduledDate = scheduledDate ?? originDate
        self.scheduleSource = scheduleSource
        self.isLiveSession = isLiveSession
        self.isCurrentPlanMatch = isCurrentPlanMatch
        self.originDate = originDate
        self.originDateFormatted = originDateFormatted
        self.completedSets = completedSets
        self.plannedSets = plannedSets
        self.totalVolumeKg = totalVolumeKg
        self.durationSeconds = durationSeconds
        self.isComplete = isComplete
        self.exerciseItems = exerciseItems
    }

    public func canAct(on day: Date, today: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let todayStart = cal.startOfDay(for: today)
        let dayStart = cal.startOfDay(for: day)
        let weekday = cal.component(.weekday, from: todayStart)
        let leadingDays = (weekday + 5) % 7
        guard let weekStart = cal.date(byAdding: .day, value: -leadingDays, to: todayStart),
              let nextWeekStart = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }

        let isInsideCurrentWeek = dayStart >= weekStart && dayStart <= todayStart
            && (scheduledDate.map { cal.startOfDay(for: $0) >= weekStart && cal.startOfDay(for: $0) < nextWeekStart } ?? true)
        let completed = isComplete || (!isLiveSession && sessionRecord.map {
            WorkoutCalendar.isSessionComplete(session: $0, workout: workout)
        } == true)
        return isInsideCurrentWeek && !completed && !(workout?.exercises.isEmpty ?? true)
    }

    public func contextText(on day: Date, today: Date = Date(), index: Int = 0) -> String {
        if isCurrentPlanMatch { return LanguageManager.t("history.recordedToday") }
        guard let scheduledDate else { return LanguageManager.t("history.additionalWorkout") }
        if Calendar.current.isDate(scheduledDate, inSameDayAs: day) {
            if index > 0 { return LanguageManager.t("history.alsoScheduledDay") }
            return Calendar.current.isDate(day, inSameDayAs: today)
                ? LanguageManager.t("history.todayWorkout")
                : LanguageManager.t("history.workoutForDate", ["date": Self.formattedDate(day)])
        }
        return LanguageManager.t(scheduledDate < day ? "history.earlierWorkout" : "history.otherScheduledDay")
    }

    public func scheduleLabel(on day: Date) -> String? {
        guard let scheduledDate else { return LanguageManager.t("history.scheduleUnknown") }
        let key = sessionRecord == nil ? "history.scheduledFor" : "history.originallyScheduled"
        if Calendar.current.isDate(scheduledDate, inSameDayAs: day) { return nil }
        return LanguageManager.t(key, ["date": Self.formattedDate(scheduledDate)])
    }

    public var statusText: String {
        LanguageManager.t(isComplete ? "history.completed" : isLiveSession ? "history.inProgress"
            : sessionRecord == nil ? "history.notStarted" : "history.unfinished")
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.locale = LanguageManager.locale
        return formatter.string(from: date)
    }
}

public struct HistoryDayDetailData: Identifiable {
    public var id: String { dateString }
    public let date: Date
    public let dateString: String
    public let status: WorkoutDayStatus
    public let sessionRecord: WorkoutSessionRecord?
    public let workout: Workout?
    public let sections: [WorkoutDaySection]

    public init(
        date: Date,
        dateString: String,
        status: WorkoutDayStatus,
        sessionRecord: WorkoutSessionRecord?,
        workout: Workout?,
        sections: [WorkoutDaySection] = []
    ) {
        self.date = date
        self.dateString = dateString
        self.status = status
        self.sessionRecord = sessionRecord
        self.workout = workout
        self.sections = sections
    }

    public var recordedSections: [WorkoutDaySection] {
        let recorded = sections.filter { $0.sessionRecord != nil }
        return recorded.isEmpty ? sections : recorded
    }

    public var isCompletionMark: Bool {
        status == .completed && sessionRecord == nil && sections.isEmpty
    }

    public var exerciseProgress: [HistoryDayExerciseProgress] {
        if !sections.isEmpty { return sections.flatMap(\.exerciseItems) }
        if isCompletionMark { return [] }
        return Self.buildExerciseProgress(sessionRecord: sessionRecord, workout: workout)
    }

    public static func workingVolumeKg(_ record: WorkoutSessionRecord?) -> Double {
        guard let record else { return 0 }
        if record.exerciseLogs.contains(where: { WorkoutSessionUtils.isAssisted(exerciseId: $0.exerciseId, name: $0.exerciseName) }) { return WorkoutSessionUtils.resistanceVolume(record) }
        if record.totalVolumeKg > 0 { return record.totalVolumeKg }
        return record.exerciseLogs.reduce(0) { sum, log in
            sum + log.sets.filter { !$0.isWarmup }.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        }
    }

    /// A saved date is required; a workout weekday cannot establish its historical origin.
    public static func scheduleContext(record: WorkoutSessionRecord, workout: Workout?, day: Date) -> (Date?, HistoryScheduleSource) {
        if let recorded = record.scheduledDate.flatMap({ WorkoutCalendar.parseDate($0) }) { return (recorded, .recorded) }
        return (nil, .unknown)
    }

    public static func groupSections(day: Date, records: [WorkoutSessionRecord], scheduledWorkout: Workout?,
        activeProgramId: String?, programs: [Program], history: [WorkoutSessionRecord], activeRecordId: String? = nil,
        manuallyCompleted: Bool = false, today: Date = Date()) -> [WorkoutDaySection] {
        // A checkbox/backup completion entry is not a session log or a saved prescription.
        if records.isEmpty && manuallyCompleted { return [] }
        let dayString = WorkoutCalendar.formatDate(day)
        var sections = records.map { record -> WorkoutDaySection in
            let workout = record.workoutSnapshot ?? programs.first { $0.id == record.programId }?.workouts.first { $0.id == record.workoutId }
            let (scheduledDate, source) = scheduleContext(record: record, workout: workout, day: day)
            let origin = scheduledDate.flatMap { Calendar.current.isDate($0, inSameDayAs: day) ? nil : $0 }
            let items = buildExerciseProgress(sessionRecord: record, workout: workout, history: history)
            let volume = workingVolumeKg(record)
            return WorkoutDaySection(sessionRecord: record, workout: workout,
                workoutTitle: record.workoutTitle.isEmpty ? workout?.title ?? LanguageManager.t("history.scheduledWorkout") : record.workoutTitle,
                originDate: origin, originDateFormatted: origin.map { $0.formatted(date: .long, time: .omitted) },
                completedSets: items.reduce(0) { $0 + $1.completedSets }, plannedSets: max(1, items.reduce(0) { $0 + $1.plannedSets }),
                totalVolumeKg: volume, durationSeconds: record.durationSeconds,
                isComplete: record.id != activeRecordId && WorkoutCalendar.isSessionComplete(session: record, workout: workout),
                exerciseItems: items, scheduledDate: scheduledDate, scheduleSource: source, isLiveSession: record.id == activeRecordId,
                isCurrentPlanMatch: Calendar.current.isDate(day, inSameDayAs: today) && scheduledDate == nil
                    && record.programId == activeProgramId && record.workoutId == scheduledWorkout?.id)
        }
        // Current plans can supplement today's activity, but cannot add invented workouts to recorded history.
        if (records.isEmpty || Calendar.current.isDate(day, inSameDayAs: today)),
           let scheduled = scheduledWorkout, !scheduled.exercises.isEmpty, !sections.contains(where: {
            ($0.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString || $0.isCurrentPlanMatch) && $0.sessionRecord?.programId == activeProgramId
                && $0.sessionRecord?.workoutId == scheduled.id
        }) {
            let items = buildExerciseProgress(sessionRecord: nil, workout: scheduled, history: history)
            sections.append(WorkoutDaySection(sessionRecord: nil, workout: scheduled, workoutTitle: scheduled.title,
                completedSets: items.reduce(0) { $0 + $1.completedSets }, plannedSets: max(1, items.reduce(0) { $0 + $1.plannedSets }),
                totalVolumeKg: 0, durationSeconds: 0, isComplete: false, exerciseItems: items,
                scheduledDate: day, scheduleSource: .currentPlan))
        }
        return sections.enumerated().sorted { a, b in
            let aToday = a.element.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString || a.element.isCurrentPlanMatch
            let bToday = b.element.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString || b.element.isCurrentPlanMatch
            if aToday != bToday { return aToday }
            let aPlan = aToday && a.element.workout?.id == scheduledWorkout?.id && (a.element.sessionRecord == nil || a.element.sessionRecord?.programId == activeProgramId)
            let bPlan = bToday && b.element.workout?.id == scheduledWorkout?.id && (b.element.sessionRecord == nil || b.element.sessionRecord?.programId == activeProgramId)
            if aPlan != bPlan { return aPlan }
            if (a.element.scheduledDate == nil) != (b.element.scheduledDate == nil) { return a.element.scheduledDate != nil }
            if let ad = a.element.scheduledDate, let bd = b.element.scheduledDate, ad != bd { return ad < bd }
            return a.offset < b.offset
        }.map(\.element)
    }

    public static func buildExerciseProgress(
        sessionRecord: WorkoutSessionRecord?,
        workout: Workout?,
        history: [WorkoutSessionRecord] = []
    ) -> [HistoryDayExerciseProgress] {
        let workout = sessionRecord?.workoutSnapshot ?? workout
        let workingLogs: [SessionExerciseLog] = sessionRecord?.exerciseLogs.map { log in
            var workingLog = log
            workingLog.sets = log.sets.filter { !$0.isWarmup }
            return workingLog
        } ?? []
        var sessionRecord = sessionRecord
        sessionRecord?.exerciseLogs = workingLogs
        let prExercises: Set<String> = {
            if let rec = sessionRecord {
                return PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: rec)
            }
            return []
        }()

        func extractTopSet(log: SessionExerciseLog?) -> (Double?, Int?) {
            guard let validSets = log?.sets.filter({ $0.weightKg.map { $0.isFinite && $0 >= 0 } == true && ($0.reps ?? 0) > 0 }), !validSets.isEmpty else {
                return (nil, nil)
            }
            let top = validSets.max { a, b in
                if (a.weightKg ?? 0.0) != (b.weightKg ?? 0.0) {
                    return WorkoutSessionUtils.isAssisted(exerciseId: log?.exerciseId, name: log?.exerciseName ?? "") ? (a.weightKg ?? 0.0) > (b.weightKg ?? 0.0) : (a.weightKg ?? 0.0) < (b.weightKg ?? 0.0)
                }
                return (a.reps ?? 0) < (b.reps ?? 0)
            }
            return (top?.weightKg, top?.reps)
        }

        // Without a saved prescription, today's edited plan cannot supply historical exercises or targets.
        let plannedExercises = sessionRecord != nil && sessionRecord?.workoutSnapshot == nil ? [] : workout?.exercises ?? []
        if !plannedExercises.isEmpty {
            let logs = sessionRecord?.exerciseLogs ?? []
            let indices = WorkoutCalendar.snapshotLogIndices(exercises: plannedExercises, logs: logs)
            let planned = plannedExercises.enumerated().map { index, ex in
                let log = indices[index].map { logs[$0] }
                let plannedCount = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: ex)
                let completed = log?.sets.count ?? 0
                let prescription: String = {
                    if let targetSets = log?.targetSets, let reps = ex.reps {
                        return "\(targetSets) × \(reps.displayText)"
                    }
                    return ex.displayPrescription
                }()
                let (topWeight, topReps) = extractTopSet(log: log)
                let rawName = log?.exerciseName ?? ex.name
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(rawName))
                return HistoryDayExerciseProgress(
                    name: ex.displayName,
                    prescription: prescription,
                    completedSets: completed,
                    plannedSets: plannedCount,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr,
                    occurrenceID: "planned-\(ex.id)-\(index)"
                )
            }
            let used = Set(indices.compactMap { $0 })
            let extraLogs = logs.enumerated().filter { !used.contains($0.offset) }.map { index, log in
                let planned = log.targetSets ?? max(log.sets.count, 1)
                let (topWeight, topReps) = extractTopSet(log: log)
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(log.exerciseName))
                return HistoryDayExerciseProgress(
                    name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    prescription: "",
                    completedSets: log.sets.count,
                    plannedSets: planned,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr,
                    occurrenceID: "logged-\(index)"
                )
            }
            return planned + extraLogs
        } else if let rec = sessionRecord {
            return rec.exerciseLogs.enumerated().map { index, log in
                let planned = log.targetSets ?? max(log.sets.count, 1)
                let (topWeight, topReps) = extractTopSet(log: log)
                let isPr = prExercises.contains(PersonalRecordTracker.normalizeExerciseKey(log.exerciseName))
                let nameKey = PersonalRecordTracker.normalizeExerciseKey(log.exerciseName)
                let matched = workout?.exercises.first {
                    PersonalRecordTracker.normalizeExerciseKey($0.name) == nameKey
                        || PersonalRecordTracker.normalizeExerciseKey($0.displayName) == nameKey
                }
                return HistoryDayExerciseProgress(
                    name: matched?.displayName ?? ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    prescription: "",
                    completedSets: log.sets.count,
                    plannedSets: planned,
                    topSetWeight: topWeight,
                    topSetReps: topReps,
                    isPr: isPr,
                    occurrenceID: "logged-\(index)"
                )
            }
        }
        return []
    }
}

public struct HistoryView: View {
    @ObservedObject var themeManager = ThemeManager.shared
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
    @State private var selectedDateString: String? = ProcessInfo.processInfo.environment["SELECTED_HISTORY_DATE"]

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
        let _ = themeManager.currentTheme
        if let detailDay = store.selectedHistoryDetailDay,
           let detail = resolveDayDetail(for: detailDay) {
            HistoryDetailView(
                detail: detail,
                history: store.state.history,
                onBack: {
                    store.selectedHistoryDetailDay = nil
                },
                onActionWorkout: { handleWorkoutAction(detail: detail) },
                weightUnit: store.weightUnit,
                onActionSection: { section in handleWorkoutAction(detail: detail, section: section) }
            )
        } else {
            VStack(spacing: 16) {
                // Header row
                HStack(alignment: .center) {
                    Text(LanguageManager.t("nav.progress"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppColors.text)

                    Spacer()

                    if activeTab == .calendar && !Calendar.current.isDate(displayedDate, equalTo: Date(), toGranularity: .month) {
                        Button(action: {
                            displayedDate = Date()
                            selectedDateString = nil
                        }) {
                            Text(LanguageManager.t("history.thisMonth"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
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

                HStack(alignment: .bottom, spacing: 0) {
                    historyTab(.calendar, label: LanguageManager.t("history.calendar"))
                    historyTab(.volumeMatrix, label: LanguageManager.t("history.volumeMatrix"), isPro: true)
                    historyTab(.formLab, label: LanguageManager.t("history.formLab"), isPro: true)
                }
                .padding(.horizontal, 20)

                if activeTab == .volumeMatrix {
                    if proManager.isFeatureUnlocked(.volumeMatrix) {
                        ScrollView {
                            VolumeMatrixView(store: store)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    } else {
                        ZStack {
                            ScrollView(showsIndicators: false) {
                                VolumeMatrixView(store: store, customReport: ProPreviewData.volumeMatrixPreviewReport)
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
                        ZStack {
                            ScrollView(showsIndicators: false) {
                                FormLabView(store: store, isPreview: true)
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
                    let calendar = Calendar.current
                    let today = Date()
                    let todayStr = WorkoutCalendar.formatDate(today)
                    let isCurrentMonth = calendar.isDate(displayedDate, equalTo: today, toGranularity: .month)
                    let displayedMonthStr = String(WorkoutCalendar.formatDate(displayedDate).prefix(7))
                    let currentMonthStr = String(WorkoutCalendar.formatDate(today).prefix(7))
                    let earliestRecordedMonth = WorkoutCalendar.earliestWorkoutMonth(history: store.state.calendarHistory, sessions: store.state.history)
                    let minMonthStr: String = {
                        let start = store.calendarStartMonth
                        if let earliest = earliestRecordedMonth {
                            return min(start, earliest)
                        }
                        return min(start, currentMonthStr)
                    }()
                    let canGoBack = displayedMonthStr > minMonthStr
                    let statuses = store.calendarStatuses(today: today)
                    let weeks = WorkoutCalendar.monthWeeks(for: displayedDate)

                    let currentSelectedDetail: HistoryDayDetailData? = {
                        guard let explicit = selectedDateString else { return nil }
                        return resolveDayDetail(for: explicit)
                    }()

                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(spacing: 16) {
                                // Month Calendar Card
                                VStack(spacing: 10) {
                        // Month navigation row
                        HStack {
                            Button(action: { changeMonth(by: -1, allowed: canGoBack) }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(canGoBack ? AppColors.secondaryText : AppColors.muted.opacity(0.3))
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AppColors.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .disabled(!canGoBack)
                            .buttonStyle(.plain)

                            Spacer()

                            Text(monthYearString(from: displayedDate))
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(AppColors.text)

                            Spacer()

                            Button(action: { changeMonth(by: 1, allowed: !isCurrentMonth) }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(isCurrentMonth ? AppColors.muted.opacity(0.3) : AppColors.secondaryText)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(AppColors.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                    .frame(width: 48, height: 48)
                                    .contentShape(Rectangle())
                            }
                            .disabled(isCurrentMonth)
                            .buttonStyle(.plain)
                        }

                        // Weekday headers
                        HStack(spacing: 0) {
                            ForEach(weekdaySymbols(), id: \.self) { symbol in
                                Text(symbol)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.muted)
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
                        CalendarChrome(
                            cornerRadius: 24,
                            startColor: AppColors.calendarSurfaceStart,
                            endColor: AppColors.calendarSurfaceEnd
                        )
                    )
                    .padding(.horizontal, 20)

                    // Calendar Legend Row
                    HStack {
                        Spacer()
                        legendItem(colors: AppColors.calendarCompletedPill, label: LanguageManager.t("history.completed"))
                        Spacer()
                        legendItem(colors: AppColors.calendarUnfinishedPill, label: LanguageManager.t("history.unfinished"))
                        Spacer()
                        legendItem(colors: AppColors.calendarMissedPill, label: LanguageManager.t("history.missed"))
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

    private func historyTab(_ tab: HistoryTab, label: String, isPro: Bool = false) -> some View {
        let isSelected = activeTab == tab
        return Button {
            activeTab = tab
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppColors.text : AppColors.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isPro {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.purple)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? AppColors.accent : AppColors.border)
                    .frame(height: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPro ? "\(label), \(LanguageManager.t("paywall.feature_badge"))" : label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func handleWorkoutAction(detail: HistoryDayDetailData, section: WorkoutDaySection? = nil) {
        let target = section ?? detail.sections.first { $0.canAct(on: detail.date) }
        guard let target, target.canAct(on: detail.date) else { return }
        guard let workout = target.workout else { return }
        let record = target.sessionRecord
        let programId = record?.programId ?? store.activeProgram?.id
        guard let programId else { return }
        if store.startActiveSession(programId: programId, workout: workout, allowPast: true,
            unfinishedRecordId: record?.id,
            startNewSession: record == nil,
            scheduledDate: target.scheduledDate.map { WorkoutCalendar.formatDate($0) } ?? (record == nil ? detail.dateString : nil),
            resumeHistory: record != nil) {
            store.selectedHistoryDetailDay = nil
            store.currentView = .today
        } else if store.activeSession != nil {
            store.noticeMessage = LanguageManager.t("history.finishActiveFirst")
        }
    }

    private func legendItem(colors: AppColors.CalendarPillColors, label: String) -> some View {
        HStack(spacing: 8) {
            CalendarPill(colors: colors)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private func changeMonth(by value: Int, allowed: Bool = true) {
        guard allowed else { return }
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedDate) {
            displayedDate = newDate
            selectedDateString = nil
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func weekdaySymbols() -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = LanguageManager.locale
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
            let activeDay = draft.assignedCalendarDate
                ?? store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })?.date
                ?? WorkoutCalendar.localDate(from: draft.startedAt)
            if activeDay == dateString {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                return SessionProgress.from(draft: draft, nowEpochMillis: now)
                    .record(draft: draft, completedAtEpochMillis: now)
            }
            return nil
        }()

        var daySessions: [WorkoutSessionRecord] = []
        if let active = activeRecord {
            daySessions.append(active)
        }
        let completedForDay = store.state.history.filter { rec in
            if let calDate = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == dateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return (startDate ?? completedDate) == dateString
        }
        for rec in completedForDay {
            if !daySessions.contains(where: { $0.id == rec.id }) {
                daySessions.append(rec)
            }
        }

        let scheduledWorkout = store.activeProgram?.workouts.first(where: { $0.day == dayOfWeek && !$0.exercises.isEmpty })

        let sortedSections = HistoryDayDetailData.groupSections(day: date, records: daySessions,
            scheduledWorkout: scheduledWorkout, activeProgramId: store.activeProgram?.id,
            programs: store.state.programs, history: store.state.history, activeRecordId: activeRecord?.id,
            manuallyCompleted: status == .completed)
        let primarySection = sortedSections.first
        let primarySessionRecord = primarySection?.sessionRecord
        let primaryWorkout = primarySection == nil && status != .completed ? scheduledWorkout : primarySection?.workout

        let hasAnySets: Bool = {
            if daySessions.contains(where: { rec in
                rec.totalCompletedSets > 0 || rec.exerciseLogs.contains { log in
                    log.sets.contains { ($0.weightKg ?? 0) > 0 || ($0.reps ?? 0) > 0 }
                }
            }) { return true }
            if let active = store.activeSession {
                let activeDay = active.assignedCalendarDate
                    ?? store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(active.id)" })?.date
                    ?? WorkoutCalendar.localDate(from: active.startedAt)
                if activeDay == dateString {
                    let allSets = active.setsByExercise.values.flatMap { $0 }
                    if allSets.contains(where: { $0.isCompleted }) { return true }
                }
            }
            return false
        }()

        let anyComplete = sortedSections.contains { $0.isComplete }
        let isToday = (dateString == WorkoutCalendar.formatDate(Date()))

        let effectiveStatus: WorkoutDayStatus = {
            if anyComplete || status == .completed {
                return .completed
            }
            if hasAnySets {
                return .unfinished
            }
            if !daySessions.isEmpty && !isToday {
                return .missed
            }
            if let status = status {
                return status
            }
            return isToday ? .unfinished : .missed
        }()

        return HistoryDayDetailData(
            date: date,
            dateString: dateString,
            status: effectiveStatus,
            sessionRecord: primarySessionRecord,
            workout: primaryWorkout,
            sections: sortedSections
        )
    }
}

// MARK: - Calendar Day Cell
private let calendarDayPillAspectRatio: CGFloat = 1.12
private let calendarDayPillCornerRadiusFraction: CGFloat = 0.5

private struct CalendarChrome: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let cornerRadius: CGFloat
    let startColor: Color
    let endColor: Color

    var body: some View {
        let _ = themeManager.currentTheme
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [startColor, endColor], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                GeometryReader { geometry in
                    let squaredWidth = geometry.size.width * geometry.size.width
                    let squaredHeight = geometry.size.height * geometry.size.height
                    let squaredDiagonal = max(squaredWidth + squaredHeight, 1)
                    // Normalize the fade to both axes; neither the bottom nor
                    // the right perimeter receives a visible outline.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(LinearGradient(
                            stops: [
                                .init(color: AppColors.border.opacity(0.85), location: 0),
                                .init(color: AppColors.border.opacity(0.45), location: 0.22),
                                .init(color: AppColors.border.opacity(0), location: 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: UnitPoint(
                                x: 2 * squaredHeight / squaredDiagonal,
                                y: 2 * squaredWidth / squaredDiagonal
                            )
                        ), lineWidth: 1)
                }
            }
    }
}

private struct CalendarPill: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let colors: AppColors.CalendarPillColors

    var body: some View {
        let _ = themeManager.currentTheme
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerRadius = height * calendarDayPillCornerRadiusFraction
            let rimWidth = min(1.15, min(width, height) * 0.065)

            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let shineRadius = width * 0.68
            let shineHeight = height * 0.35
            let internalShineStrength = 0.9

            ZStack {
                shape.fill(colors.body)
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: colors.light.opacity(0.25), location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .clear, location: 0.55),
                        .init(color: colors.shade.opacity(0.2), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // A wide, tilted reflection peaks inside the upper third and dissolves by ~65% height.
                Circle().fill(RadialGradient(
                    stops: [
                        .init(color: colors.light.opacity(0.82 * internalShineStrength), location: 0),
                        .init(color: colors.light.opacity(0.62 * internalShineStrength), location: 0.3),
                        .init(color: colors.light.opacity(0.26 * internalShineStrength), location: 0.6),
                        .init(color: colors.light.opacity(0.05 * internalShineStrength), location: 0.85),
                        .init(color: colors.light.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: shineRadius
                ))
                .overlay {
                    Circle().fill(RadialGradient(
                        stops: [
                            .init(color: .white.opacity(0.18 * internalShineStrength), location: 0),
                            .init(color: .white.opacity(0.135 * internalShineStrength), location: 0.3),
                            .init(color: .white.opacity(0.057 * internalShineStrength), location: 0.6),
                            .init(color: .white.opacity(0.011 * internalShineStrength), location: 0.85),
                            .init(color: .clear, location: 1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: shineRadius
                    ))
                }
                .frame(width: shineRadius * 2, height: shineRadius * 2)
                .scaleEffect(x: 1, y: shineHeight / shineRadius)
                .rotationEffect(.degrees(12))
                .position(x: width * 0.4, y: height * 0.28)

                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.58),
                        .init(color: .black.opacity(0.01), location: 0.78),
                        .init(color: .black.opacity(0.035), location: 0.93),
                        .init(color: .black.opacity(0.06), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                // Full-perimeter reflection complements the upper satin sheen; the center stays vivid.
                shape.fill(RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .white.opacity(0.06), location: 0.64),
                        .init(color: .white.opacity(0.18), location: 0.86),
                        .init(color: .white.opacity(0.32), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.5
                ))
                shape.strokeBorder(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.42), location: 0),
                        .init(color: .white.opacity(0.18), location: 0.3),
                        .init(color: .clear, location: 0.65),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: rimWidth)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            // Exterior light remains separate and much weaker than the internal reflection.
            .shadow(color: colors.body.opacity(0.08), radius: min(3, height * 0.09), x: 0, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BoxDayCell: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let dateOpt: Date?
    let todayStr: String
    let statuses: [String: WorkoutDayStatus]
    let isSelected: Bool
    let onSelectDay: (Date, String, WorkoutDayStatus) -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        GeometryReader { geometry in
            let cellSize = min(geometry.size.width, geometry.size.height)
            // Include the selection ring in the fit calculation, not just the fill.
            let canGrow = cellSize >= 44
            // The pill, its border and the selection/today ring share one frame; the ring sits flush on the pill's edge.
            let pillWidth = canGrow ? min(44, cellSize - 2) : min(38, max(0, cellSize - 2))

            ZStack {
                if let date = dateOpt {
                    let dateString = WorkoutCalendar.formatDate(date)
                    let status = statuses[dateString]
                    let isToday = (dateString == todayStr)
                    let calendar = Calendar.current
                    let dayNumber = calendar.component(.day, from: date)
                    let isClickable = (status == .unfinished || status == .missed || status == .completed)

                    ZStack {
                        let pillHeight = pillWidth / calendarDayPillAspectRatio
                        let pillRadius = pillHeight * calendarDayPillCornerRadiusFraction
                        let colors: AppColors.CalendarPillColors? = status.map { status in
                            switch status {
                            case .completed: return AppColors.calendarCompletedPill
                            case .unfinished: return AppColors.calendarUnfinishedPill
                            case .missed: return AppColors.calendarMissedPill
                            }
                        }

                        // Aggressively rounded rectangle status pill
                        if let colors {
                            CalendarPill(colors: colors)
                                .frame(width: pillWidth, height: pillHeight)
                        }

                        // Border drawn inside the pill's edge: selection, today, or (light suites) the pill's own line.
                        let border: (color: Color, width: CGFloat)? = {
                            if isSelected { return (AppColors.accent, 2) }
                            if isToday { return (AppColors.calendarTodayBorder, 1.5) }
                            if let colors, !themeManager.currentTheme.isDark { return (colors.shade, 1) }
                            return nil
                        }()
                        if let border {
                            RoundedRectangle(cornerRadius: pillRadius, style: .continuous)
                                .strokeBorder(border.color, lineWidth: border.width)
                                .frame(width: pillWidth, height: pillHeight)
                        }

                        if status != nil {
                            Text("\(dayNumber)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.calendarPillText)
                        } else {
                            Text("\(dayNumber)")
                                .font(.system(size: 15, weight: isToday ? .semibold : .regular))
                                .foregroundStyle(dateString > todayStr ? AppColors.muted.opacity(0.45) : AppColors.secondaryText)
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
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Compatibility sheet
public struct HistoryDayDetailSheet: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var today: Date
    var onDismiss: () -> Void
    var onActionWorkout: (() -> Void)?

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord] = [],
        onDismiss: @escaping () -> Void,
        onActionWorkout: (() -> Void)? = nil,
        initiallyExpanded: Bool = false,
        today: Date = Date()
    ) {
        self.detail = detail
        self.history = history
        self.today = today
        self.onDismiss = onDismiss
        self.onActionWorkout = onActionWorkout
    }

    public var body: some View {
        HistoryDetailView(detail: detail, history: history, today: today,
            onBack: onDismiss, onActionWorkout: onActionWorkout)
            .presentationDetents([.fraction(0.8), .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(themeManager.currentTheme.colorScheme)
    }
}
