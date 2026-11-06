import SwiftUI

/// Which block questions a card asks (docs/training-blocks.md#weeks-2-to-the-last-accumulation-week).
enum BlockQuestions: String { case soreness, pumpAndWorkload = "pump_and_workload" }

/// A training block's questions for the muscles this exercise opens (soreness) or closes (pump and workload).
/// Every answer is optional and a second tap clears it, like the exercise ratings. Android `BlockFeedbackCard` matches.
struct BlockFeedbackCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let muscles: [String]
    let answers: [String: MuscleFeedback]
    let questions: BlockQuestions
    let onAnswer: (String, MuscleFeedback) -> Void
    @ScaledMetric(relativeTo: .footnote) private var hintSize = 12.0
    @ScaledMetric(relativeTo: .subheadline) private var muscleSize = 13.0

    var body: some View {
        let _ = themeManager.currentTheme
        if !muscles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(LanguageManager.t("block.feedback.hint"))
                    .font(.app(size: hintSize)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(muscles.enumerated()), id: \.element) { index, muscle in
                    if index > 0 { Rectangle().fill(AppColors.border.opacity(0.5)).frame(height: 0.8) }
                    let current = answers[muscle] ?? MuscleFeedback()
                    Text(LanguageManager.t("block.feedback.title", ["muscle": LanguageManager.t("anatomy.muscle.\(muscle)")]))
                        .font(.app(size: muscleSize, weight: .semibold)).foregroundStyle(AppColors.purple)
                        .accessibilityAddTraits(.isHeader)
                    switch questions {
                    case .soreness:
                        RatingSection(title: LanguageManager.t("block.feedback.soreness"), hint: LanguageManager.t("block.feedback.hint"),
                                      options: MuscleFeedback.sorenessCodes.map { ($0, LanguageManager.t("block.soreness.\($0)")) },
                                      selected: current.soreness, identifier: "block-soreness-\(muscle)") { code in
                            var updated = current; updated.soreness = code; onAnswer(muscle, updated)
                        }
                    case .pumpAndWorkload:
                        RatingSection(title: LanguageManager.t("block.feedback.pump"), hint: LanguageManager.t("block.feedback.hint"),
                                      options: MuscleFeedback.pumpCodes.map { ($0, LanguageManager.t("block.pump.\($0)")) },
                                      selected: current.pump, identifier: "block-pump-\(muscle)") { code in
                            var updated = current; updated.pump = code; onAnswer(muscle, updated)
                        }
                        RatingSection(title: LanguageManager.t("block.feedback.workload"), hint: LanguageManager.t("block.feedback.hint"),
                                      options: MuscleFeedback.workloadCodes.map { ($0, LanguageManager.t("block.workload.\($0)")) },
                                      selected: current.workload, identifier: "block-workload-\(muscle)") { code in
                            var updated = current; updated.workload = code; onAnswer(muscle, updated)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surfaceRaised.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("block-feedback-\(questions.rawValue)")
        }
    }
}

/// The optional readiness check before a workout's first set (docs/training-blocks.md#readiness-check): sleep,
/// energy and soreness, then, on two or more low answers, a lighter day the lifter may choose. Never applied on its own.
struct ReadinessCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let check: ReadinessCheck?
    let options: [String]
    let lighterTarget: String?
    let onAnswer: (ReadinessCheck) -> Void
    let onChoose: (String) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .footnote) private var bodySize = 13.0

    private func label(_ option: String) -> String {
        LanguageManager.t(option == "planned" ? "readiness.planned" : option == "fewer_sets" ? "readiness.fewer" : "readiness.moreRir")
    }

    var body: some View {
        let _ = themeManager.currentTheme
        let current = check ?? ReadinessCheck()
        let hint = LanguageManager.t("readiness.hint")
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t("readiness.title")).font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
            RatingSection(title: LanguageManager.t("readiness.sleep"), hint: hint,
                          options: Readiness.sleepCodes.map { ($0, LanguageManager.t("readiness.sleep.\($0)")) },
                          selected: current.sleep, identifier: "readiness-sleep") { var next = current; next.sleep = $0; onAnswer(next) }
            RatingSection(title: LanguageManager.t("readiness.energy"), hint: hint,
                          options: Readiness.energyCodes.map { ($0, LanguageManager.t("readiness.energy.\($0)")) },
                          selected: current.energy, identifier: "readiness-energy") { var next = current; next.energy = $0; onAnswer(next) }
            RatingSection(title: LanguageManager.t("readiness.soreness"), hint: hint,
                          options: Readiness.sorenessCodes.map { ($0, LanguageManager.t("readiness.soreness.\($0)")) },
                          selected: current.soreness, identifier: "readiness-soreness") { var next = current; next.soreness = $0; onAnswer(next) }
            if Readiness.offersLighterDay(check) {
                Text(LanguageManager.t("readiness.offer")).font(.app(size: bodySize, weight: .semibold)).foregroundStyle(AppColors.purple)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("readiness-offer")
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    Button { onChoose(option) } label: {
                        Text(label(option)).font(.app(size: titleSize, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? AppColors.background : AppColors.secondaryText)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(index == 0 ? AppColors.accent : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(index == 0 ? Color.clear : AppColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("readiness-\(option)")
                }
            } else if check?.choice == "fewer_sets" {
                Text(LanguageManager.t("readiness.applied.fewer")).font(.app(size: bodySize)).foregroundStyle(AppColors.purple)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("readiness-applied")
            } else if check?.choice == "more_rir", let lighterTarget {
                Text(LanguageManager.t("readiness.applied.moreRir", ["effort": lighterTarget])).font(.app(size: bodySize))
                    .foregroundStyle(AppColors.purple).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("readiness-applied")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceRaised.opacity(0.55)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readiness-card")
    }
}
