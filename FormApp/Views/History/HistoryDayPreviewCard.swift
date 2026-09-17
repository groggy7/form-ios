import SwiftUI

public struct HistoryDayPreviewCard: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    let onOpenDetail: () -> Void

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord],
        onOpenDetail: @escaping () -> Void
    ) {
        self.detail = detail
        self.history = history
        self.onOpenDetail = onOpenDetail
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

    public var body: some View {
        let prExercises: Set<String> = {
            if let record = detail.sessionRecord {
                return PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: record)
            }
            return []
        }()

        let workoutTitle = detail.sessionRecord?.workoutTitle
            ?? detail.workout?.title
            ?? LanguageManager.t("history.scheduledWorkout")

        let statusColor: Color = {
            switch detail.status {
            case .completed: return AppColors.completedGreen
            case .unfinished: return AppColors.unfinishedOrange
            case .missed: return AppColors.missedRed
            }
        }()

        let statusLabel: String = {
            switch detail.status {
            case .completed: return LanguageManager.t("history.completed")
            case .unfinished: return LanguageManager.t("history.unfinished")
            case .missed: return LanguageManager.t("history.missed")
            }
        }()

        let dayNumberText: String = {
            if let workout = detail.workout {
                return "DAY \(workout.day)"
            }
            let cal = Calendar.current
            let dayNum = cal.component(.day, from: detail.date)
            return "DAY \(dayNum)"
        }()

        // Time range & active duration string
        let timeDurationText: String = {
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
        }()

        // Summary metrics calculation
        let volumeKg: Double = {
            if let vol = detail.sessionRecord?.totalVolumeKg, vol > 0 {
                return vol
            }
            if let logs = detail.sessionRecord?.exerciseLogs {
                return logs.reduce(0.0) { sum, log in
                    sum + log.sets.reduce(0.0) { sSum, s in sSum + (s.weightKg ?? 0.0) * Double(s.reps ?? 0) }
                }
            }
            return 0.0
        }()

        let exerciseList: [PreviewExerciseItem] = {
            let planned = detail.workout?.exercises ?? []
            let logs = detail.sessionRecord?.exerciseLogs ?? []
            if !logs.isEmpty {
                return logs.enumerated().map { index, log in
                    let ex = planned.first {
                        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame ||
                        $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(log.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                    }
                    let name = ex?.displayName ?? ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: log.exerciseName)
                    let setsCount = log.sets.count
                    let targetSets = log.targetSets ?? ex.map { WorkoutSessionUtils.initialSetCount(exercise: $0) } ?? setsCount
                    let validSets = log.sets.filter { ($0.weightKg ?? 0.0) > 0.0 && ($0.reps ?? 0) > 0 }
                    let topSet = validSets.max { a, b in
                        if (a.weightKg ?? 0.0) != (b.weightKg ?? 0.0) {
                            return (a.weightKg ?? 0.0) < (b.weightKg ?? 0.0)
                        }
                        return (a.reps ?? 0) < (b.reps ?? 0)
                    }
                    let normKey = PersonalRecordTracker.normalizeExerciseKey(log.exerciseName)
                    let isPr = prExercises.contains(normKey)
                    return PreviewExerciseItem(
                        index: index + 1,
                        name: name,
                        setsCount: setsCount,
                        targetSets: targetSets,
                        topSetWeight: topSet?.weightKg,
                        topSetReps: topSet?.reps,
                        isPr: isPr,
                        isCompleted: setsCount >= targetSets && setsCount > 0
                    )
                }
            } else {
                return planned.enumerated().map { index, ex in
                    let targetSets = WorkoutSessionUtils.initialSetCount(exercise: ex)
                    return PreviewExerciseItem(
                        index: index + 1,
                        name: ex.displayName,
                        setsCount: 0,
                        targetSets: targetSets,
                        topSetWeight: nil,
                        topSetReps: nil,
                        isPr: false,
                        isCompleted: false
                    )
                }
            }
        }()

        let totalCompletedSets = detail.sessionRecord?.totalCompletedSets ?? exerciseList.reduce(0) { $0 + $1.setsCount }
        let totalPlannedSets = max(1, exerciseList.reduce(0) { $0 + $1.targetSets })
        let prsHitCount = prExercises.count

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

                    Image(systemName: {
                        switch detail.status {
                        case .completed: return "checkmark"
                        case .unfinished: return "clock"
                        case .missed: return "xmark"
                        }
                    }())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(statusColor)
                }
            }

            // Metric Tiles Row: VOLUME, SETS, MOVES, PRS HIT
            HStack(spacing: 8) {
                metricTile(
                    title: LanguageManager.t("history.volume").uppercased(),
                    value: volumeKg > 0.0 ? "\(WorkoutSessionUtils.formatWeight(volumeKg)) kg" : "0 kg",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.sets").uppercased(),
                    value: "\(totalCompletedSets) / \(totalPlannedSets)",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.moves").uppercased().isEmpty ? "MOVES" : LanguageManager.t("history.moves").uppercased(),
                    value: "\(exerciseList.count) Ex",
                    isPrTile: false
                )
                metricTile(
                    title: LanguageManager.t("history.prsHit").uppercased().isEmpty ? "PRS HIT" : LanguageManager.t("history.prsHit").uppercased(),
                    value: prsHitCount > 0 ? "⚡ \(prsHitCount) New" : "-",
                    isPrTile: prsHitCount > 0
                )
            }

            // Exercise List Rows
            VStack(spacing: 8) {
                let previewItems = Array(exerciseList.prefix(4))
                ForEach(previewItems) { item in
                    exerciseRowItem(item: item)
                }
                if exerciseList.count > 4 {
                    let remaining = exerciseList.count - 4
                    Text("+\(remaining) more exercises in full breakdown")
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
                .foregroundColor(isPrTile ? AppColors.goldPrText : AppColors.muted)
                .tracking(0.5)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isPrTile ? AppColors.goldPrText : AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isPrTile ? AppColors.goldPrBg : AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isPrTile ? AppColors.goldPrBorder : AppColors.border, lineWidth: 1)
                )
        )
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
                            .foregroundColor(AppColors.goldPrText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(AppColors.goldPrBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(AppColors.goldPrBorder, lineWidth: 1)
                                    )
                            )
                    }
                }

                let subInfo: String = {
                    if let w = item.topSetWeight, let r = item.topSetReps {
                        return "\(item.setsCount) sets · Top: \(WorkoutSessionUtils.formatWeight(w)) kg × \(r) reps"
                    } else if item.setsCount > 0 {
                        return "\(item.setsCount) / \(item.targetSets) sets"
                    } else {
                        return "\(item.targetSets) sets"
                    }
                }()

                Text(subInfo)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Status label on the right
            Text(item.isCompleted ? LanguageManager.t("history.completed") : (item.setsCount > 0 ? LanguageManager.t("history.unfinished") : LanguageManager.t("history.notStarted")))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(item.isCompleted ? AppColors.completedGreen : (item.setsCount > 0 ? AppColors.unfinishedOrange : AppColors.muted))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        )
    }
}
