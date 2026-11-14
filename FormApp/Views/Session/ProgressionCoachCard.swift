import SwiftUI

public struct ProgressionCoachCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let recommendation: ExerciseProgressionRecommendation
    let weightUnit: WeightUnit
    let canApplyTarget: Bool
    let sessionSets: [ExerciseSetLog]?
    let onApplyTarget: () -> Void
    let onOpenInfo: () -> Void
    var onLockedClick: (() -> Void)? = nil
    var onDismissLocked: (() -> Void)? = nil

    @ObservedObject private var proManager = ProAccessManager.shared
    @State private var wasApplied: Bool = false
    @State private var detailsExpanded: Bool = false
    @State private var showInternalPaywall: Bool = false
    @ScaledMetric(relativeTo: .headline) private var emptyHeadlineSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var emptyBodySize = 13.0

    public init(
        recommendation: ExerciseProgressionRecommendation,
        weightUnit: WeightUnit = .kg,
        canApplyTarget: Bool = true,
        sessionSets: [ExerciseSetLog]? = nil,
        onApplyTarget: @escaping () -> Void,
        onOpenInfo: @escaping () -> Void,
        onLockedClick: (() -> Void)? = nil,
        onDismissLocked: (() -> Void)? = nil
    ) {
        self.recommendation = recommendation
        self.weightUnit = weightUnit
        self.canApplyTarget = canApplyTarget
        self.sessionSets = sessionSets
        self.onApplyTarget = onApplyTarget
        self.onOpenInfo = onOpenInfo
        self.onLockedClick = onLockedClick
        self.onDismissLocked = onDismissLocked
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        Group {
        if !proManager.isFeatureUnlocked(.autoProgression) {
            LockedSessionFeatureCard(
                title: LanguageManager.t("progression.coach.locked_title"),
                description: LanguageManager.t("progression.coach.locked_desc"),
                cardIdentifier: "progression-coach-card", dismissIdentifier: "dismiss-progression-card",
                onUnlock: { if let onLockedClick { onLockedClick() } else { showInternalPaywall = true } },
                onDismiss: onDismissLocked,
                icon: LockedProgressionTrend().stroke(AppColors.purple, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 24, height: 24)
            )
            .sheet(isPresented: $showInternalPaywall) {
                ProPaywallSheet(feature: .autoProgression, onDismiss: { showInternalPaywall = false })
            }
        } else if recommendation.setTargets.isEmpty && (recommendation.action == .firstSession || recommendation.action == .insufficientData) {
            emptyHistoryCard
        } else if recommendation.isPlateau || !recommendation.setTargets.isEmpty {
            ProgressionRecommendationCard(recommendation: recommendation, weightUnit: weightUnit,
                canApplyTarget: canApplyTarget, expanded: $detailsExpanded, wasApplied: $wasApplied,
                onApplyTarget: onApplyTarget, onOpenInfo: onOpenInfo)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ProgressionCoachHeader(onOpenInfo: onOpenInfo)

                // Target Headline & Action Button Row
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            let repStr = recommendation.suggestedRepsMin == recommendation.suggestedRepsMax
                                ? "\(recommendation.suggestedRepsMin)"
                                : "\(recommendation.suggestedRepsMin)–\(recommendation.suggestedRepsMax)"

                            let targetHeadline: String = {
                                if recommendation.setTargets.isEmpty {
                                    return LanguageManager.t(recommendation.isPlateau ? "progression.coach.review" : "progression.coach.no_target")
                                } else if hasDifferentTargets {
                                    return LanguageManager.t("progression.coach.by_set")
                                } else if (recommendation.suggestedWeightKg ?? 0) > 0 {
                                    return "\(LanguageManager.t("progression.coach.target")): \(recommendation.suggestedWeightDisplay) \(weightUnit.label) × \(repStr)"
                                } else {
                                    return "\(LanguageManager.t("progression.coach.target")): \(LanguageManager.t("progression.coach.reps", ["reps": repStr]))"
                                }
                            }()

                            Text(targetHeadline)
                                .font(.app(size: 14, weight: .bold))
                                .foregroundStyle(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let delta = recommendation.weightDeltaDisplay {
                            Text(delta)
                                .font(.app(size: 11, weight: .semibold))
                                .foregroundStyle(recommendation.action.color)
                                .padding(.leading, 19)
                        }
                    }

                    Spacer()

                    if !recommendation.setTargets.isEmpty {
                        Button(action: {
                            onApplyTarget()
                            wasApplied = true
                        }) {
                            HStack(spacing: 4) {
                                if wasApplied {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(AppColors.accent)
                                }
                                Text(wasApplied ? LanguageManager.t("progression.coach.applied") : LanguageManager.t("progression.coach.apply"))
                                    .font(.app(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(wasApplied ? AppColors.accent : AppColors.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 48)
                            .background(wasApplied ? AppColors.positiveBg : AppColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(wasApplied ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(!canApplyTarget)
                        .accessibilityIdentifier("apply-progression-target")
                    }
                }

                if hasDifferentTargets {
                    ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                        let load = (target.weightKg ?? 0) > 0 ? "\(weightUnit.formatLoadableDisplayWeight(target.weightKg!)) \(weightUnit.label) × " : ""
                        Text(LanguageManager.t("progression.coach.set_target", ["set": "\(index + 1)", "target": load.isEmpty ? LanguageManager.t("progression.coach.reps", ["reps": "\(target.reps)"]) : "\(load)\(target.reps)"]))
                            .font(.app(size: 12))
                            .foregroundStyle(AppColors.text)
                    }
                }
                if let summary = recommendation.lastSessionSummary {
                    Text(LanguageManager.t("progression.coach.last_logged", ["summary": summary, "unit": weightUnit.label]))
                        .font(.app(size: 11))
                        .foregroundStyle(AppColors.muted)
                }
                if !recommendation.setTargets.isEmpty && !canApplyTarget {
                    Text(LanguageManager.t("progression.coach.set_count_changed"))
                        .font(.app(size: 12))
                        .foregroundStyle(AppColors.secondaryText)
                }

                // Rationale text
                let rationaleText = LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs)
                Text(rationaleText)
                    .font(.app(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(14)
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture {
                onOpenInfo()
            }
        }
        }.onChange(of: recommendation) { _, _ in detailsExpanded = false; wasApplied = false }
    }

    private var emptyHistoryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProgressionCoachHeader(onOpenInfo: onOpenInfo).padding(.bottom, 8)

            Text(emptyHistoryCopy.headline)
                .font(.app(size: emptyHeadlineSize, weight: .bold))
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(emptyHistoryCopy.description)
                .font(.app(size: emptyBodySize))
                .lineSpacing(2)
                .foregroundStyle(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            // Say why the latest log gives no target, not only how to log this session.
            if recommendation.action == .insufficientData {
                Text(LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs))
                    .font(.app(size: emptyBodySize - 1))
                    .lineSpacing(2)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("progression-no-target-reason")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenInfo)
        .accessibilityIdentifier("progression-coach-card")
    }

    private var loggingProgress: ProgressionLoggingProgress? {
        guard let sessionSets else { return nil }
        let progress = ProgressionLoggingProgress.from(sets: sessionSets)
        return progress.totalSets > 0 ? progress : nil
    }

    private var emptyHistoryCopy: (headline: String, description: String) {
        guard let progress = loggingProgress else {
            return (LanguageManager.t("progression.coach.no_target"),
                    LanguageManager.t("progression.coach.first_session_hint"))
        }
        let args = ["recorded": "\(progress.recordedSets)", "sets": "\(progress.totalSets)", "remaining": "\(progress.remainingSets)"]
        let headlineKey = progress.totalSets == 1 ? "progression.coach.recorded_set" : "progression.coach.recorded_sets"
        let descriptionKey = progress.remainingSets == 0 ? "progression.coach.working_sets_recorded_hint"
            : progress.remainingSets == 1 ? "progression.coach.remaining_set_hint" : "progression.coach.remaining_sets_hint"
        return (LanguageManager.t(headlineKey, args), LanguageManager.t(descriptionKey, args))
    }

    private var hasDifferentTargets: Bool {
        guard let first = recommendation.setTargets.first else { return false }
        return recommendation.setTargets.contains { $0 != first }
    }
}

private struct ProgressionCoachHeader: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let onOpenInfo: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0

    private var title: some View {
        Text(LanguageManager.t("progression.coach.next_target"))
            .font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
    }

    var body: some View {
        let _ = themeManager.currentTheme
        HStack(alignment: .center, spacing: 4) {
            ProgressionHeaderBolt().fill(AppColors.purple)
                .frame(width: 16, height: 16).frame(width: 20, height: 24).accessibilityHidden(true)
            title.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpenInfo) {
                ZStack {
                    Circle().stroke(AppColors.muted, lineWidth: 1.5).frame(width: 12.5, height: 12.5)
                    Circle().fill(AppColors.muted).frame(width: 1.8, height: 1.8).offset(y: -3.4)
                    Capsule().fill(AppColors.muted).frame(width: 1.3, height: 5).offset(y: 1.35)
                    Capsule().fill(AppColors.muted).frame(width: 3.6, height: 1.1).offset(y: 3.6)
                }
                .frame(width: 18, height: 18).accessibilityHidden(true)
                .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(LanguageManager.t("progression.info.title"))
            .accessibilityIdentifier("progression-info-button").frame(width: 18, height: 24)
        }.frame(minHeight: 24)
    }
}

struct ProgressionRecommendationCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let recommendation: ExerciseProgressionRecommendation
    let weightUnit: WeightUnit
    let canApplyTarget: Bool
    @Binding var expanded: Bool
    @Binding var wasApplied: Bool
    let onApplyTarget: () -> Void
    let onOpenInfo: () -> Void
    @ScaledMetric(relativeTo: .headline) private var headlineSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var bodySize = 13.0
    @ScaledMetric(relativeTo: .caption) private var metadataSize = 11.0
    private var review: Bool { recommendation.isPlateau }

    var body: some View {
        let _ = themeManager.currentTheme
        VStack(alignment: .leading, spacing: 0) {
            ProgressionCoachHeader(onOpenInfo: onOpenInfo).padding(.bottom, 8)
            Text(headlineTitle)
                .font(.app(size: headlineSize, weight: .bold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            Text(descriptionText)
                .font(.app(size: bodySize)).lineSpacing(2).foregroundStyle(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let variationId = recommendation.suggestedVariationId {
                let name = ContentLocalizer.shared.exerciseName(exerciseId: variationId, fallback: recommendation.suggestedVariationName ?? variationId)
                Text(LanguageManager.t(review ? "progression.coach.variation_idea" : "progression.coach.variation_harder", ["exercise": name]))
                    .font(.app(size: bodySize)).lineSpacing(2).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    .accessibilityIdentifier("progression-variation")
            }
            // Drops, rest-pause and partials are context only; targets come from main parts.
            ForEach(recommendation.lastTechniqueSets, id: \.setNumber) { set in
                let detail = "\(LanguageManager.t("table.setNumber", ["count": set.setNumber])): \(IntensitySets.notation(set, unit: weightUnit))"
                Text(LanguageManager.t("intensity.lastTime", ["detail": detail]))
                    .font(.app(size: bodySize)).lineSpacing(2).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    .accessibilityIdentifier("progression-last-technique-\(set.setNumber)")
            }
            // A review applies nothing by itself; its lighter week is an optional, explicit choice.
            if review && !recommendation.setTargets.isEmpty {
                Text(LanguageManager.t("progression.coach.lighter_week_hint"))
                    .font(.app(size: bodySize)).lineSpacing(2).foregroundStyle(AppColors.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            if !recommendation.setTargets.isEmpty {
                if expanded {
                    targetDetails.padding(.top, 10)
                }
                if !canApplyTarget {
                    Text(LanguageManager.t("progression.coach.set_count_changed"))
                        .font(.app(size: bodySize)).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        toggleButton
                        applyButton
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 0) {
                        toggleButton
                        applyButton
                    }
                }.padding(.top, 4)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
        .accessibilityIdentifier("progression-coach-card")
    }

    private var headlineTitle: String {
        if !review && WorkoutSessionUtils.isAssisted(exerciseId: recommendation.exerciseId, name: recommendation.exerciseName) { return LanguageManager.t("progression.coach.assistance_title") }
        if review { return LanguageManager.t("progression.coach.review_compact", recommendation.rationaleArgs) }
        switch recommendation.action {
        case .increaseLoad:
            return LanguageManager.t("progression.action.increase_load")
        case .holdLoad:
            let repsAdded = zip(recommendation.setTargets, recommendation.lastSessionSets).contains { target, last in
                target.reps > last.reps
            }
            return repsAdded
                ? LanguageManager.t("progression.coach.add_reps_title", recommendation.rationaleArgs)
                : LanguageManager.t("progression.action.hold_load")
        default:
            return LanguageManager.t("progression.coach.add_reps_title", recommendation.rationaleArgs)
        }
    }

    /// Rationales that explain a padded baseline: where the sets the lifter did not log last time came from.
    private static let paddedRationales: Set<String> = ["progression.rationale.plan_sets_changed",
        "progression.rationale.ended_with_drop", "progression.rationale.ended_with_rest_pause"]

    /// Whether the description is the rationale itself rather than the add-reps hint: a weight decision, or a
    /// padded baseline, which the hint alone would leave unexplained.
    static func showsRationale(_ recommendation: ExerciseProgressionRecommendation) -> Bool {
        paddedRationales.contains(recommendation.rationaleKey) || recommendation.action == .increaseLoad || recommendation.action == .holdLoad
    }

    private var descriptionText: String {
        if review { return LanguageManager.t("progression.coach.review_observation", recommendation.rationaleArgs) }
        if wasApplied { return LanguageManager.t("progression.coach.applied_hint") }
        if WorkoutSessionUtils.isAssisted(exerciseId: recommendation.exerciseId, name: recommendation.exerciseName) { return LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs) }
        if Self.showsRationale(recommendation) {
            return LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs)
        }
        if expanded { return LanguageManager.t("progression.coach.add_reps_expanded_hint") }
        return LanguageManager.t("progression.coach.add_reps_hint", recommendation.rationaleArgs)
    }

    private var toggleButton: some View {
        CompactCoachButton(label: LanguageManager.t(review ? (expanded ? "progression.coach.hide_lighter_week" : "progression.coach.show_lighter_week")
                : (expanded ? "progression.coach.hide_targets" : "progression.coach.show_targets")),
            expanded: expanded) { expanded.toggle() }
            .accessibilityValue(LanguageManager.t(expanded ? "progression.coach.expanded" : "progression.coach.collapsed"))
            .accessibilityIdentifier("toggle-progression-details")
    }

    private var applyButton: some View {
        CompactCoachButton(label: LanguageManager.t(wasApplied ? "progression.coach.applied" : review ? "progression.coach.apply_lighter_week" : "progression.coach.apply"),
                           primary: !review) {
            onApplyTarget()
            wasApplied = true
            expanded = false
        }.disabled(!canApplyTarget).opacity(canApplyTarget ? 1 : 0.5)
            .accessibilityIdentifier("apply-progression-target")
    }

    private var targetDetails: some View {
        VStack(spacing: 0) {
            if recommendation.action == .increaseLoad || recommendation.action == .deload {
                loadIncreaseDetails
            } else {
                ProgressionTableRow {
                    Text(LanguageManager.t("progression.coach.set_column"))
                    Text(LanguageManager.t(WorkoutSessionUtils.isAssisted(exerciseId: recommendation.exerciseId, name: recommendation.exerciseName) ? "table.assistance" : "progression.coach.weight_column"))
                    Text(LanguageManager.t("progression.coach.last_reps_column")).multilineTextAlignment(.center)
                    Color.clear.frame(height: 0)
                    Text(LanguageManager.t("progression.coach.target_reps_column")).multilineTextAlignment(.center)
                }.font(.app(size: metadataSize)).foregroundStyle(AppColors.muted).padding(.vertical, 8)
                ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                    Rectangle().fill(AppColors.border).frame(height: 1)
                    ProgressionTableRow {
                        Text("\(index + 1)").foregroundStyle(AppColors.secondaryText)
                        Text(weight(target)).foregroundStyle(AppColors.text)
                        Text(recommendation.lastSessionSets.indices.contains(index) ? "\(recommendation.lastSessionSets[index].reps)" : "—")
                            .foregroundStyle(AppColors.muted).accessibilityIdentifier("progression-last-reps-\(index + 1)")
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(AppColors.muted).accessibilityHidden(true)
                        Text("\(target.reps)").fontWeight(.bold).foregroundStyle(AppColors.text)
                            .accessibilityIdentifier("progression-target-reps-\(index + 1)")
                    }.font(.app(size: bodySize)).monospacedDigit().padding(.vertical, 8)
                        .accessibilityIdentifier("progression-target-row-\(index + 1)")
                }
            }
        }.padding(.horizontal, 10)
            .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .accessibilityIdentifier("progression-target-details")
    }

    private var loadIncreaseDetails: some View {
        Group {
            ProgressionTableRow(fractions: [0.10, 0.42, 0.06, 0.42], spacing: 4) {
                Text(LanguageManager.t("progression.coach.set_column"))
                Text(LanguageManager.t("progression.coach.last_set_column"))
                Color.clear.frame(height: 0)
                Text(LanguageManager.t("progression.coach.target_set_column"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.font(.app(size: metadataSize)).foregroundStyle(AppColors.muted)
                .lineLimit(1).minimumScaleFactor(0.1).padding(.vertical, 8)
            ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                Rectangle().fill(AppColors.border).frame(height: 1)
                ProgressionTableRow(fractions: [0.10, 0.42, 0.06, 0.42], spacing: 4) {
                    Text("\(index + 1)").foregroundStyle(AppColors.secondaryText)
                    if recommendation.lastSessionSets.indices.contains(index) {
                        setDetails(recommendation.lastSessionSets[index], index: index, isTarget: false)
                    } else {
                        Text("—").foregroundStyle(AppColors.muted)
                    }
                    Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(AppColors.muted).accessibilityHidden(true)
                    setDetails(target, index: index, isTarget: true)
                }.font(.app(size: bodySize)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.1).padding(.vertical, 8)
                    .accessibilityIdentifier("progression-target-row-\(index + 1)")
            }
        }
    }

    private func setDetails(_ set: ProgressionSetTarget, index: Int, isTarget: Bool) -> some View {
        Text("\(weight(set, compact: true)) × \(set.reps)")
            .fontWeight(isTarget ? .bold : .regular)
            .foregroundStyle(isTarget ? AppColors.text : AppColors.muted)
            .lineLimit(1).minimumScaleFactor(0.1).allowsTightening(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(weight(set)), \(LanguageManager.t("progression.coach.reps", ["reps": "\(set.reps)"]))")
            .accessibilityIdentifier("progression-\(isTarget ? "target" : "last")-set-\(index + 1)")
    }

    private func weight(_ target: ProgressionSetTarget, compact: Bool = false) -> String {
        guard let load = target.weightKg else { return "—" }
        return load == 0 && !WorkoutSessionUtils.isAssisted(exerciseId: recommendation.exerciseId, name: recommendation.exerciseName) ? LanguageManager.t("progression.coach.bodyweight") : "\(weightUnit.formatLoadableDisplayWeight(load))\(compact ? "" : " ")\(weightUnit.label)"
    }
}

// Shared column widths keep headers and values aligned while allowing large text to wrap.
private struct ProgressionTableRow: Layout {
    var fractions: [CGFloat] = [0.15, 0.32, 0.22, 0.06, 0.25]
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let columnSpace = max(0, width - spacing * CGFloat(max(0, subviews.count - 1)))
        let height = subviews.enumerated().map { index, view in
            view.sizeThatFits(ProposedViewSize(width: columnSpace * fractions[index], height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        let columnSpace = max(0, bounds.width - spacing * CGFloat(max(0, subviews.count - 1)))
        for (index, view) in subviews.enumerated() {
            let width = columnSpace * fractions[index]
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let offset = index < 2 ? 0 : (width - size.width) / 2
            view.place(at: CGPoint(x: x + offset, y: bounds.midY - size.height / 2),
                proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}

/// The mid-workout adjustment under the first working set (docs/adaptive-training.md#b2-mid-workout-adjustment):
/// what the set's reps in reserve suggest for the remaining sets. Use fills their loads like Apply; Keep hides it.
public struct LoadAdjustmentCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let adjustment: LoadAdjustment
    let scale: SetEffort.Scale
    let weightUnit: WeightUnit
    let onUse: () -> Void
    let onKeep: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .footnote) private var bodySize = 13.0

    public init(adjustment: LoadAdjustment, scale: SetEffort.Scale, weightUnit: WeightUnit,
                onUse: @escaping () -> Void, onKeep: @escaping () -> Void) {
        self.adjustment = adjustment
        self.scale = scale
        self.weightUnit = weightUnit
        self.onUse = onUse
        self.onKeep = onKeep
    }

    /// A tag, a load and a load × reps each stay on one line when the sentence around them wraps.
    private func unbroken(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "\u{00A0}") }

    private func load(_ kg: Double) -> String {
        unbroken("\(weightUnit.formatLoadableDisplayWeight(kg)) \(weightUnit.label)")
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        let targetLoad = load(adjustment.target.weightKg ?? adjustment.currentKg)
        let currentLoad = load(adjustment.currentKg)
        let use = CompactCoachButton(label: LanguageManager.t("progression.adjust.use", ["load": targetLoad]), primary: true, action: onUse)
            .accessibilityIdentifier("load-adjustment-use")
        let keep = CompactCoachButton(label: LanguageManager.t("progression.adjust.keep", ["load": currentLoad]), action: onKeep)
            .accessibilityIdentifier("load-adjustment-keep")
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                ProgressionHeaderBolt().fill(AppColors.purple)
                    .frame(width: 16, height: 16).frame(width: 20, height: 24).accessibilityHidden(true)
                Text(LanguageManager.t(adjustment.direction.titleKey,
                                       ["set": adjustment.setNumber, "effort": unbroken(SetEffort.tag(adjustment.rir, scale: scale))]))
                    .font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(LanguageManager.t(adjustment.direction.reasonKey))
                .font(.app(size: bodySize)).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(LanguageManager.t("progression.adjust.remaining", ["target": unbroken("\(targetLoad) × \(adjustment.target.reps)")]))
                .font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                .accessibilityIdentifier("load-adjustment-target")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { use; keep }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 0) { use; keep }
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
        .padding(.top, 6).padding(.bottom, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("load-adjustment")
    }
}

/// A strength block lift (docs/training-blocks.md#strength-blocks): the top set to work up to, then its back-off sets
/// from the logged top set, or the test's three singles. Use fills loads only, like Apply. Android `StrengthLiftCard` matches.
public struct StrengthLiftCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let plan: TrainingBlockRules.StrengthWeek
    let exercise: Exercise
    let sets: [ExerciseSetLog]
    let estimateKg: Double?
    let weightUnit: WeightUnit
    let steps: ProgressionLoadSteps
    let scale: SetEffort.Scale
    let onApply: ([Int: ProgressionSetTarget]) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .footnote) private var bodySize = 13.0

    private func load(_ kg: Double) -> String { "\(weightUnit.formatLoadableDisplayWeight(kg))\u{00A0}\(weightUnit.label)" }

    /// The card's title, detail and Use action for the current rows; nil when there is nothing to show.
    private var content: (title: String, detail: String?, action: (String, [Int: ProgressionSetTarget])?)? {
        let working = sets.indices.filter { !sets[$0].isWarmup }
        guard let top = working.first else { return nil }
        let open = working.filter { !sets[$0].isCompleted }
        if plan.test {
            let attempts = estimateKg.flatMap { ProgressionEngine.attemptsKg(exercise: exercise, e1rmKg: $0, unit: weightUnit, steps: steps) }
            var targets: [Int: ProgressionSetTarget] = [:]
            for (index, kg) in zip(working.prefix(attempts?.count ?? 0), attempts ?? []) where open.contains(index) {
                targets[index] = ProgressionSetTarget(weightKg: kg, reps: 1)
            }
            return (LanguageManager.t("block.strength.test"), attempts?.map(load).joined(separator: " · "),
                    attempts == nil ? nil : (LanguageManager.t("block.strength.useAttempts"), targets))
        }
        if !sets[top].isCompleted {
            let suggestion = estimateKg.flatMap {
                ProgressionEngine.gridLoadKg(exercise: exercise, targetKg: TrainingBlockRules.topSetTarget(e1rm: $0, reps: plan.topReps, rir: plan.topRir),
                                             unit: weightUnit, steps: steps)
            }
            let title = LanguageManager.t("block.strength.top", ["reps": plan.topReps,
                "effort": SetEffort.tag(plan.topRir, scale: scale).replacingOccurrences(of: " ", with: "\u{00A0}")])
            let detail = suggestion.map { LanguageManager.t("block.strength.topLoad", ["load": load($0)]) } ?? LanguageManager.t("block.strength.workUp")
            return (title, detail, suggestion.map { (LanguageManager.t("progression.adjust.use", ["load": load($0)]),
                                                     [top: ProgressionSetTarget(weightKg: $0, reps: plan.topReps)]) })
        }
        guard let topKg = sets[top].weightKg, topKg > 0, !open.isEmpty,
              let backoff = ProgressionEngine.gridLoadKg(exercise: exercise, targetKg: topKg * plan.backoffPercent / 100, unit: weightUnit, steps: steps)
        else { return nil }
        let title = LanguageManager.t("block.strength.backoff", ["sets": plan.backoffSets, "reps": plan.backoffReps, "load": load(backoff)])
            .replacingOccurrences(of: " × ", with: "\u{00A0}×\u{00A0}")
        let detail = LanguageManager.t("block.strength.backoffWhy", ["percent": BlockFormat.percent(plan.backoffPercent)])
            .replacingOccurrences(of: " %", with: "\u{00A0}%")
        let needsLoads = open.contains { abs((sets[$0].weightKg ?? -1) - backoff) > 1e-6 }
        return (title, detail, needsLoads ? (LanguageManager.t("progression.adjust.use", ["load": load(backoff)]),
                                             Dictionary(uniqueKeysWithValues: open.map { ($0, ProgressionSetTarget(weightKg: backoff, reps: plan.backoffReps)) })) : nil)
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        if let content {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    ProgressionHeaderBolt().fill(AppColors.purple)
                        .frame(width: 16, height: 16).frame(width: 20, height: 24).accessibilityHidden(true)
                    Text(content.title).font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("strength-lift-title")
                }
                if let detail = content.detail {
                    Text(detail).font(.app(size: bodySize)).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("strength-lift-detail")
                }
                if let (label, targets) = content.action {
                    CompactCoachButton(label: label, primary: true) { onApply(targets) }
                        .accessibilityIdentifier("strength-lift-use")
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, content.action == nil ? 12 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("strength-lift-card")
        }
    }
}

private struct CompactCoachButton: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let label: String
    var primary = false
    var expanded: Bool? = nil
    let action: () -> Void
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12.0

    var body: some View {
        let _ = themeManager.currentTheme
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.app(size: fontSize, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let expanded {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 14, height: 14).accessibilityHidden(true)
                }
            }
            .foregroundStyle(primary ? AppColors.background : AppColors.secondaryText)
            .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 32)
            .background(primary ? AppColors.accent : AppColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(primary ? Color.clear : AppColors.border, lineWidth: 1))
            .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

// Use the same 20-unit bolt geometry on both platforms.
private struct ProgressionHeaderBolt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12.5, y: 0))
        path.addLine(to: CGPoint(x: 3.5, y: 11))
        path.addLine(to: CGPoint(x: 9, y: 11))
        path.addLine(to: CGPoint(x: 7.5, y: 20))
        path.addLine(to: CGPoint(x: 16.5, y: 8))
        path.addLine(to: CGPoint(x: 11, y: 8))
        path.closeSubpath()
        return path.applying(CGAffineTransform(scaleX: rect.width / 20, y: rect.height / 20))
    }
}

/// Shared locked presentation: the card opens Premium; the close control only dismisses.
struct LockedSessionFeatureCard<Icon: View>: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let title: String
    let description: String
    let cardIdentifier: String
    let dismissIdentifier: String
    let onUnlock: () -> Void
    let onDismiss: (() -> Void)?
    let icon: Icon
    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var bodySize = 13.0

    private var heading: some View {
        Text(title)
            .font(.app(size: titleSize, weight: .bold))
            .foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        let _ = themeManager.currentTheme
        ZStack(alignment: .topTrailing) {
            Button(action: onUnlock) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        icon.frame(width: 24, height: 24).accessibilityHidden(true)
                        heading.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.purple)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                    }
                    .padding(.trailing, onDismiss != nil ? 34 : 0)
                    Text(description)
                        .font(.app(size: bodySize))
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(LanguageManager.t("pro.premium_required"))
            .accessibilityIdentifier(cardIdentifier)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.muted)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2)
                .accessibilityLabel(LanguageManager.t("common.close"))
                .accessibilityIdentifier(dismissIdentifier)
            }
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppColors.border, lineWidth: 1))
    }
}

