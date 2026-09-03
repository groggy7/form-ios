import SwiftUI

public struct HistoryView: View {
    @ObservedObject var store: AppStore
    var onOpenSettings: () -> Void
    var onSelectRecord: (WorkoutSessionRecord) -> Void

    @State private var displayedDate: Date = Date()

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
        let history = store.state.history
        let calendar = Calendar.current
        let isCurrentMonth = calendar.isDate(displayedDate, equalTo: Date(), toGranularity: .month)

        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    Text(LanguageManager.t("nav.history"))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Spacer()

                    if !isCurrentMonth {
                        Button(action: { displayedDate = Date() }) {
                            Text(LanguageManager.t("history.thisMonth"))
                                .font(.system(size: 13, weight: .medium))
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
                VStack(spacing: 16) {
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
                            .font(.system(size: 18, weight: .medium))
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
                    HStack {
                        ForEach(weekdaySymbols(), id: \.self) { symbol in
                            Text(symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Days grid
                    let days = daysInMonthGrid(for: displayedDate)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, dateOpt in
                            if let date = dateOpt {
                                let dayNumber = calendar.component(.day, from: date)
                                let isToday = calendar.isDateInToday(date)
                                let hasWorkout = history.contains { record in
                                    guard let completedDate = ISO8601DateFormatter().date(from: record.completedAt) else { return false }
                                    return calendar.isDate(completedDate, inSameDayAs: date)
                                }

                                ZStack {
                                    if hasWorkout {
                                        Circle()
                                            .fill(AppColors.accent)
                                            .frame(width: 32, height: 32)
                                        Text("\(dayNumber)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(AppColors.background)
                                    } else {
                                        if isToday {
                                            Circle()
                                                .stroke(AppColors.accent.opacity(0.7), lineWidth: 1.5)
                                                .frame(width: 32, height: 32)
                                        }
                                        Text("\(dayNumber)")
                                            .font(.system(size: 13, weight: isToday ? .bold : .regular))
                                            .foregroundColor(isToday ? AppColors.accent : AppColors.text)
                                    }
                                }
                                .frame(height: 34)
                            } else {
                                Color.clear.frame(height: 34)
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

                // Completed Workouts List
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LanguageManager.t("history.allExercises"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.text)
                            .padding(.horizontal, 20)

                        VStack(spacing: 8) {
                            ForEach(history) { record in
                                Button(action: { onSelectRecord(record) }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(record.workoutTitle)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppColors.text)

                                            Spacer()

                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(AppColors.accent)
                                        }

                                        HStack(spacing: 14) {
                                            Label(RestTimerUtils.formatSecondsToTime(record.durationSeconds), systemImage: "timer")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)

                                            Label("\(record.totalCompletedSets) \(LanguageManager.t("history.sets").lowercased())", systemImage: "checkmark")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)

                                            Label("\(Int(record.totalVolumeKg)) kg", systemImage: "scalemass")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)

                                            Spacer()

                                            Text(formatDate(record.completedAt))
                                                .font(.system(size: 11))
                                                .foregroundColor(AppColors.muted)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .fill(AppColors.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                    .stroke(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer().frame(height: 16)
            }
        }
    }

    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedDate) {
            displayedDate = newDate
        }
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private func weekdaySymbols() -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private func daysInMonthGrid(for date: Date) -> [Date?] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday

        guard let monthInterval = cal.dateInterval(of: .month, for: date) else { return [] }
        let firstDayOfMonth = monthInterval.start

        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        // Convert gregorian weekday (1=Sun, 2=Mon...) to Monday-based offset (0=Mon...6=Sun)
        let leadingEmpty = (weekday + 5) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)

        var current = firstDayOfMonth
        while current < monthInterval.end {
            days.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        // Pad to complete week
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func formatDate(_ isoString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: isoString) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
