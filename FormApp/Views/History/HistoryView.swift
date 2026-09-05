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

    @State private var displayedDate: Date = Date()
    @State private var selectedDayDetail: HistoryDayDetailData? = nil

    public init(
        store: AppStore,
        onOpenSettings: @escaping () -> Void,
        onSelectRecord: @escaping (WorkoutSessionRecord) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onSelectRecord = onSelectRecord
    }

    public var body: some View {
        let calendar = Calendar.current
        let today = Date()
        let todayStr = WorkoutCalendar.formatDate(today)
        let isCurrentMonth = calendar.isDate(displayedDate, equalTo: today, toGranularity: .month)
        let statuses = store.calendarStatuses(today: today)

        ScrollView {
            VStack(spacing: 24) {
                // Header row
                HStack(alignment: .center) {
                    Text(LanguageManager.t("nav.history"))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Spacer()

                    if !isCurrentMonth {
                        Button(action: { displayedDate = Date() }) {
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

                // Month Calendar Card
                VStack(spacing: 18) {
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
                    let weeks = WorkoutCalendar.monthWeeks(for: displayedDate)
                    VStack(spacing: 8) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            HStack(spacing: 0) {
                                ForEach(Array(week.enumerated()), id: \.offset) { _, dateOpt in
                                    BoxDayCell(
                                        dateOpt: dateOpt,
                                        todayStr: todayStr,
                                        statuses: statuses,
                                        onSelectDay: { date, dateString, status in
                                            handleDaySelection(date: date, dateString: dateString, status: status)
                                        }
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(16)
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
                .padding(.top, 4)

                Spacer().frame(height: 24)
            }
        }
        .sheet(item: $selectedDayDetail) { detail in
            HistoryDayDetailSheet(detail: detail) {
                selectedDayDetail = nil
            }
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

    private func handleDaySelection(date: Date, dateString: String, status: WorkoutDayStatus) {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date)
        let dayOfWeek = (weekday + 5) % 7 + 1 // 1=Mon..7=Sun

        let activeRecord: WorkoutSessionRecord? = {
            guard let draft = store.activeSession else { return nil }
            let activeDay = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })?.date
                ?? WorkoutCalendar.scheduledDate(forWeekday: draft.workout.day, relativeTo: Date())
                ?? WorkoutCalendar.localDate(from: draft.startedAt)
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

        let effectiveStatus: WorkoutDayStatus = (sessionRecord?.isComplete == true) ? .completed : status

        selectedDayDetail = HistoryDayDetailData(
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
    let onSelectDay: (Date, String, WorkoutDayStatus) -> Void

    var body: some View {
        ZStack {
            if let date = dateOpt {
                let dateString = WorkoutCalendar.formatDate(date)
                let status = statuses[dateString]
                let isToday = (dateString == todayStr)
                let calendar = Calendar.current
                let dayNumber = calendar.component(.day, from: date)
                let isClickable = (status == .unfinished || status == .missed)

                ZStack {
                    // Outer border ring for today
                    if isToday {
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
    var onDismiss: () -> Void

    public init(detail: HistoryDayDetailData, onDismiss: @escaping () -> Void) {
        self.detail = detail
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let formattedDate = formattedFullDate(for: detail.date)

        let workoutTitle = detail.sessionRecord?.workoutTitle
            ?? detail.workout?.title
            ?? LanguageManager.t("history.scheduledWorkout")

        let items = exerciseProgressList()
        let allCompleted = !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets }
        let effectiveStatus: WorkoutDayStatus = (detail.status == .unfinished && allCompleted) ? .completed : detail.status

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

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)

                        Text(workoutTitle)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.text)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 36, height: 36)
                            .background(AppColors.surfaceRaised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Status pill tag
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(statusBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(statusColor.opacity(0.3), lineWidth: 1)
                        )
                )

                // Detail Content
                if effectiveStatus == .missed {
                    missedContentView(workoutTitle: workoutTitle)
                } else {
                    unfinishedContentView(items: items, allCompleted: allCompleted)
                }

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .background(AppColors.surface.ignoresSafeArea())
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
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

    // MARK: Missed Content
    @ViewBuilder
    private func missedContentView(workoutTitle: String) -> some View {
        let shortDate = formattedShortDate(for: detail.date)
        let summaryLine = "\(shortDate) — \(workoutTitle) — \(LanguageManager.t("history.missed"))"

        VStack(alignment: .leading, spacing: 18) {
            // Summary Card
            VStack(alignment: .leading, spacing: 8) {
                Text(summaryLine)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.text)

                Text(LanguageManager.t("history.missedWorkout"))
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.muted)
                    .lineSpacing(3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )

            // Scheduled exercises list
            if let workout = detail.workout, !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LanguageManager.t("history.allExercises"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)

                    ForEach(workout.exercises) { exercise in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.text)

                            if !exercise.displayPrescription.isEmpty {
                                Text(exercise.displayPrescription)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.muted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: Unfinished / Completed Content
    @ViewBuilder
    private func unfinishedContentView(items: [ExerciseProgressItem], allCompleted: Bool) -> some View {
        let sectionTitle = allCompleted
            ? LanguageManager.t("history.allExercises")
            : LanguageManager.t("history.uncompletedExercises")

        VStack(alignment: .leading, spacing: 20) {
            // Stats Row (Duration, Sets, Volume)
            if let rec = detail.sessionRecord {
                HStack(spacing: 10) {
                    statCard(
                        title: LanguageManager.t("history.duration"),
                        value: RestTimerUtils.formatSecondsToTime(rec.durationSeconds)
                    )
                    statCard(
                        title: LanguageManager.t("history.sets"),
                        value: "\(rec.totalCompletedSets)"
                    )
                    statCard(
                        title: LanguageManager.t("history.volume"),
                        value: "\(Int(rec.totalVolumeKg)) kg"
                    )
                }
            }

            // Breakdown of exercises
            VStack(alignment: .leading, spacing: 12) {
                Text(sectionTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.text)

                ForEach(items) { item in
                    exerciseProgressCard(item: item)
                }
            }
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(AppColors.muted)

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }

    private struct ExerciseProgressItem: Identifiable {
        var id: String { name }
        let name: String
        let completedSets: Int
        let plannedSets: Int
    }

    private func exerciseProgressList() -> [ExerciseProgressItem] {
        let plannedExercises = detail.workout?.exercises ?? []
        if !plannedExercises.isEmpty {
            return plannedExercises.map { ex in
                let nameKey = ex.name.trimmingCharacters(in: .whitespaces).lowercased()
                let displayKey = ex.displayName.trimmingCharacters(in: .whitespaces).lowercased()
                let log = detail.sessionRecord?.exerciseLogs.first { l in
                    let logKey = l.exerciseName.trimmingCharacters(in: .whitespaces).lowercased()
                    return logKey == nameKey || logKey == displayKey
                }
                let completed = log?.sets.count ?? 0
                let planned = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: ex)
                return ExerciseProgressItem(name: ex.displayName, completedSets: completed, plannedSets: planned)
            }
        } else if let rec = detail.sessionRecord {
            return rec.exerciseLogs.map { log in
                let planned = log.targetSets ?? max(log.sets.count, 1)
                return ExerciseProgressItem(name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName), completedSets: log.sets.count, plannedSets: planned)
            }
        }
        return []
    }

    private func exerciseProgressCard(item: ExerciseProgressItem) -> some View {
        let isFullyDone = (item.completedSets >= item.plannedSets && item.plannedSets > 0)
        let isNotStarted = (item.completedSets == 0)
        let isPartial = (!isFullyDone && !isNotStarted)

        let borderColor: Color = {
            if isNotStarted {
                return AppColors.unfinishedOrange.opacity(0.4)
            } else if isPartial {
                return AppColors.unfinishedOrange.opacity(0.6)
            } else {
                return AppColors.border
            }
        }()

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFullyDone ? AppColors.secondaryText : AppColors.text)

                Text(LanguageManager.formatSetsProgress(done: item.completedSets, total: item.plannedSets))
                    .font(.system(size: 12))
                    .foregroundColor(isFullyDone ? AppColors.muted : AppColors.secondaryText)
            }

            Spacer()

            // Status Badge
            HStack(spacing: 4) {
                if isFullyDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.completedGreen)
                }

                Text(statusBadgeText(isFullyDone: isFullyDone, isNotStarted: isNotStarted, remaining: max(0, item.plannedSets - item.completedSets)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isFullyDone ? AppColors.completedGreen : (isPartial ? AppColors.unfinishedOrange : AppColors.muted))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFullyDone ? AppColors.completedGreen.opacity(0.15) : (isPartial ? AppColors.unfinishedOrange.opacity(0.15) : AppColors.border.opacity(0.4)))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
    }

    private func statusBadgeText(isFullyDone: Bool, isNotStarted: Bool, remaining: Int) -> String {
        if isFullyDone {
            return LanguageManager.t("history.completed")
        } else if isNotStarted {
            return LanguageManager.t("history.notStarted")
        } else {
            return LanguageManager.t("history.setsRemainingCount", ["count": remaining])
        }
    }
}
