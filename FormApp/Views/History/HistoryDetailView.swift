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
    /// Offers a rating on unrated exercises; existing ratings can always be changed while `onRateJointStress` is set.
    var jointStressRatings: Bool = false
    var onRateJointStress: ((WorkoutSessionRecord, Int, JointStress?) -> Void)? = nil
    @State private var socialRequest: SocialShareRequest?
    @State private var collapsedSections: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var rowFont: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailFont: CGFloat = 12
    @ScaledMetric(relativeTo: .headline) private var cardFont: CGFloat = 18
    @ScaledMetric(relativeTo: .title2) private var workoutTitleFont: CGFloat = 24
    @ScaledMetric(relativeTo: .headline) private var exerciseHeadingFont: CGFloat = 16
    @ScaledMetric(relativeTo: .title2) private var headingFont: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var totalLabelFont: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var totalUnitFont: CGFloat = 13
    @ScaledMetric(relativeTo: .headline) private var totalValueFont: CGFloat = 20

    public init(detail: HistoryDayDetailData, history: [WorkoutSessionRecord] = [], today: Date = Date(),
        onBack: @escaping () -> Void, onActionWorkout: (() -> Void)? = nil,
        weightUnit: WeightUnit = .kg, onActionSection: ((WorkoutDaySection) -> Void)? = nil,
        jointStressRatings: Bool = false, onRateJointStress: ((WorkoutSessionRecord, Int, JointStress?) -> Void)? = nil) {
        self.jointStressRatings = jointStressRatings
        self.onRateJointStress = onRateJointStress
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
                    .font(.app(size: cardFont, weight: .semibold)).foregroundStyle(AppColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formattedFullDate(detail.date)).font(.app(size: detailFont, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                        Text(LanguageManager.t(detail.isCompletionMark ? "history.markedComplete" : "history.dayBreakdown"))
                            .font(.app(size: headingFont, weight: .bold)).foregroundStyle(AppColors.text)
                            .accessibilityIdentifier("history-detail-title")
                        if sections.count > 1 {
                            Text(LanguageManager.t("history.multipleWorkouts", ["count": sections.count]))
                                .font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                                .accessibilityIdentifier("history-detail-multiple-workouts")
                            Text(LanguageManager.t("history.recordedActivity"))
                                .font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                                .accessibilityIdentifier("history-detail-status")
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LanguageManager.t("history.dayTotals"))
                            .font(.app(size: totalLabelFont, weight: .medium)).foregroundStyle(AppColors.secondaryText)
                        if dynamicTypeSize >= .xxLarge {
                            VStack(spacing: 6) { totalMetrics(sections, recorded: totalSections) }
                        } else {
                            HStack(spacing: 6) { totalMetrics(sections, recorded: totalSections) }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14).background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("history-day-totals")
                    if detail.isCompletionMark {
                        Text(LanguageManager.t("history.noLoggedSets"))
                            .font(.app(size: rowFont)).foregroundStyle(AppColors.secondaryText)
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
        .sheet(item: $socialRequest) { request in SocialCardComposer(request: request) { socialRequest = nil } }
    }

    @ViewBuilder
    private func totalMetrics(_ sections: [WorkoutDaySection], recorded: [WorkoutDaySection]) -> some View {
        let volume = sections.reduce(0.0) { $0 + $1.totalVolumeKg }
        let bodyweight = WorkoutSessionUtils.bodyweightVolumeLabel(volume,
            completedSets: sections.reduce(0) { $0 + $1.completedSets })
        metric(LanguageManager.t("history.sets"),
            Text("\(recorded.reduce(0) { $0 + $1.completedSets })")
                + Text(" / \(recorded.reduce(0) { $0 + $1.plannedSets })")
                    .font(.app(size: totalUnitFont)).foregroundColor(AppColors.secondaryText))
        metric(LanguageManager.t("history.duration"),
            formattedDuration(sections.reduce(0) { $0 + $1.durationSeconds }).reduce(Text("")) { result, character in
                result + Text(String(character))
                    .font(.app(size: character.isLetter ? totalUnitFont : totalValueFont,
                        weight: character.isLetter ? .regular : .bold))
                    .foregroundColor(character.isLetter ? AppColors.secondaryText : AppColors.text)
            })
        metric(LanguageManager.t("history.volume") + (bodyweight == nil ? " · \(weightUnit.label)" : ""),
            Text(bodyweight ?? weightUnit.formatVolume(volume)))
    }

    private func metric(_ label: String, _ value: Text) -> some View {
        let stacked = dynamicTypeSize >= .xxLarge
        return Group {
            if stacked {
                HStack(spacing: 12) {
                    Text(label).font(.app(size: totalLabelFont)).foregroundStyle(AppColors.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    value.font(.app(size: totalValueFont, weight: .bold)).foregroundStyle(AppColors.text)
                        .monospacedDigit().multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.padding(12)
            } else {
                VStack(spacing: 0) {
                    Text(label).font(.app(size: totalLabelFont)).foregroundStyle(AppColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    value.font(.app(size: totalValueFont, weight: .bold)).foregroundStyle(AppColors.text)
                        .monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
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
        return VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    workoutDate
                    Spacer(minLength: 0)
                    statusPill(statusText, color: statusColor, id: single ? "history-detail-status" : "history-section-status-\(section.id)")
                }
                VStack(alignment: .leading, spacing: 10) {
                    workoutDate
                    statusPill(statusText, color: statusColor, id: single ? "history-detail-status" : "history-section-status-\(section.id)")
                }
            }
            if !single { contextLabel(section, index: index) }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.workoutTitle).font(.app(size: workoutTitleFont, weight: .bold)).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("history-section-title-\(section.id)")
                    Text(LanguageManager.t(items.count == 1 ? "builder.exerciseCountOne" : "weekly.exerciseCount", ["count": items.count]) + " · "
                        + (section.isComplete ? LanguageManager.shared.plural("exercise.history.setsCount", section.completedSets)
                            : LanguageManager.formatSetsFraction(completed: section.completedSets, total: section.plannedSets)))
                        .font(.app(size: rowFont)).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let record = section.sessionRecord, !section.isLiveSession,
                   record.exerciseLogs.contains(where: { !RecordEngine.workingSets($0).isEmpty }) {
                    Button {
                        let cards = SocialCards.workout(history: history, record: record, unit: weightUnit)
                        if !cards.isEmpty { socialRequest = SocialShareRequest(cards: cards) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 48, height: 48)
                            .background(AppColors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LanguageManager.t("social.share"))
                    .accessibilityIdentifier("history-share-\(record.id)")
                }
            }
            SavedNote(text: section.sessionRecord?.note)
            if let label = section.scheduleLabel(on: detail.date) {
                Text(label).font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(section.scheduledDate == nil ? "history-section-schedule-unknown-\(section.id)" : "history-section-date-\(section.id)")
            }
            if !single {
                Text(formattedDuration(section.durationSeconds) + " · " + volumeText(section.totalVolumeKg, completedSets: section.completedSets))
                    .font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            }
            if !section.isComplete {
                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppColors.surfaceRaised)
                            Capsule().fill(AppColors.accent)
                                .frame(width: geometry.size.width * CGFloat(progress))
                        }
                    }.frame(height: 5)
                    Text(LanguageManager.formatPercent(Int(progress * 100)))
                        .font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                }
            }
            Rectangle().fill(AppColors.border).frame(height: 1)
            Button {
                if expanded { collapsedSections.insert(key) } else { collapsedSections.remove(key) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 20)).frame(width: 22)
                        .padding(.trailing, 4)
                    Text(LanguageManager.t("history.exercises"))
                        .font(.app(size: exerciseHeadingFont, weight: .semibold)).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(items.count)").font(.app(size: exerciseHeadingFont))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(AppColors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(LanguageManager.t(expanded ? "progression.coach.expanded" : "progression.coach.collapsed"))
            .accessibilityHint(LanguageManager.t(expanded ? "builder.collapseDay" : "builder.expandDay"))
            .accessibilityIdentifier("history-exercises-toggle-\(section.id)")
            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { rowIndex, item in
                        exerciseRow(item, past: past, rate: jointRating(item, in: section))
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
                        .font(.app(size: rowFont, weight: .semibold)).foregroundStyle(AppColors.accent)
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
            .font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("history-section-context-\(section.id)")
    }

    private var workoutDate: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 18))
            Text(formattedWorkoutDate(detail.date)).font(.app(size: detailFont))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppColors.secondaryText)
        .padding(.vertical, 6)
    }

    private func statusPill(_ key: String, color: Color, id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: key == "history.completed" ? "checkmark.circle" :
                ["history.unfinished", "history.inProgress"].contains(key) ? "clock" : "minus")
                .font(.system(size: 16)).accessibilityHidden(true)
            Text(LanguageManager.t(key)).font(.app(size: detailFont, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1))
    }

    private func exerciseRank(_ item: HistoryDayExerciseProgress) -> Int {
        if item.completedSets > 0 && item.completedSets < item.plannedSets { return 0 }
        if item.completedSets > 0 && item.completedSets >= item.plannedSets { return 1 }
        return 2
    }

    /// A saved exercise with working sets can be rated afterwards: joint discomfort often shows up later.
    private func jointRating(_ item: HistoryDayExerciseProgress, in section: WorkoutDaySection) -> ((JointStress?) -> Void)? {
        guard let onRateJointStress, !section.isLiveSession, let record = section.sessionRecord, let logIndex = item.logIndex,
              record.exerciseLogs.indices.contains(logIndex),
              record.exerciseLogs[logIndex].sets.contains(where: { !$0.isWarmup }),
              jointStressRatings || item.jointStress != nil else { return nil }
        return { onRateJointStress(record, logIndex, $0) }
    }

    private func exerciseRow(_ item: HistoryDayExerciseProgress, past: Bool, rate: ((JointStress?) -> Void)? = nil) -> some View {
        let completed = item.completedSets >= item.plannedSets && item.plannedSets > 0
        let partial = item.completedSets > 0 && !completed
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.app(size: rowFont, weight: .semibold)).foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.isPr {
                            Text("PR").font(.app(size: detailFont, weight: .bold)).foregroundStyle(AppColors.orangePrText)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(AppColors.orangePrBg)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(exerciseSubtitle(item)).font(.app(size: detailFont)).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    SavedNote(text: item.setupNote)
                    if rate == nil, let rating = item.jointStress {
                        Text(LanguageManager.t("history.jointStress", ["rating": LanguageManager.t(rating.labelKey)]))
                            .font(.app(size: detailFont)).foregroundStyle(AppColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                if let rate { jointRatingMenu(item, rate: rate) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: completed ? "checkmark" : partial ? "clock" : "minus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(completed ? AppColors.completedGreen : partial ? AppColors.unfinishedOrange : AppColors.muted)
                .frame(width: 20, height: 20)
                .accessibilityLabel(LanguageManager.t(completed ? "history.completed" : partial ? "history.unfinished" : past ? "history.notCompleted" : "history.notStarted"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        // The rating menu stays its own control; otherwise the row reads as one element.
        .accessibilityElement(children: rate == nil ? .combine : .contain)
        .accessibilityIdentifier("history-exercise-\(item.name)")
    }

    /// The rating line of a saved exercise: its current rating, or an offer to rate, opening None / Mild / High.
    private func jointRatingMenu(_ item: HistoryDayExerciseProgress, rate: @escaping (JointStress?) -> Void) -> some View {
        let label = item.jointStress.map { LanguageManager.t("history.jointStress", ["rating": LanguageManager.t($0.labelKey)]) }
            ?? LanguageManager.t("history.rateJointStress")
        return Menu {
            ForEach(JointStress.allCases, id: \.self) { option in
                Button { if option != item.jointStress { rate(option) } } label: {
                    if option == item.jointStress {
                        Label(LanguageManager.t(option.labelKey), systemImage: "checkmark")
                    } else {
                        Text(LanguageManager.t(option.labelKey))
                    }
                }
                .accessibilityIdentifier("history-joint-option-\(option.rawValue)")
            }
            if item.jointStress != nil {
                Divider()
                Button(role: .destructive) { rate(nil) } label: { Text(LanguageManager.t("history.clearJointStress")) }
                    .accessibilityIdentifier("history-joint-clear")
            }
        } label: {
            HStack(spacing: 4) {
                // Menu labels centre wrapped lines by default; keep them aligned with the row's other text.
                Text(label).font(.app(size: detailFont, weight: .medium)).foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .accessibilityLabel("\(item.name), \(label)")
        .accessibilityHint(LanguageManager.t("history.changeJointStress"))
        .accessibilityIdentifier("history-joint-\(item.name)")
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

    private func formattedWorkoutDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateStyle = .long
        let dateText = formatter.string(from: date)
        formatter.dateFormat = "EEEE"
        return dateText + " · " + formatter.string(from: date)
    }

    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}
