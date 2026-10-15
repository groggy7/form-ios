import SwiftUI

public struct HistoryDetailView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let detail: HistoryDayDetailData
    let history: [WorkoutSessionRecord]
    var today: Date = Date()
    var onBack: () -> Void
    var onActionWorkout: (() -> Void)? = nil
    var weightUnit: WeightUnit = .kg
    var onActionSection: ((WorkoutDaySection) -> Void)? = nil
    @State private var collapsedSections: Set<String> = []
    @ScaledMetric(relativeTo: .body) private var rowFont: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailFont: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var cardFont: CGFloat = 18
    @ScaledMetric(relativeTo: .title2) private var headingFont: CGFloat = 22

    public init(detail: HistoryDayDetailData, history: [WorkoutSessionRecord] = [], today: Date = Date(),
        onBack: @escaping () -> Void, onActionWorkout: (() -> Void)? = nil,
        weightUnit: WeightUnit = .kg, onActionSection: ((WorkoutDaySection) -> Void)? = nil) {
        self.detail = detail
        self.history = history
        self.today = today
        self.onBack = onBack
        self.onActionWorkout = onActionWorkout
        self.weightUnit = weightUnit
        self.onActionSection = onActionSection
    }

    private var effectiveSections: [WorkoutDaySection] {
        if !detail.sections.isEmpty { return detail.sections }
        if detail.isCompletionMark { return [] }
        let workout = detail.sessionRecord?.workoutSnapshot ?? detail.workout
        let items = HistoryDayDetailData.buildExerciseProgress(sessionRecord: detail.sessionRecord, workout: workout, history: history)
        let context = detail.sessionRecord.map {
            HistoryDayDetailData.scheduleContext(record: $0, workout: workout, day: detail.date)
        }
        return [WorkoutDaySection(sessionRecord: detail.sessionRecord, workout: workout,
            workoutTitle: detail.sessionRecord?.workoutTitle ?? workout?.title ?? LanguageManager.t("history.scheduledWorkout"),
            completedSets: items.reduce(0) { $0 + $1.completedSets }, plannedSets: items.reduce(0) { $0 + $1.plannedSets },
            totalVolumeKg: HistoryDayDetailData.workingVolumeKg(detail.sessionRecord),
            durationSeconds: detail.sessionRecord?.durationSeconds ?? 0, isComplete: detail.status == .completed,
            exerciseItems: items, scheduledDate: detail.sessionRecord == nil ? detail.date : context?.0,
            scheduleSource: context?.1 ?? .currentPlan)]
    }

    var singleActionSection: WorkoutDaySection? {
        guard let section = effectiveSections.count == 1 ? effectiveSections.first : nil,
              section.canAct(on: detail.date, today: today) else { return nil }
        return section
    }

    var singleWorkoutAction: (() -> Void)? {
        guard let section = singleActionSection else { return nil }
        if let onActionSection { return { onActionSection(section) } }
        return onActionWorkout
    }

    var resumesSingleWorkout: Bool { singleActionSection?.sessionRecord != nil }

    public var body: some View {
        let _ = themeManager.currentTheme
        let sections = effectiveSections
        let recorded = sections.filter { $0.sessionRecord != nil }
        let totalSections = recorded.isEmpty ? sections : recorded
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.back"))
                .accessibilityIdentifier("history-detail-back")
                Text(LanguageManager.t("history.workoutDetail"))
                    .font(.system(size: cardFont, weight: .semibold)).foregroundStyle(AppColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedFullDate(detail.date)).font(.system(size: detailFont, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                        Text(LanguageManager.t(detail.isCompletionMark ? "history.markedComplete" : "history.dayBreakdown"))
                            .font(.system(size: headingFont, weight: .bold)).foregroundStyle(AppColors.text)
                            .accessibilityIdentifier("history-detail-title")
                        if sections.count > 1 {
                            Text(LanguageManager.t("history.multipleWorkouts", ["count": sections.count]))
                                .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                                .accessibilityIdentifier("history-detail-multiple-workouts")
                            Text(LanguageManager.t("history.recordedActivity"))
                                .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                                .accessibilityIdentifier("history-detail-status")
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LanguageManager.t("history.dayTotals"))
                            .font(.system(size: detailFont, weight: .medium)).foregroundStyle(AppColors.secondaryText)
                        HStack(alignment: .top, spacing: 10) {
                            metric(LanguageManager.t("history.sets"), "\(totalSections.reduce(0) { $0 + $1.completedSets }) / \(totalSections.reduce(0) { $0 + $1.plannedSets })")
                            metric(LanguageManager.t("history.duration"), formattedDuration(sections.reduce(0) { $0 + $1.durationSeconds }))
                            metric(LanguageManager.t("history.volume"), volumeText(sections.reduce(0.0) { $0 + $1.totalVolumeKg }, completedSets: sections.reduce(0) { $0 + $1.completedSets }))
                        }
                    }
                    .padding(14).background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("history-day-totals")
                    if detail.isCompletionMark {
                        Text(LanguageManager.t("history.noLoggedSets"))
                            .font(.system(size: rowFont)).foregroundStyle(AppColors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColors.border, lineWidth: 1))
                            .accessibilityIdentifier("history-completion-mark")
                    }
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        workoutCard(section, index: index, single: sections.count == 1)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-detail-screen")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            Text(value).font(.system(size: cardFont, weight: .bold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutCard(_ section: WorkoutDaySection, index: Int, single: Bool) -> some View {
        let key = "\(detail.dateString):\(section.id)"
        let expanded = !collapsedSections.contains(key)
        let items = section.exerciseItems.enumerated().sorted { a, b in
            let aRank = exerciseRank(a.element), bRank = exerciseRank(b.element)
            return aRank == bRank ? a.offset < b.offset : aRank < bRank
        }.map(\.element)
        let past = Calendar.current.startOfDay(for: detail.date) < Calendar.current.startOfDay(for: today)
        let statusColor = section.isComplete ? AppColors.completedGreen
            : section.sessionRecord != nil ? AppColors.unfinishedOrange : past ? AppColors.missedRed : AppColors.secondaryText
        let statusText = section.isComplete ? "history.completed" : section.isLiveSession ? "history.inProgress"
            : section.sessionRecord != nil ? "history.unfinished" : past ? "history.missed" : "history.notStarted"
        let progress = min(1, max(0, Double(section.completedSets) / Double(max(1, section.plannedSets))))
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    contextLabel(section, index: index)
                    Spacer(minLength: 0)
                    statusPill(statusText, color: statusColor, id: single ? "history-detail-status" : "history-section-status-\(section.id)")
                }
                VStack(alignment: .leading, spacing: 6) {
                    contextLabel(section, index: index)
                    statusPill(statusText, color: statusColor, id: single ? "history-detail-status" : "history-section-status-\(section.id)")
                }
            }
            Text(section.workoutTitle).font(.system(size: cardFont, weight: .bold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("history-section-title-\(section.id)")
            if let label = section.scheduleLabel(on: detail.date) {
                Text(label).font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(section.scheduledDate == nil ? "history-section-schedule-unknown-\(section.id)" : "history-section-date-\(section.id)")
            }
            Text(LanguageManager.t(items.count == 1 ? "builder.exerciseCountOne" : "weekly.exerciseCount", ["count": items.count]) + " · "
                + LanguageManager.formatSetsFraction(completed: section.completedSets, total: section.plannedSets))
                .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            if !single {
                Text(formattedDuration(section.durationSeconds) + " · " + volumeText(section.totalVolumeKg, completedSets: section.completedSets))
                    .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            }
            HStack(spacing: 10) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.surfaceRaised)
                        Capsule().fill(section.isComplete ? AppColors.completedGreen : AppColors.accent)
                            .frame(width: geometry.size.width * CGFloat(progress))
                    }
                }.frame(height: 5)
                Text(LanguageManager.formatPercent(Int(progress * 100)))
                    .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            }
            Button {
                if expanded { collapsedSections.insert(key) } else { collapsedSections.remove(key) }
            } label: {
                HStack(spacing: 8) {
                    Text(LanguageManager.t("history.exerciseSummaries"))
                    Spacer(minLength: 0)
                    Text("\(items.count)")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(LanguageManager.t(expanded ? "progression.coach.expanded" : "progression.coach.collapsed"))
            .accessibilityHint(LanguageManager.t(expanded ? "builder.collapseDay" : "builder.expandDay"))
            .accessibilityIdentifier("history-exercises-toggle-\(section.id)")
            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { rowIndex, item in
                        exerciseRow(item, past: past)
                        if rowIndex < items.count - 1 { Rectangle().fill(AppColors.border).frame(height: 1) }
                    }
                }
                .background(AppColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("history-exercise-list-\(section.id)")
            }
            if section.canAct(on: detail.date, today: today), let action = sectionAction(section, single: single) {
                Button(action: action) {
                    Text(LanguageManager.t(section.sessionRecord != nil ? "history.resumeWorkout" : "history.startWorkout"))
                        .font(.system(size: rowFont, weight: .semibold)).foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(single ? "history-action-button" : "history-section-action-\(section.id)")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-workout-card-\(section.id)")
    }

    private func sectionAction(_ section: WorkoutDaySection, single: Bool) -> (() -> Void)? {
        if let onActionSection { return { onActionSection(section) } }
        return single ? onActionWorkout : nil
    }

    private func contextLabel(_ section: WorkoutDaySection, index: Int) -> some View {
        Text(section.contextText(on: detail.date, today: today, index: index))
            .font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("history-section-context-\(section.id)")
    }

    private func statusPill(_ key: String, color: Color, id: String) -> some View {
        Text(LanguageManager.t(key)).font(.system(size: detailFont, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
            .accessibilityIdentifier(id)
    }

    private func exerciseRank(_ item: HistoryDayExerciseProgress) -> Int {
        if item.completedSets > 0 && item.completedSets < item.plannedSets { return 0 }
        if item.completedSets > 0 && item.completedSets >= item.plannedSets { return 1 }
        return 2
    }

    private func exerciseRow(_ item: HistoryDayExerciseProgress, past: Bool) -> some View {
        let completed = item.completedSets >= item.plannedSets && item.plannedSets > 0
        let partial = item.completedSets > 0 && !completed
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: rowFont, weight: .semibold)).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isPr {
                        Text("PR").font(.system(size: detailFont, weight: .bold)).foregroundStyle(AppColors.orangePrText)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(AppColors.orangePrBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(exerciseSubtitle(item)).font(.system(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: completed ? "checkmark" : partial ? "clock" : "minus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(completed ? AppColors.completedGreen : partial ? AppColors.unfinishedOrange : AppColors.muted)
                .frame(width: 20, height: 20)
                .accessibilityLabel(LanguageManager.t(completed ? "history.completed" : partial ? "history.unfinished" : past ? "history.notCompleted" : "history.notStarted"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history-exercise-\(item.name)")
    }

    private func exerciseSubtitle(_ item: HistoryDayExerciseProgress) -> String {
        if item.completedSets == 0 {
            return item.prescription.isEmpty ? LanguageManager.formatSetsFraction(completed: 0, total: item.plannedSets) : item.prescription
        }
        let sets = LanguageManager.formatSetsFraction(completed: item.completedSets, total: item.plannedSets)
        if let weight = item.topSetWeight, let reps = item.topSetReps {
            return sets + " · \(LanguageManager.t("history.top")): \(weightUnit.formatDisplayWeight(weight)) \(weightUnit.label) × \(reps)"
        }
        return sets
    }

    private func volumeText(_ volumeKg: Double, completedSets: Int) -> String {
        WorkoutSessionUtils.bodyweightVolumeLabel(volumeKg, completedSets: completedSets)
            ?? "\(weightUnit.formatVolume(volumeKg)) \(weightUnit.label)"
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let tr = LanguageManager.shared.currentLanguage.hasPrefix("tr")
        if seconds >= 3600 {
            return tr ? "\(seconds / 3600)sa \(seconds % 3600 / 60)dk" : "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
        return tr ? "\(seconds / 60)dk \(seconds % 60)sn" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}
