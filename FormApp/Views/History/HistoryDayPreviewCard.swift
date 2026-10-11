import SwiftUI

public struct HistoryDayPreviewCard: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    let onOpenDetail: () -> Void
    var weightUnit: WeightUnit = .kg

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord],
        onOpenDetail: @escaping () -> Void,
        weightUnit: WeightUnit = .kg
    ) {
        self.detail = detail
        self.history = history
        self.onOpenDetail = onOpenDetail
        self.weightUnit = weightUnit
    }

    private struct PreviewExerciseItem: Identifiable {
        var id: String { "\(index)-\(name)" }
        let index: Int
        let name: String
        let setsCount: Int
        let targetSets: Int
        let topSetWeight: Double?
        let topSetReps: Int?
        let isPr: Bool
        let isCompleted: Bool
    }

    private enum PreviewDisplayItem: Identifiable {
        case single(PreviewExerciseItem)
        case unstartedGroup([PreviewExerciseItem])

        var id: String {
            switch self {
            case .single(let item):
                return "single-\(item.id)"
            case .unstartedGroup(let items):
                return "group-\(items.count)-\(items.first?.id ?? "")"
            }
        }
    }

    private var prExercises: Set<String> {
        if detail.sections.count > 1 {
            return Set(detail.sections.compactMap { $0.sessionRecord }.flatMap {
                PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: $0)
            })
        }
        guard let record = detail.sessionRecord else { return [] }
        return PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: record)
    }

    private var workoutTitle: String {
        if detail.isCompletionMark { return LanguageManager.t("history.markedComplete") }
        if detail.sections.count > 1 {
            return detail.recordedSections.map { $0.workoutTitle }.joined(separator: " + ")
        }
        return detail.sessionRecord?.workoutTitle
            ?? detail.workout?.title
            ?? LanguageManager.t("history.scheduledWorkout")
    }

    private var statusColor: Color {
        switch detail.status {
        case .completed: return AppColors.completedGreen
        case .unfinished: return AppColors.unfinishedOrange
        case .missed: return AppColors.missedRed
        }
    }

    private var statusLabel: String {
        switch detail.status {
        case .completed: return LanguageManager.t("history.completed")
        case .unfinished: return LanguageManager.t("history.unfinished")
        case .missed: return LanguageManager.t("history.missed")
        }
    }

    private var dayNumberText: String {
        if detail.sections.count > 1 {
            return "\(detail.sections.count) WORKOUTS"
        }
        if let workout = detail.workout {
            return "DAY \(workout.day)"
        }
        let cal = Calendar.current
        let dayNum = cal.component(.day, from: detail.date)
        return "DAY \(dayNum)"
    }

    private var timeDurationText: String {
        if detail.sections.count > 1 {
            let durationSeconds = detail.sections.reduce(0) { $0 + $1.durationSeconds }
            let durationMinutes = max(1, durationSeconds / 60)
            return LanguageManager.t("history.activeDuration", ["duration": "\(durationMinutes) min"])
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let startTimeStr: String? = {
            guard let startedAt = detail.sessionRecord?.startedAt, !startedAt.isEmpty,
                  let date = WorkoutCalendar.parseIsoTimestamp(startedAt) else { return nil }
            return timeFormatter.string(from: date)
        }()
        let endTimeStr: String? = {
            guard let completedAt = detail.sessionRecord?.completedAt, !completedAt.isEmpty,
                  let date = WorkoutCalendar.parseIsoTimestamp(completedAt) else { return nil }
            return timeFormatter.string(from: date)
        }()

        let durationSeconds = detail.sessionRecord?.durationSeconds ?? 0
        let durationMinutes = max(1, durationSeconds / 60)
        let durationStr = LanguageManager.t("history.activeDuration", ["duration": "\(durationMinutes) min"])

        if let s = startTimeStr, let e = endTimeStr {
            return "\(s) – \(e) · \(durationStr)"
        } else if let s = startTimeStr {
            return "\(s) · \(durationStr)"
        } else if durationSeconds > 0 {
            return durationStr
        } else {
            let df = DateFormatter()
            df.locale = LanguageManager.locale
            df.dateFormat = "d MMMM yyyy"
            return df.string(from: detail.date)
        }
    }

    var volumeKg: Double {
        if !detail.sections.isEmpty {
            return detail.recordedSections.reduce(0) { $0 + $1.totalVolumeKg }
        }
        return HistoryDayDetailData.workingVolumeKg(detail.sessionRecord)
    }

    var exerciseProgress: [HistoryDayExerciseProgress] {
        if !detail.sections.isEmpty { return detail.recordedSections.flatMap(\.exerciseItems) }
        if detail.sessionRecord == nil && detail.status == .completed { return detail.exerciseProgress }
        return HistoryDayDetailData.buildExerciseProgress(sessionRecord: detail.sessionRecord,
            workout: detail.workout, history: history)
    }

    private var allExercises: [PreviewExerciseItem] {
        exerciseProgress.enumerated().map { index, item in
            PreviewExerciseItem(index: index + 1, name: item.name, setsCount: item.completedSets,
                targetSets: item.plannedSets, topSetWeight: item.topSetWeight, topSetReps: item.topSetReps,
                isPr: item.isPr, isCompleted: item.completedSets >= item.plannedSets && item.plannedSets > 0)
        }
    }

    private var displayItems: [PreviewDisplayItem] {
        if detail.status == .unfinished {
            let started = allExercises.filter { $0.setsCount > 0 }
            let unstarted = allExercises.filter { $0.setsCount == 0 }
            var result: [PreviewDisplayItem] = []
            for item in started {
                result.append(.single(item))
            }
            if unstarted.count > 1 {
                result.append(.unstartedGroup(unstarted))
            } else if let single = unstarted.first {
                result.append(.single(single))
            }
            return result
        } else {
            return allExercises.map { .single($0) }
        }
    }

    private var totalCompletedSets: Int {
        allExercises.reduce(0) { $0 + $1.setsCount }
    }

    private var totalPlannedSets: Int {
        max(0, allExercises.reduce(0) { $0 + $1.targetSets })
    }

    private var prsHitCount: Int {
        prExercises.count
    }

    private var statusSystemImage: String {
        switch detail.status {
        case .completed: return "checkmark"
        case .unfinished: return "clock"
        case .missed: return "exclamationmark"
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header Row: Status tag, workout title, status icon, and time range
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    // Tag: • DAY {N} · STATUS
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)

                        Text("\(dayNumberText) · \(statusLabel.uppercased())")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(statusColor)
                            .tracking(0.6)
                    }

                    Text(workoutTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(2)

                    Text(timeDurationText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.muted)
                }

                Spacer()

                // Top right status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                        .overlay(Circle().stroke(statusColor.opacity(0.35), lineWidth: 1))

                    Image(systemName: statusSystemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
            }

            // Metric Tiles Row: VOLUME, SETS, MOVES, PRS HIT
            HStack(spacing: 8) {
                metricTile(
                    title: LanguageManager.t("history.volume").uppercased(),
                    value: volumeKg > 0.0 ? "\(weightUnit.formatVolume(volumeKg)) \(weightUnit.label)" : "0 \(weightUnit.label)",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.sets").uppercased(),
                    value: "\(totalCompletedSets) / \(totalPlannedSets)",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.moves").uppercased().isEmpty ? "MOVES" : LanguageManager.t("history.moves").uppercased(),
                    value: "\(allExercises.count) Ex",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.prsHit").uppercased().isEmpty ? "PRS HIT" : LanguageManager.t("history.prsHit").uppercased(),
                    value: prsHitCount > 0 ? "⚡ \(prsHitCount) New" : "-",
                    isPrTile: prsHitCount > 0
                )
            }

            // Exercise List Rows (Max 3 preview cards)
            if detail.isCompletionMark {
                Text(LanguageManager.t("history.noLoggedSets"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 8) {
                let previewItems = Array(displayItems.prefix(3))
                ForEach(previewItems) { displayItem in
                    switch displayItem {
                    case .single(let item):
                        exerciseRowItem(item: item)
                    case .unstartedGroup(let items):
                        unstartedGroupCard(items: items)
                    }
                }
                let accountedCount = previewItems.reduce(0) { sum, item in
                    switch item {
                    case .single: return sum + 1
                    case .unstartedGroup(let items): return sum + items.count
                    }
                }
                let remaining = allExercises.count - accountedCount
                if remaining > 0 {
                    let hint = LanguageManager.t("history.moreExercisesInBreakdown", ["count": "\(remaining)"])
                    Text(hint.isEmpty ? "+\(remaining) more exercises in full breakdown" : hint)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .padding(.top, 2)
                }
            }

            // Full Log Breakdown Action Button
            Button(action: onOpenDetail) {
                HStack {
                    Text(LanguageManager.t("history.fullLogBreakdown").isEmpty ? "Full Log Breakdown →" : LanguageManager.t("history.fullLogBreakdown"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0x090C0F))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-full-log-breakdown-button")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("history-day-preview-card")
    }

    private func metricTile(title: String, value: String, isPrTile: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isPrTile ? AppColors.orangePrText : AppColors.muted)
                .tracking(0.5)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isPrTile ? AppColors.orangePrText : AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isPrTile ? AppColors.orangePrBg : AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isPrTile ? AppColors.orangePrBorder : AppColors.border, lineWidth: 1)
                )
        )
    }

    private func formatSubInfo(for item: PreviewExerciseItem) -> String {
        let repsWord = LanguageManager.t("units.reps")
        let setsWord = LanguageManager.t("units.sets")
        let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
        if item.setsCount > 0 && item.setsCount < item.targetSets {
            let setsText = "\(item.setsCount) / \(item.targetSets) \(setsWord)"
            if let w = item.topSetWeight, let r = item.topSetReps {
                return "\(setsText) · \(topLabel): \(weightUnit.formatDisplayWeight(w)) \(weightUnit.label) × \(r) \(repsWord)"
            } else {
                return setsText
            }
        } else if item.isCompleted {
            let setsText = "\(item.setsCount) \(setsWord)"
            if let w = item.topSetWeight, let r = item.topSetReps {
                return "\(setsText) · \(topLabel): \(weightUnit.formatDisplayWeight(w)) \(weightUnit.label) × \(r) \(repsWord)"
            } else {
                return setsText
            }
        } else {
            return "\(item.targetSets) \(setsWord)"
        }
    }

    private func exerciseBorderColor(for item: PreviewExerciseItem) -> Color {
        if item.isCompleted {
            return AppColors.completedGreen.opacity(0.35)
        } else if item.setsCount > 0 && item.setsCount < item.targetSets {
            return AppColors.unfinishedOrange.opacity(0.5)
        } else if detail.status == .missed || item.setsCount == 0 {
            return AppColors.missedRed.opacity(0.35)
        } else {
            return AppColors.border
        }
    }

    private func unstartedGroupCard(items: [PreviewExerciseItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LanguageManager.formatUncompletedExercisesCount(items.count))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.text)

            Text(items.map(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.missedRed.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityIdentifier("history-preview-unstarted-group")
    }

    private func exerciseRowItem(item: PreviewExerciseItem) -> some View {
        HStack(spacing: 10) {
            // Index circle: 1, 2, 3
            ZStack {
                Circle()
                    .fill(AppColors.background)
                    .frame(width: 30, height: 30)

                Text("\(item.index)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.text)
            }

            // Exercise name & sub-info (sets + top set)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)

                    if item.isPr {
                        Text("PR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColors.orangePrText)
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

                Text(formatSubInfo(for: item))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Status icon on the right (saves space instead of text)
            if item.isCompleted {
                ZStack {
                    Circle()
                        .fill(AppColors.completedGreen.opacity(0.15))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(AppColors.completedGreen.opacity(0.35), lineWidth: 1))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.completedGreen)
                }
            } else if item.setsCount > 0 {
                ZStack {
                    Circle()
                        .fill(AppColors.unfinishedOrange.opacity(0.15))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(AppColors.unfinishedOrange.opacity(0.35), lineWidth: 1))
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.unfinishedOrange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(exerciseBorderColor(for: item), lineWidth: 1)
                )
        )
    }
}
