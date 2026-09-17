import SwiftUI

public struct HistoryDetailView: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var onBack: () -> Void
    var onActionWorkout: (() -> Void)? = nil

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
        let allCompleted = !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let effectiveStatus: WorkoutDayStatus = (detail.status == .unfinished && allCompleted) ? .completed : detail.status

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
                VStack(alignment: .leading, spacing: 18) {
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
                    let isMissed = effectiveStatus == .missed || (!items.isEmpty && items.allSatisfy { $0.completedSets == 0 } && detail.date < Calendar.current.startOfDay(for: Date()))

                    if allCompleted {
                        // Completed Day (Picture 1)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(LanguageManager.t("history.exercises").isEmpty ? "Exercises" : LanguageManager.t("history.exercises"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Text("\(items.count)")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
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
                            HStack {
                                Text(LanguageManager.t("history.exercises").isEmpty ? "Exercises" : LanguageManager.t("history.exercises"))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Spacer()
                                Text("\(items.count)")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(AppColors.secondaryText)
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

                            if let action = onActionWorkout {
                                Spacer().frame(height: 8)
                                Button(action: action) {
                                    Text(LanguageManager.t("history.startWorkout"))
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
                        }
                    } else {
                        // Half-Done / In-Progress Workout (Picture 2)
                        VStack(alignment: .leading, spacing: 20) {
                            // Section 1: Continue Workout Card
                            if !halfwayExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(LanguageManager.t("history.continueWorkout").isEmpty ? "Continue workout" : LanguageManager.t("history.continueWorkout"))
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(AppColors.text)

                                    ForEach(halfwayExercises) { item in
                                        let setsLeft = max(0, item.plannedSets - item.completedSets)
                                        let progress = min(1.0, max(0.0, Double(item.completedSets) / Double(max(1, item.plannedSets))))

                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack {
                                                Text(item.name)
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(AppColors.text)
                                                    .lineLimit(1)

                                                Spacer()

                                                Text(LanguageManager.formatSetsLeft(setsLeft))
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(AppColors.accent)
                                            }

                                            let setsText = LanguageManager.formatExerciseSetsCompleted(completed: item.completedSets, planned: item.plannedSets)
                                            let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                                            let detailText: String = {
                                                if let w = item.topSetWeight, let r = item.topSetReps {
                                                    return "\(setsText) · \(topLabel): \(WorkoutSessionUtils.formatWeight(w)) kg × \(r)"
                                                }
                                                return setsText
                                            }()

                                            Text(detailText)
                                                .font(.system(size: 13))
                                                .foregroundColor(AppColors.secondaryText)

                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color(hex: 0x1D262B))
                                                        .frame(height: 6)
                                                    Capsule()
                                                        .fill(AppColors.accent)
                                                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                                                }
                                            }
                                            .frame(height: 6)

                                            if let action = onActionWorkout {
                                                Button(action: action) {
                                                    Text(LanguageManager.t("history.resume").isEmpty ? "Resume" : LanguageManager.t("history.resume"))
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundColor(AppColors.background)
                                                        .padding(.horizontal, 20)
                                                        .padding(.vertical, 8)
                                                        .background(AppColors.accent)
                                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityIdentifier("history-action-button")
                                            }
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

                            // Section 2: Completed Exercises
                            if !completedExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(LanguageManager.t("history.completedSection").isEmpty ? "Completed" : LanguageManager.t("history.completedSection"))
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Text("\(completedExercises.count)")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(AppColors.secondaryText)
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

                            // Section 3: Uncompleted Exercises
                            if !unstartedExercises.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(LanguageManager.t("history.uncompletedSection").isEmpty ? "Uncompleted" : LanguageManager.t("history.uncompletedSection"))
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Text("\(unstartedExercises.count)")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(AppColors.secondaryText)
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

                            // Fallback Resume Workout CTA if no continue card
                            if halfwayExercises.isEmpty, let action = onActionWorkout {
                                Spacer().frame(height: 8)
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
                        }
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
