import SwiftUI

public struct HistoryDayExerciseProgress: Identifiable, Equatable {
    public var id: String { "\(name)-\(prescription)" }
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
        isPr: Bool = false
    ) {
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
    public let originDate: Date?
    public let originDateFormatted: String?
    public let completedSets: Int
    public let plannedSets: Int
    public let totalVolumeKg: Double
    public let durationSeconds: Int
    public let isComplete: Bool
    public let exerciseItems: [HistoryDayExerciseProgress]

    public init(
        sessionRecord: WorkoutSessionRecord?,
        workout: Workout?,
        workoutTitle: String,
        originDate: Date? = nil,
        originDateFormatted: String? = nil,
        completedSets: Int,
        plannedSets: Int,
        totalVolumeKg: Double,
        durationSeconds: Int,
        isComplete: Bool,
        exerciseItems: [HistoryDayExerciseProgress],
        scheduledDate: Date? = nil,
        scheduleSource: HistoryScheduleSource = .unknown,
        isLiveSession: Bool = false
    ) {
        self.sessionRecord = sessionRecord
        self.workout = workout
        self.workoutTitle = workoutTitle
        self.scheduledDate = scheduledDate ?? originDate
        self.scheduleSource = scheduleSource
        self.isLiveSession = isLiveSession
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
        Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: today)
            && !isComplete && !(workout?.exercises.isEmpty ?? true)
    }

    public func contextText(on day: Date, today: Date = Date(), index: Int = 0) -> String {
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
        let key = scheduleSource == .recorded ? "history.originallyScheduled"
            : sessionRecord == nil ? "history.scheduledFor" : "history.usualSchedule"
        if key == "history.usualSchedule", Calendar.current.isDate(scheduledDate, inSameDayAs: day) { return nil }
        return LanguageManager.t(key, ["date": Self.formattedDate(scheduledDate)])
    }

    public var statusText: String {
        LanguageManager.t(isComplete ? "history.completed" : isLiveSession ? "history.inProgress"
            : sessionRecord == nil ? "history.notStarted" : "history.unfinished")
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
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

    /// A legacy weekly schedule is display context, never a claim about the saved origin.
    public static func scheduleContext(record: WorkoutSessionRecord, workout: Workout?, day: Date) -> (Date?, HistoryScheduleSource) {
        if let recorded = record.scheduledDate.flatMap({ WorkoutCalendar.parseDate($0) }) { return (recorded, .recorded) }
        guard let weekday = (record.workoutSnapshot ?? workout)?.day, (1...7).contains(weekday),
              var usual = WorkoutCalendar.parseDate(WorkoutCalendar.scheduledDate(forWeekday: weekday, relativeTo: day)) else {
            return (nil, .unknown)
        }
        if usual > day { usual = Calendar.current.date(byAdding: .day, value: -7, to: usual) ?? usual }
        return (usual, record.workoutSnapshot == nil ? .currentPlan : .workoutSnapshot)
    }

    public static func groupSections(day: Date, records: [WorkoutSessionRecord], scheduledWorkout: Workout?,
        activeProgramId: String?, programs: [Program], history: [WorkoutSessionRecord], activeRecordId: String? = nil,
        manuallyCompleted: Bool = false) -> [WorkoutDaySection] {
        let dayString = WorkoutCalendar.formatDate(day)
        var sections = records.map { record -> WorkoutDaySection in
            let workout = record.workoutSnapshot ?? programs.first { $0.id == record.programId }?.workouts.first { $0.id == record.workoutId }
            let (scheduledDate, source) = scheduleContext(record: record, workout: workout, day: day)
            let origin = scheduledDate.flatMap { Calendar.current.isDate($0, inSameDayAs: day) ? nil : $0 }
            let items = buildExerciseProgress(sessionRecord: record, workout: workout, history: history)
            let volume = record.totalVolumeKg > 0 ? record.totalVolumeKg : record.exerciseLogs.reduce(0.0) { sum, log in
                sum + log.sets.filter { !$0.isWarmup }.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
            }
            return WorkoutDaySection(sessionRecord: record, workout: workout,
                workoutTitle: record.workoutTitle.isEmpty ? workout?.title ?? LanguageManager.t("history.scheduledWorkout") : record.workoutTitle,
                originDate: origin, originDateFormatted: origin.map { $0.formatted(date: .long, time: .omitted) },
                completedSets: items.reduce(0) { $0 + $1.completedSets }, plannedSets: max(1, items.reduce(0) { $0 + $1.plannedSets }),
                totalVolumeKg: volume, durationSeconds: record.durationSeconds,
                isComplete: record.id != activeRecordId && WorkoutCalendar.isSessionComplete(session: record, workout: workout),
                exerciseItems: items, scheduledDate: scheduledDate, scheduleSource: source, isLiveSession: record.id == activeRecordId)
        }
        if let scheduled = scheduledWorkout, !scheduled.exercises.isEmpty, !sections.contains(where: {
            $0.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString && $0.sessionRecord?.programId == activeProgramId
                && $0.sessionRecord?.workoutId == scheduled.id
        }) {
            var items = buildExerciseProgress(sessionRecord: nil, workout: scheduled, history: history)
            let complete = records.isEmpty && manuallyCompleted
            if complete { items = items.map { HistoryDayExerciseProgress(name: $0.name, prescription: $0.prescription,
                completedSets: $0.plannedSets, plannedSets: $0.plannedSets) } }
            sections.append(WorkoutDaySection(sessionRecord: nil, workout: scheduled, workoutTitle: scheduled.title,
                completedSets: items.reduce(0) { $0 + $1.completedSets }, plannedSets: max(1, items.reduce(0) { $0 + $1.plannedSets }),
                totalVolumeKg: 0, durationSeconds: 0, isComplete: complete, exerciseItems: items,
                scheduledDate: day, scheduleSource: .currentPlan))
        }
        return sections.enumerated().sorted { a, b in
            let aToday = a.element.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString
            let bToday = b.element.scheduledDate.map { WorkoutCalendar.formatDate($0) } == dayString
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
        let isExplicitlyCompleted = sessionRecord?.isComplete == true
        let prExercises: Set<String> = {
            if let rec = sessionRecord {
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

        let plannedExercises = workout?.exercises ?? []
        if !plannedExercises.isEmpty {
            let planned = plannedExercises.map { ex in
                let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()
                let log = sessionRecord?.exerciseLogs.first { l in
                    let logKey = l.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                    return logKey == nameKey || logKey == displayKey
                }
                let plannedCount = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: ex)
                let completed = log?.sets.count ?? (isExplicitlyCompleted && sessionRecord == nil ? plannedCount : 0)
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
                    isPr: isPr
                )
            }
            let extraLogs = (sessionRecord?.exerciseLogs ?? []).filter { log in
                let logKey = log.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                return !plannedExercises.contains { ex in
                    ex.name.trimmingCharacters(in: .whitespaces).lowercased() == logKey ||
                    ex.displayName.trimmingCharacters(in: .whitespaces).lowercased() == logKey
                }
            }.map { log in
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
                    isPr: isPr
                )
            }
            return planned + extraLogs
        } else if let rec = sessionRecord {
            return rec.exerciseLogs.map { log in
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
                    isPr: isPr
                )
            }
        }
        return []
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
                        .foregroundColor(AppColors.text)

                    Spacer()

                    if activeTab == .calendar && !Calendar.current.isDate(displayedDate, equalTo: Date(), toGranularity: .month) {
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
                    .foregroundColor(isSelected ? AppColors.text : AppColors.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if isPro {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.purple)
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
        guard let workout = target?.workout ?? detail.workout else { return }
        let record = target?.sessionRecord ?? (target == nil ? detail.sessionRecord : nil)
        let programId = record?.programId
            ?? store.state.programs.first(where: { $0.workouts.contains(where: { $0.id == workout.id }) })?.id
        guard let programId else { return }
        let sameDay = Calendar.current.isDateInToday(detail.date)
        if store.startActiveSession(programId: programId, workout: workout, allowPast: true,
            unfinishedRecordId: sameDay ? record?.id : nil,
            assignedCalendarDate: WorkoutCalendar.formatDate(Date()),
            startNewSession: record == nil || (!sameDay && target?.isLiveSession != true),
            scheduledDate: target?.scheduledDate.map { WorkoutCalendar.formatDate($0) } ?? detail.dateString) {
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
        let primaryWorkout = primarySection?.workout ?? scheduledWorkout

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
            if anyComplete {
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

private struct CalendarPill: View {
    let colors: AppColors.CalendarPillColors

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let cornerRadius = height * calendarDayPillCornerRadiusFraction
            let rimWidth = min(1.15, min(width, height) * 0.065)

            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let shineRadius = width * 0.68
            let shineHeight = height * 0.35

            ZStack {
                shape.fill(colors.body)
                shape.fill(LinearGradient(
                    stops: [
                        .init(color: colors.light.opacity(0.25), location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .clear, location: 0.55),
                        .init(color: colors.shade.opacity(0.3), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))

                // A wide, tilted reflection peaks inside the upper third and dissolves by ~65% height.
                Circle().fill(RadialGradient(
                    stops: [
                        .init(color: colors.light.opacity(0.48), location: 0),
                        .init(color: colors.light.opacity(0.35), location: 0.3),
                        .init(color: colors.light.opacity(0.15), location: 0.6),
                        .init(color: colors.light.opacity(0.03), location: 0.85),
                        .init(color: colors.light.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: shineRadius
                ))
                .frame(width: shineRadius * 2, height: shineRadius * 2)
                .scaleEffect(x: 1, y: shineHeight / shineRadius)
                .rotationEffect(.degrees(12))
                .position(x: width * 0.4, y: height * 0.28)

                shape.fill(LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.58),
                        .init(color: .black.opacity(0.02), location: 0.78),
                        .init(color: .black.opacity(0.08), location: 0.93),
                        .init(color: .black.opacity(0.14), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                shape.strokeBorder(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.18), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.24),
                        .init(color: .clear, location: 0.45),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ), lineWidth: rimWidth)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            // Exterior light remains separate and much weaker than the internal reflection.
            .shadow(color: colors.body.opacity(0.04), radius: min(2, height * 0.06), x: 0, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BoxDayCell: View {
    let dateOpt: Date?
    let todayStr: String
    let statuses: [String: WorkoutDayStatus]
    let isSelected: Bool
    let onSelectDay: (Date, String, WorkoutDayStatus) -> Void

    var body: some View {
        GeometryReader { geometry in
            let cellSize = min(geometry.size.width, geometry.size.height)
            // Include the selection ring in the fit calculation, not just the fill.
            let canGrow = cellSize >= 44
            let pillWidth = canGrow ? min(40, cellSize - 6) : min(32, max(0, cellSize - 6))
            let ringWidth = canGrow ? pillWidth + 4 : min(38, max(0, cellSize - 2))

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
                        let ringHeight = ringWidth / calendarDayPillAspectRatio
                        let ringRadius = ringHeight * calendarDayPillCornerRadiusFraction

                        // Outer border ring for selected day or today
                        if isSelected {
                            RoundedRectangle(cornerRadius: ringRadius, style: .continuous)
                                .strokeBorder(AppColors.accent, lineWidth: 2)
                                .frame(width: ringWidth, height: ringHeight)
                        } else if isToday {
                            let todayWidth = status == nil ? pillWidth : ringWidth
                            let todayHeight = status == nil ? pillHeight : ringHeight
                            let todayRadius = status == nil ? pillRadius : ringRadius
                            RoundedRectangle(cornerRadius: todayRadius, style: .continuous)
                                .strokeBorder(AppColors.text.opacity(0.8), lineWidth: 1)
                                .frame(width: todayWidth, height: todayHeight)
                        }

                        // Aggressively rounded rectangle status pill
                        if let status = status {
                            let colors: AppColors.CalendarPillColors = {
                                switch status {
                                case .completed: return AppColors.calendarCompletedPill
                                case .unfinished: return AppColors.calendarUnfinishedPill
                                case .missed: return AppColors.calendarMissedPill
                                }
                            }()

                            CalendarPill(colors: colors)
                                .frame(width: pillWidth, height: pillHeight)

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
            .frame(width: geometry.size.width, height: geometry.size.height)
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

        let workoutTitle = detail.sections.count > 1
            ? detail.sections.map { $0.workoutTitle }.joined(separator: " + ")
            : (detail.sessionRecord?.workoutTitle ?? detail.workout?.title ?? LanguageManager.t("history.scheduledWorkout"))

        let items = exerciseProgressList()
        let allCompleted = !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let effectiveStatus: WorkoutDayStatus = (detail.status == .unfinished && allCompleted) ? .completed : detail.status
        let isMissed = effectiveStatus == .missed || (!items.isEmpty && items.allSatisfy { $0.completedSets == 0 } && detail.date < Calendar.current.startOfDay(for: Date()))
        let showActionButton = onActionWorkout != nil && !allCompleted
        let actionButtonText = isMissed ? LanguageManager.t("history.startWorkout") : LanguageManager.t("history.resumeWorkout")

        let completedExercises = items.filter { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let halfwayExercises = items.filter { $0.completedSets > 0 && $0.completedSets < $0.plannedSets }
        let unstartedExercises = items.filter { $0.completedSets == 0 }

        let totalCompletedSets = detail.sections.count > 1
            ? detail.sections.reduce(0) { $0 + $1.completedSets }
            : (detail.sessionRecord?.totalCompletedSets ?? items.reduce(0) { $0 + $1.completedSets })
        let totalPlannedSets = max(1, detail.sections.count > 1
            ? detail.sections.reduce(0) { $0 + $1.plannedSets }
            : items.reduce(0) { $0 + $1.plannedSets })
        let displayCompletedSets = effectiveStatus == .missed ? 0 : totalCompletedSets
        let durationSeconds = detail.sections.count > 1
            ? detail.sections.reduce(0) { $0 + $1.durationSeconds }
            : (detail.sessionRecord?.durationSeconds ?? 0)
        let totalVolumeKg = detail.sections.count > 1
            ? detail.sections.reduce(0.0) { $0 + $1.totalVolumeKg }
            : (detail.sessionRecord?.totalVolumeKg ?? 0.0)

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
                if detail.sections.count > 1 {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(detail.sections.enumerated()), id: \.element.id) { sIndex, sec in
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        let headerTitle = sec.originDate == nil
                                            ? "\(LanguageManager.t("history.todayExercises")) · \(sec.workoutTitle)"
                                            : sec.workoutTitle
                                        Text(headerTitle)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Text("\(sec.exerciseItems.count)")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(AppColors.secondaryText)
                                            .frame(width: 20, alignment: .center)
                                    }

                                    if let origin = sec.originDateFormatted {
                                        Text("🗓️ \(LanguageManager.t("history.originallyScheduled", ["date": origin]))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(AppColors.secondaryText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(AppColors.surfaceRaised)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .stroke(AppColors.border, lineWidth: 1)
                                                    )
                                            )
                                    }

                                    let setsStr = LanguageManager.formatSetsFraction(completed: sec.completedSets, total: sec.plannedSets)
                                    let secVolumeStr = sec.totalVolumeKg > 0.0 ? " · \(WorkoutSessionUtils.formatWeight(sec.totalVolumeKg)) kg" : ""
                                    Text("\(setsStr)\(secVolumeStr)")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                VStack(spacing: 0) {
                                    ForEach(Array(sec.exerciseItems.enumerated()), id: \.element.id) { index, item in
                                        let isItemComplete = item.completedSets >= item.plannedSets && item.plannedSets > 0
                                        let progItem = ExerciseProgressItem(
                                            name: item.name,
                                            prescription: item.prescription,
                                            completedSets: item.completedSets,
                                            plannedSets: item.plannedSets,
                                            topSetWeight: item.topSetWeight,
                                            topSetReps: item.topSetReps,
                                            isPr: item.isPr
                                        )
                                        exerciseRow(item: progItem, isCompleted: isItemComplete)
                                        if index < sec.exerciseItems.count - 1 {
                                            Divider()
                                                .background(Color.white.opacity(0.08))
                                        }
                                    }
                                }
                            }

                            if sIndex < detail.sections.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.12))
                            }
                        }
                    }
                } else if allCompleted {
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
        if !detail.sections.isEmpty {
            return detail.sections.flatMap { sec in
                sec.exerciseItems.map { item in
                    ExerciseProgressItem(
                        name: item.name,
                        prescription: item.prescription,
                        completedSets: item.completedSets,
                        plannedSets: item.plannedSets,
                        topSetWeight: item.topSetWeight,
                        topSetReps: item.topSetReps,
                        isPr: item.isPr
                    )
                }
            }
        }
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

