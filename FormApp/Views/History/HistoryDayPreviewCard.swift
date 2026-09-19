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
        guard let record = detail.sessionRecord else { return [] }
        return PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: record)
    }

    private var workoutTitle: String {
        detail.sessionRecord?.workoutTitle
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
        if let workout = detail.workout {
            return "DAY \(workout.day)"
        }
        let cal = Calendar.current
        let dayNum = cal.component(.day, from: detail.date)
        return "DAY \(dayNum)"
    }

    private var timeDurationText: String {
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
            df.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
            df.dateFormat = "d MMMM yyyy"
            return df.string(from: detail.date)
        }
    }

    private var volumeKg: Double {
        if let vol = detail.sessionRecord?.totalVolumeKg, vol > 0.0 {
            return vol
        }
        guard let logs = detail.sessionRecord?.exerciseLogs else { return 0.0 }
        var total: Double = 0.0
        for log in logs {
            for set in log.sets {
                let w = set.weightKg ?? 0.0
                let r = Double(set.reps ?? 0)
                total += w * r
            }
        }
        return total
    }

    private var allExercises: [PreviewExerciseItem] {
        let planned = detail.workout?.exercises ?? []
        let logs = detail.sessionRecord?.exerciseLogs ?? []
        let activePrs = prExercises

        if !planned.isEmpty {
            let plannedItems: [PreviewExerciseItem] = planned.enumerated().map { index, ex in
                let log = logs.first {
                    $0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(ex.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame ||
                    $0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(ex.displayName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                }
                let setsCount = log?.sets.count ?? 0
                let targetSets = log?.targetSets ?? WorkoutSessionUtils.initialSetCount(exercise: ex)
                let validSets = log?.sets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 } ?? []
                let topSet = validSets.max { a, b in
                    let wA = a.weightKg ?? 0.0
                    let wB = b.weightKg ?? 0.0
                    if wA != wB { return wA < wB }
                    return (a.reps ?? 0) < (b.reps ?? 0)
                }
                let rawName = log?.exerciseName ?? ex.name
                let normKey = PersonalRecordTracker.normalizeExerciseKey(rawName)
                let isPr = activePrs.contains(normKey)
                return PreviewExerciseItem(
                    index: index + 1,
                    name: ex.displayName,
                    setsCount: setsCount,
                    targetSets: targetSets,
                    topSetWeight: topSet?.weightKg,
                    topSetReps: topSet?.reps,
                    isPr: isPr,
                    isCompleted: setsCount >= targetSets && setsCount > 0
                )
            }
            let extraLogs: [PreviewExerciseItem] = logs.filter { log in
                !planned.contains { ex in
                    log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(ex.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame ||
                    log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(ex.displayName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                }
            }.enumerated().map { index, log in
                let setsCount = log.sets.count
                let targetSets = log.targetSets ?? max(setsCount, 1)
                let validSets = log.sets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                let topSet = validSets.max { a, b in
                    let wA = a.weightKg ?? 0.0
                    let wB = b.weightKg ?? 0.0
                    if wA != wB { return wA < wB }
                    return (a.reps ?? 0) < (b.reps ?? 0)
                }
                let normKey = PersonalRecordTracker.normalizeExerciseKey(log.exerciseName)
                let isPr = activePrs.contains(normKey)
                return PreviewExerciseItem(
                    index: planned.count + index + 1,
                    name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    setsCount: setsCount,
                    targetSets: targetSets,
                    topSetWeight: topSet?.weightKg,
                    topSetReps: topSet?.reps,
                    isPr: isPr,
                    isCompleted: setsCount >= targetSets && setsCount > 0
                )
            }
            return plannedItems + extraLogs
        } else if !logs.isEmpty {
            return logs.enumerated().map { index, log in
                let setsCount = log.sets.count
                let targetSets = log.targetSets ?? max(setsCount, 1)
                let validSets = log.sets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                let topSet = validSets.max { a, b in
                    let wA = a.weightKg ?? 0.0
                    let wB = b.weightKg ?? 0.0
                    if wA != wB { return wA < wB }
                    return (a.reps ?? 0) < (b.reps ?? 0)
                }
                let normKey = PersonalRecordTracker.normalizeExerciseKey(log.exerciseName)
                let isPr = activePrs.contains(normKey)
                return PreviewExerciseItem(
                    index: index + 1,
                    name: ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName),
                    setsCount: setsCount,
                    targetSets: targetSets,
                    topSetWeight: topSet?.weightKg,
                    topSetReps: topSet?.reps,
                    isPr: isPr,
                    isCompleted: setsCount >= targetSets && setsCount > 0
                )
            }
        } else {
            return []
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
        detail.sessionRecord?.totalCompletedSets ?? allExercises.reduce(0) { $0 + $1.setsCount }
    }

    private var totalPlannedSets: Int {
        max(1, allExercises.reduce(0) { $0 + $1.targetSets })
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
                            .foregroundColor(statusColor)
                            .tracking(0.6)
                    }

                    Text(workoutTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .lineLimit(2)

                    Text(timeDurationText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(AppColors.muted)
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
                        .foregroundColor(statusColor)
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
                        .foregroundColor(AppColors.muted)
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
                        .foregroundColor(Color(hex: 0x090C0F))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AppColors.accent)
                .cornerRadius(14)
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
                .foregroundColor(isPrTile ? AppColors.orangePrText : AppColors.muted)
                .tracking(0.5)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isPrTile ? AppColors.orangePrText : AppColors.text)
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
        let repsWord = LanguageManager.shared.currentLanguage == "tr" ? "tekrar" : "reps"
        let setsWord = LanguageManager.shared.currentLanguage == "tr" ? "set" : "sets"
        let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
        if item.setsCount > 0 && item.setsCount < item.targetSets {
            let setsText = "\(item.setsCount) / \(item.targetSets) \(setsWord)"
            if let w = item.topSetWeight, let r = item.topSetReps {
                return "\(setsText) · \(topLabel): \(weightUnit.formatWeight(w)) \(weightUnit.label) × \(r) \(repsWord)"
            } else {
                return setsText
            }
        } else if item.isCompleted {
            let setsText = "\(item.setsCount) \(setsWord)"
            if let w = item.topSetWeight, let r = item.topSetReps {
                return "\(setsText) · \(topLabel): \(weightUnit.formatWeight(w)) \(weightUnit.label) × \(r) \(repsWord)"
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
                .foregroundColor(AppColors.text)

            Text(items.map(\.name).joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundColor(AppColors.secondaryText)
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
                    .foregroundColor(AppColors.text)
            }

            // Exercise name & sub-info (sets + top set)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
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

                Text(formatSubInfo(for: item))
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
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
                        .foregroundColor(AppColors.completedGreen)
                }
            } else if item.setsCount > 0 {
                ZStack {
                    Circle()
                        .fill(AppColors.unfinishedOrange.opacity(0.15))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(AppColors.unfinishedOrange.opacity(0.35), lineWidth: 1))
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.unfinishedOrange)
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

