import SwiftUI

public struct HistoryDetailView: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var onBack: () -> Void
    var onActionWorkout: (() -> Void)? = nil

    @State private var isUnstartedExpanded: Bool = true
    @State private var isCompletedExpanded: Bool = true

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord] = [],
        onBack: @escaping () -> Void,
        onActionWorkout: (() -> Void)? = nil
    ) {
        self.detail = detail
        self.history = history
        self.onBack = onBack
        self.onActionWorkout = onActionWorkout
    }

    public var body: some View {
        let formattedDate = formattedFullDate(for: detail.date)

        let workoutTitle = detail.sessionRecord?.workoutTitle
            ?? detail.workout?.title
            ?? LanguageManager.t("history.scheduledWorkout")

        let items = exerciseProgressList()
        let allCompleted = !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets }
        let effectiveStatus: WorkoutDayStatus = (detail.status == .unfinished && allCompleted) ? .completed : detail.status

        let totalCompletedSets = detail.sessionRecord?.totalCompletedSets ?? items.reduce(0) { $0 + $1.completedSets }
        let totalPlannedSets = max(1, items.reduce(0) { $0 + $1.plannedSets })
        let progressFraction = effectiveStatus == .missed ? 0.0 : min(1.0, max(0.0, Double(totalCompletedSets) / Double(totalPlannedSets)))
        let progressPercent = Int(progressFraction * 100)

        let durationSeconds = detail.sessionRecord?.durationSeconds ?? 0
        let totalVolumeKg = detail.sessionRecord?.totalVolumeKg ?? 0.0

        let completedExercises = items.filter { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let halfwayExercises = items.filter { $0.completedSets > 0 && $0.completedSets < $0.plannedSets }
        let unstartedExercises = items.filter { $0.completedSets == 0 }

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

        VStack(spacing: 0) {
            // Top Navigation Bar
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("history-detail-back")

                Text(LanguageManager.t("history.workoutDetail").isEmpty ? "Workout Details" : LanguageManager.t("history.workoutDetail"))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(AppColors.text)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Date & Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedDate)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)

                        Text(workoutTitle)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .accessibilityIdentifier("history-detail-title")
                    }

                    // Status pill tag
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
                                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .accessibilityIdentifier("history-detail-status")

                    // Overall Progress Header Row & Bar
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(LanguageManager.formatSetsFraction(
                                    completed: effectiveStatus == .missed ? 0 : totalCompletedSets,
                                    total: totalPlannedSets
                                ))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)

                                Spacer()

                                Text(LanguageManager.formatPercent(progressPercent))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.text)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(AppColors.progressTrack)
                                        .frame(height: 10)
                                    Capsule()
                                        .fill(effectiveStatus == .completed ? AppColors.completedGreen : AppColors.accent)
                                        .frame(width: geo.size.width * CGFloat(progressFraction), height: 10)
                                }
                            }
                            .frame(height: 10)
                        }
                    }

                    // Key Stats Surface (3 Columns)
                    HStack(spacing: 0) {
                        // Duration
                        VStack(spacing: 4) {
                            Text(LanguageManager.t("history.duration"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.muted)
                            Text(effectiveStatus == .missed ? "0:00" : RestTimerUtils.formatSecondsToTime(durationSeconds))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                        Rectangle()
                            .fill(AppColors.border)
                            .frame(width: 1, height: 36)

                        // Sets
                        VStack(spacing: 4) {
                            Text(LanguageManager.t("history.sets"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.muted)
                            Text(effectiveStatus == .missed ? "0" : "\(totalCompletedSets)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)

                        Rectangle()
                            .fill(AppColors.border)
                            .frame(width: 1, height: 36)

                        // Volume
                        VStack(spacing: 4) {
                            Text(LanguageManager.t("history.volume"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.muted)
                            Text(effectiveStatus == .missed ? "0 kg" : "\(Int(totalVolumeKg)) kg")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    )

                    // Halfway Done Exercises
                    if !halfwayExercises.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("history.toContinue"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            ForEach(halfwayExercises) { item in
                                let setsLeft = max(0, item.plannedSets - item.completedSets)
                                let progress = min(1.0, max(0.0, Double(item.completedSets) / Double(max(1, item.plannedSets))))

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppColors.text)

                                        Spacer()

                                        Text(LanguageManager.formatSetsLeft(setsLeft))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(AppColors.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(AppColors.accent.opacity(0.15))
                                            )
                                    }

                                    let setsText = LanguageManager.formatExerciseSetsCompleted(completed: item.completedSets, planned: item.plannedSets)
                                    let repsWord = LanguageManager.shared.currentLanguage == "tr" ? "tekrar" : "reps"
                                    let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                                    let detailText: String = {
                                        if let w = item.topSetWeight, let r = item.topSetReps {
                                            return "\(setsText) · \(topLabel): \(WorkoutSessionUtils.formatWeight(w)) kg × \(r) \(repsWord)"
                                        }
                                        return setsText
                                    }()

                                    Text(detailText)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.secondaryText)

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
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(AppColors.toContinueSurface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(AppColors.accent, lineWidth: 1.5)
                                        )
                                )
                            }
                        }
                    }

                    // Completed Exercises Card
                    if !completedExercises.isEmpty {
                        let headerTitle = LanguageManager.formatCompletedExercisesCount(completedExercises.count)
                        let summaryNames = completedExercises.map(\.name).joined(separator: ", ")

                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isCompletedExpanded.toggle()
                                }
                            }) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(headerTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                        Text(summaryNames)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                            .lineLimit(isCompletedExpanded ? nil : 2)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .rotationEffect(.degrees(isCompletedExpanded ? 180 : 0))
                                }
                            }
                            .buttonStyle(.plain)

                            if isCompletedExpanded {
                                Divider()
                                    .background(AppColors.border.opacity(0.5))

                                VStack(spacing: 8) {
                                    ForEach(completedExercises) { item in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 6) {
                                                    Text(item.name)
                                                        .font(.system(size: 14, weight: .medium))
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

                                                let setsProgress = LanguageManager.formatSetsProgress(done: item.completedSets, total: item.plannedSets)
                                                let repsWord = LanguageManager.shared.currentLanguage == "tr" ? "tekrar" : "reps"
                                                let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                                                let detailText: String = {
                                                    if let w = item.topSetWeight, let r = item.topSetReps {
                                                        return "\(setsProgress) · \(topLabel): \(WorkoutSessionUtils.formatWeight(w)) kg × \(r) \(repsWord)"
                                                    }
                                                    return setsProgress
                                                }()

                                                Text(detailText)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AppColors.secondaryText)
                                                    .lineLimit(1)
                                            }

                                            Spacer(minLength: 4)

                                            ZStack {
                                                Circle()
                                                    .fill(AppColors.completedGreen.opacity(0.15))
                                                    .frame(width: 26, height: 26)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(AppColors.completedGreen)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(AppColors.surface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(AppColors.completedGreen.opacity(0.35), lineWidth: 1)
                                                )
                                        )
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                        .accessibilityIdentifier("history-completed-container")
                    }

                    // Not-Started Exercises Card
                    if !unstartedExercises.isEmpty {
                        let headerTitle = LanguageManager.formatUncompletedExercisesCount(unstartedExercises.count)
                        let summaryNames = unstartedExercises.map(\.name).joined(separator: ", ")

                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isUnstartedExpanded.toggle()
                                }
                            }) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(headerTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                        Text(summaryNames)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                            .lineLimit(isUnstartedExpanded ? nil : 2)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                        .rotationEffect(.degrees(isUnstartedExpanded ? 180 : 0))
                                }
                            }
                            .buttonStyle(.plain)

                            if isUnstartedExpanded {
                                Divider()
                                    .background(AppColors.border.opacity(0.5))

                                VStack(spacing: 8) {
                                    ForEach(unstartedExercises) { item in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(AppColors.text)
                                                let subtext = item.prescription.isEmpty
                                                    ? LanguageManager.formatSetsProgress(done: 0, total: item.plannedSets)
                                                    : item.prescription
                                                Text(subtext)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(AppColors.secondaryText)
                                            }

                                            Spacer()

                                            Text(LanguageManager.t("history.notStarted"))
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(AppColors.muted)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(AppColors.border.opacity(0.4))
                                                )
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(AppColors.surface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
                                                )
                                        )
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surfaceRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                        .accessibilityIdentifier("history-unstarted-container")
                    }

                    // Bottom Primary Action CTA Button
                    if effectiveStatus == .unfinished, let action = onActionWorkout {
                        Button(action: action) {
                            Text(LanguageManager.t("history.resumeWorkout"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.background)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history-action-button")
                    }

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityIdentifier("history-detail-screen")
    }

    private func formattedFullDate(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        df.dateStyle = .full
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
