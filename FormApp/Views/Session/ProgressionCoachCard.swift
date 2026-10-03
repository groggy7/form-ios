import SwiftUI

public struct ProgressionCoachCard: View {
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
        Group {
        if !proManager.isFeatureUnlocked(.autoProgression) {
            HStack(spacing: 6) {
                Button(action: {
                    if let onLockedClick = onLockedClick {
                        onLockedClick()
                    } else {
                        showInternalPaywall = true
                    }
                }) {
                    HStack(spacing: 10) {
                        // Left Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.purpleBg)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppColors.purple.opacity(0.4), lineWidth: 1)
                                )

                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.purple)
                        }

                        // Text details
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                ProBadge()
                                Text(LanguageManager.t("pro.auto_progression.title"))
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }

                            Text(LanguageManager.t("pro.auto_progression.teaser"))
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }

                        Spacer(minLength: 2)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.purple)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onDismissLocked = onDismissLocked {
                    Button(action: onDismissLocked) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dismiss-progression-card")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, onDismissLocked != nil ? 8 : 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppColors.purple.opacity(0.35), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("progression-coach-card")
            .sheet(isPresented: $showInternalPaywall) {
                ProPaywallSheet(feature: .autoProgression, onDismiss: { showInternalPaywall = false })
            }
        } else if recommendation.setTargets.isEmpty && (recommendation.action == .firstSession || recommendation.action == .insufficientData) {
            emptyHistoryCard
        } else if recommendation.isPlateau || (recommendation.action == .addReps && !recommendation.setTargets.isEmpty) {
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
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let delta = recommendation.weightDeltaDisplay {
                            Text(delta)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(recommendation.action.color)
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
                                        .foregroundColor(AppColors.accent)
                                }
                                Text(wasApplied ? LanguageManager.t("progression.coach.applied") : LanguageManager.t("progression.coach.apply"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(wasApplied ? AppColors.accent : AppColors.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 48)
                            .background(wasApplied ? AppColors.positiveBg : AppColors.surface)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(wasApplied ? AppColors.accent.opacity(0.5) : AppColors.border, lineWidth: 1))
                            .cornerRadius(8)
                        }
                        .disabled(!canApplyTarget)
                        .accessibilityIdentifier("apply-progression-target")
                    }
                }

                if hasDifferentTargets {
                    ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                        let load = (target.weightKg ?? 0) > 0 ? "\(weightUnit.formatWeight(target.weightKg!)) \(weightUnit.label) × " : ""
                        Text(LanguageManager.t("progression.coach.set_target", ["set": "\(index + 1)", "target": load.isEmpty ? LanguageManager.t("progression.coach.reps", ["reps": "\(target.reps)"]) : "\(load)\(target.reps)"]))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.text)
                    }
                }
                if let summary = recommendation.lastSessionSummary {
                    Text(LanguageManager.t("progression.coach.last_logged", ["summary": summary, "unit": weightUnit.label]))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                }
                if !recommendation.setTargets.isEmpty && !canApplyTarget {
                    Text(LanguageManager.t("progression.coach.set_count_changed"))
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.secondaryText)
                }

                // Rationale text
                let rationaleText = LanguageManager.t(recommendation.rationaleKey, recommendation.rationaleArgs)
                Text(rationaleText)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(14)
            .background(AppColors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(recommendation.action.color.opacity(0.35), lineWidth: 1))
            .cornerRadius(16)
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
                .font(.system(size: emptyHeadlineSize, weight: .bold))
                .foregroundColor(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(emptyHistoryCopy.description)
                .font(.system(size: emptyBodySize))
                .lineSpacing(2)
                .foregroundColor(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.border, lineWidth: 1))
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
    let onOpenInfo: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0

    private var title: some View {
        Text(LanguageManager.t("progression.coach.next_target"))
            .font(.system(size: titleSize, weight: .bold)).foregroundColor(AppColors.text)
            .fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ProgressionHeaderBolt().fill(AppColors.purple)
                .frame(width: 16, height: 16).frame(width: 20, height: 24).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { title; ProBadge() }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { title; ProBadge() }
            }.frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 0) {
            ProgressionCoachHeader(onOpenInfo: onOpenInfo).padding(.bottom, 8)
            Text(LanguageManager.t(review ? "progression.coach.review_compact" : "progression.coach.add_reps_title"))
                .font(.system(size: headlineSize, weight: .bold)).foregroundColor(AppColors.text)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
            Text(LanguageManager.t(review ? "progression.coach.review_observation"
                : wasApplied ? "progression.coach.applied_hint" : "progression.coach.add_reps_hint", recommendation.rationaleArgs))
                .font(.system(size: bodySize)).lineSpacing(2).foregroundColor(AppColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            if review, let summary = lastSummary {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("progression.coach.last_logged_label"))
                        .font(.system(size: metadataSize, weight: .semibold)).foregroundColor(AppColors.muted)
                    Text(summary).font(.system(size: bodySize)).foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 10)
            }
            if expanded {
                if review {
                    Text(LanguageManager.t("progression.coach.review_options_hint"))
                        .font(.system(size: bodySize)).lineSpacing(2).foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                        .accessibilityIdentifier("progression-review-options")
                } else {
                    targetDetails.padding(.top, 10)
                    if !canApplyTarget {
                        Text(LanguageManager.t("progression.coach.set_count_changed"))
                            .font(.system(size: bodySize)).foregroundColor(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                    Button {
                        onApplyTarget()
                        wasApplied = true
                        expanded = false
                    } label: {
                        Text(LanguageManager.t(wasApplied ? "progression.coach.applied" : "progression.coach.apply"))
                            .font(.system(size: bodySize, weight: .bold))
                            .frame(maxWidth: .infinity).padding(12).frame(minHeight: 48)
                            .foregroundColor(wasApplied ? AppColors.accent : AppColors.background)
                            .background(wasApplied ? AppColors.positiveBg : AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }.buttonStyle(.plain).disabled(!canApplyTarget).opacity(canApplyTarget ? 1 : 0.5)
                        .accessibilityIdentifier("apply-progression-target").padding(.top, 10)
                }
            }
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Text(LanguageManager.t(toggleKey)).font(.system(size: bodySize, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, height: 18).accessibilityHidden(true)
                }
                .foregroundColor(AppColors.purple).padding(12).frame(minHeight: 48)
                .background(AppColors.purpleBg).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
            }.buttonStyle(.plain).padding(.top, 10)
                .accessibilityValue(LanguageManager.t(expanded ? "progression.coach.expanded" : "progression.coach.collapsed"))
                .accessibilityIdentifier("toggle-progression-details")
        }
        .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityIdentifier("progression-coach-card")
    }

    private var targetDetails: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(LanguageManager.t("progression.coach.set_column")).frame(width: 26, alignment: .leading)
                Text(LanguageManager.t("progression.coach.weight_column")).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(LanguageManager.t("progression.coach.reps_column"))
                    Text(LanguageManager.t("progression.coach.last_to_target"))
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: metadataSize)).foregroundColor(AppColors.muted)
            ForEach(Array(recommendation.setTargets.enumerated()), id: \.offset) { index, target in
                HStack(spacing: 8) {
                    Text("\(index + 1)").foregroundColor(AppColors.secondaryText).frame(width: 26, alignment: .leading)
                    Text(weight(target)).foregroundColor(AppColors.text).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    repComparison(index: index, target: target).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }.font(.system(size: bodySize)).accessibilityIdentifier("progression-target-row-\(index + 1)")
            }
        }.accessibilityIdentifier("progression-target-details")
    }

    private func repComparison(index: Int, target: ProgressionSetTarget) -> Text {
        let previous = recommendation.lastSessionSets.indices.contains(index) ? recommendation.lastSessionSets[index] : nil
        return Text(previous.map { "\($0.reps) → " } ?? "").foregroundColor(AppColors.muted)
            + Text("\(target.reps)").fontWeight(.bold).foregroundColor(AppColors.text)
    }

    private func weight(_ target: ProgressionSetTarget) -> String {
        guard let load = target.weightKg else { return "—" }
        return load == 0 ? LanguageManager.t("progression.coach.bodyweight") : "\(weightUnit.formatWeight(load)) \(weightUnit.label)"
    }

    private var lastSummary: String? {
        let last = recommendation.lastSessionSets
        guard !last.isEmpty else { return recommendation.lastSessionSummary }
        if last.allSatisfy({ $0.weightKg == 0 }) {
            return "\(LanguageManager.t("progression.coach.bodyweight")) · "
                + LanguageManager.t("progression.coach.reps", ["reps": last.map { "\($0.reps)" }.joined(separator: " / ")])
        }
        return last.map { "\(weight($0)) × \($0.reps)" }.joined(separator: " · ")
    }

    private var toggleKey: String {
        if review { return expanded ? "progression.coach.hide_options" : "progression.coach.review_options" }
        return expanded ? "progression.coach.hide_targets" : "progression.coach.show_targets"
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
