import SwiftUI

public struct HistoryDetailView: View {
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var onBack: () -> Void
    var onActionWorkout: (() -> Void)? = nil
    var weightUnit: WeightUnit = .kg
    var onActionSection: ((WorkoutDaySection) -> Void)? = nil

    public init(
        detail: HistoryDayDetailData,
        history: [WorkoutSessionRecord] = [],
        onBack: @escaping () -> Void,
        onActionWorkout: (() -> Void)? = nil,
        weightUnit: WeightUnit = .kg,
        onActionSection: ((WorkoutDaySection) -> Void)? = nil
    ) {
        self.detail = detail
        self.history = history
        self.onBack = onBack
        self.onActionWorkout = onActionWorkout
        self.weightUnit = weightUnit
        self.onActionSection = onActionSection
    }

    public var body: some View {
        let formattedDate = formattedFullDate(for: detail.date)

        let workoutTitle: String = {
            if detail.sections.count > 1 {
                return LanguageManager.t("history.dayBreakdown")
            }
            return detail.sessionRecord?.workoutTitle
                ?? detail.workout?.title
                ?? LanguageManager.t("history.scheduledWorkout")
        }()

        let items = exerciseProgressList()
        let allCompleted = detail.sections.isEmpty
            ? !items.isEmpty && items.allSatisfy { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
            : detail.sections.allSatisfy(\.isComplete)
        let effectiveStatus = detail.status
        let isMissed = effectiveStatus == .missed || (!items.isEmpty && items.allSatisfy { $0.completedSets == 0 } && detail.date < Calendar.current.startOfDay(for: Date()))
        let showActionButton = detail.sections.count <= 1 && onActionWorkout != nil && !allCompleted
        let actionSection = detail.sections.first { $0.canAct(on: detail.date) }
        let resumeAction = actionSection?.isLiveSession == true
            || (Calendar.current.isDateInToday(detail.date) && (actionSection?.sessionRecord ?? detail.sessionRecord) != nil)
        let actionButtonText = LanguageManager.t(resumeAction ? "history.resumeWorkout" : "history.startWorkout")

        let completedExercises = items.filter { $0.completedSets >= $0.plannedSets && $0.plannedSets > 0 }
        let halfwayExercises = items.filter { $0.completedSets > 0 && $0.completedSets < $0.plannedSets }
        let unstartedExercises = items.filter { $0.completedSets == 0 }

        let totalCompletedSets = detail.sections.count > 1
            ? detail.sections.reduce(0) { $0 + $1.completedSets }
            : items.reduce(0) { $0 + $1.completedSets }
        let totalPlannedSets = max(1, detail.sections.count > 1
            ? detail.recordedSections.reduce(0) { $0 + $1.plannedSets }
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
            return weightUnit.formatVolume(totalVolumeKg)
        }()

        let (statusColor, statusBg, statusText): (Color, Color, String) = {
            if detail.sections.count > 1 {
                return (AppColors.secondaryText, AppColors.surfaceRaised, LanguageManager.t("history.recordedActivity"))
            }
            switch effectiveStatus {
            case .unfinished:
                return (AppColors.unfinishedOrange, AppColors.unfinishedOrange.opacity(0.15), LanguageManager.t("history.unfinished"))
            case .missed:
                return (AppColors.missedRed, AppColors.missedRed.opacity(0.15), LanguageManager.t("history.missed"))
            case .completed:
                return (AppColors.completedGreen, AppColors.completedGreen.opacity(0.15), LanguageManager.t("history.completed"))
            }
        }()

        let scheduledOriginLabel: String? = {
            if let section = detail.sections.first, section.originDate != nil {
                return section.scheduleLabel(on: detail.date)
            }
            guard let record = detail.sessionRecord else { return nil }
            let (scheduled, source) = HistoryDayDetailData.scheduleContext(record: record, workout: detail.workout, day: detail.date)
            guard let scheduled, !Calendar.current.isDate(scheduled, inSameDayAs: detail.date) else { return nil }
            return LanguageManager.t(source == .recorded ? "history.originallyScheduled" : "history.usualSchedule",
                ["date": formattedFullDate(for: scheduled)])
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

            ZStack(alignment: .bottom) {
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

                        // Status Pill Tag & Scheduled Origin
                        HStack(spacing: 8) {
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

                            if detail.sections.count > 1 {
                                Text(LanguageManager.t("history.multipleWorkouts", ["count": "\(detail.sections.count)"]))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppColors.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                    .accessibilityIdentifier("history-detail-multiple-workouts")
                            } else if let scheduledOrigin = scheduledOriginLabel {
                                Text("🗓️ \(scheduledOrigin)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppColors.surfaceRaised)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(AppColors.border, lineWidth: 1)
                                            )
                                    )
                                    .accessibilityIdentifier("history-detail-scheduled-origin")
                            }
                        }

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
                                Text("\(formattedVolume) \(weightUnit.label)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppColors.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                        }

                        // Progress Bar + Percentage Row
                        if detail.sections.count <= 1 {
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

                        }

                        // Content Sections
                        if detail.sections.count > 1 {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(Array(detail.sections.enumerated()), id: \.element.id) { sIndex, sec in
                                    workoutSection(sec, index: sIndex)

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
                                                            return "\(setsText) · \(topLabel): \(weightUnit.formatWeight(w)) \(weightUnit.label) × \(r) \(repsLabel)"
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
                .padding(.top, 10)
                .padding(.bottom, showActionButton ? 96 : 24)
            }

            if showActionButton, let action = onActionWorkout {
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            AppColors.background.opacity(0),
                            AppColors.background.opacity(0.85),
                            AppColors.background
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
                    .padding(.bottom, 16)
                    .background(AppColors.background)
                }
            }
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
                    if isCompleted || item.completedSets > 0 {
                        let setsFraction = LanguageManager.formatSetsFraction(completed: item.completedSets, total: item.plannedSets)
                        let topLabel = LanguageManager.t("history.top").isEmpty ? "Top" : LanguageManager.t("history.top")
                        if let w = item.topSetWeight, let r = item.topSetReps {
                            return "\(setsFraction) · \(topLabel): \(weightUnit.formatWeight(w)) \(weightUnit.label) × \(r)"
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
            } else if item.completedSets > 0 {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppColors.unfinishedOrange)
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

    private func workoutSection(_ section: WorkoutDaySection, index: Int) -> some View {
        let statusColor = section.isComplete ? AppColors.completedGreen
            : section.sessionRecord != nil ? AppColors.unfinishedOrange : AppColors.secondaryText
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.workoutTitle)
                    .font(.system(size: 17, weight: .bold)).foregroundColor(AppColors.text)
                    .accessibilityIdentifier("history-section-title-\(section.id)")
                Spacer()
                Text("\(section.exerciseItems.count)")
                    .font(.system(size: 15)).foregroundColor(AppColors.secondaryText).frame(width: 20)
            }
            Text(section.contextText(on: detail.date, index: index))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(section.scheduledDate.map { Calendar.current.isDate($0, inSameDayAs: detail.date) } == true
                    ? AppColors.accent : AppColors.secondaryText)
                .accessibilityIdentifier("history-section-context-\(section.id)")
            if let label = section.scheduleLabel(on: detail.date) {
                Text(label).font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                    .accessibilityIdentifier("history-section-date-\(section.id)")
            }
            Text(section.statusText).font(.system(size: 12, weight: .medium)).foregroundColor(statusColor)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(statusColor.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(statusColor.opacity(0.3), lineWidth: 1))
                .accessibilityIdentifier("history-section-status-\(section.id)")
            Text(LanguageManager.formatSetsFraction(completed: section.completedSets, total: section.plannedSets)
                + (section.totalVolumeKg > 0 ? " · \(weightUnit.formatVolume(section.totalVolumeKg))" : ""))
                .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
            if section.canAct(on: detail.date), let onActionSection {
                Button { onActionSection(section) } label: {
                    Text(LanguageManager.t(section.isLiveSession || (Calendar.current.isDateInToday(detail.date) && section.sessionRecord != nil)
                        ? "history.resumeWorkout" : "history.startWorkout"))
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityIdentifier("history-section-action-\(section.id)")
            }
            VStack(spacing: 0) {
                ForEach(Array(section.exerciseItems.enumerated()), id: \.element.id) { index, item in
                    exerciseRow(item: item, isCompleted: item.completedSets >= item.plannedSets && item.plannedSets > 0)
                    if index < section.exerciseItems.count - 1 { Divider().background(Color.white.opacity(0.08)) }
                }
            }
        }
    }

    private func formattedFullDate(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: LanguageManager.shared.currentLanguage)
        df.dateStyle = .full
        return df.string(from: date).capitalized
    }

    private typealias ExerciseProgressItem = HistoryDayExerciseProgress

    private func exerciseProgressList() -> [ExerciseProgressItem] {
        if !detail.sections.isEmpty {
            return detail.sections.flatMap { $0.exerciseItems }
        }
        return HistoryDayDetailData.buildExerciseProgress(
            sessionRecord: detail.sessionRecord,
            workout: detail.workout,
            history: history
        )
    }
}