private struct LockedProgressionTrend: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 24, y: rect.minY + y * rect.height / 24)
        }
        path.move(to: point(3, 17)); path.addLine(to: point(9, 11))
        path.addLine(to: point(13, 15)); path.addLine(to: point(21, 7))
        path.move(to: point(15, 7)); path.addLine(to: point(21, 7)); path.addLine(to: point(21, 13))
        return path
    }
}

/// The exercise's ratings: Smart Progression's effort rating, asked once every working set is recorded, and the
/// opt-in joint-stress rating, offered from the first completed working set, share one compact card under the last
/// set, so there is never a second prompt.
/// Both are the user's own reports; tapping the selected value again clears it. Their explanations are spoken
/// hints and live in Settings, so the card stays one line per rating.
struct ExerciseRatingsCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let effort: ProgressionEffort?
    let onEffort: ((ProgressionEffort?) -> Void)?
    let jointStress: JointStress?
    let onJointStress: ((JointStress?) -> Void)?

    var body: some View {
        let _ = themeManager.currentTheme
        if onEffort != nil || onJointStress != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let onEffort {
                    RatingSection(title: LanguageManager.t("progression.effort.title"), hint: LanguageManager.t("progression.effort.hint"),
                                  options: ProgressionEffort.allCases.map { ($0.rawValue, LanguageManager.t($0.labelKey)) },
                                  selected: effort?.rawValue, identifier: "progression-effort") { onEffort($0.flatMap(ProgressionEffort.init(rawValue:))) }
                }
                if onEffort != nil && onJointStress != nil {
                    Rectangle().fill(AppColors.border.opacity(0.5)).frame(height: 0.8)
                }
                if let onJointStress {
                    RatingSection(title: LanguageManager.t("joint.title"), hint: LanguageManager.t("joint.hint"),
                                  options: JointStress.allCases.map { ($0.rawValue, LanguageManager.t($0.labelKey)) },
                                  selected: jointStress?.rawValue, identifier: "joint-stress") { onJointStress($0.flatMap(JointStress.init(rawValue:))) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exercise-ratings")
        }
    }
}

struct RatingSection: View {
    let title: String
    let hint: String
    let options: [(String, String)]
    let selected: String?
    let identifier: String
    let onSelect: (String?) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .subheadline) private var optionSize = 13.0

    var body: some View {
        let label = Text(title)
            .font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
            .fixedSize(horizontal: false, vertical: true)
        // The label shares the line with its choices while they fit, then the choices wrap below it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label.fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                // Whole words only: inline is chosen just when every choice fits at its natural width.
                HStack(spacing: 8) { buttons }.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                label
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }.fixedSize()
                    VStack(alignment: .leading, spacing: 0) { buttons }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(options, id: \.0) { code, label in
            let isSelected = code == selected
            Button { onSelect(isSelected ? nil : code) } label: {
                Text(label)
                    .font(.app(size: optionSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isSelected ? AppColors.positiveBg : AppColors.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1))
                    .frame(minWidth: 48, minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(label)")
            .accessibilityHint(hint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("\(identifier)-\(code)")
        }
    }
}
