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
