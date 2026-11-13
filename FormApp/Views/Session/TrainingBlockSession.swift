import SwiftUI

/// Which block questions a card asks (docs/training-blocks.md#weeks-2-to-the-last-accumulation-week).
enum BlockQuestions: String { case soreness, pumpAndWorkload = "pump_and_workload" }

/// A training block's questions for the muscles this exercise opens (soreness) or closes (pump and workload).
/// Every answer is optional and a second tap clears it, like the exercise ratings. Android `BlockFeedbackCard` matches.
///
/// It wears the block's own card (the Home card's purple calendar, title and 50% purple border) so the questions read
/// as the block's, with the choices in an even grid.
struct BlockFeedbackCard: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let muscles: [String]
    let answers: [String: MuscleFeedback]
    let questions: BlockQuestions
    let onAnswer: (String, MuscleFeedback) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .footnote) private var hintSize = 13.0
    @ScaledMetric(relativeTo: .subheadline) private var muscleSize = 13.0

    var body: some View {
        let _ = themeManager.currentTheme
        if !muscles.isEmpty {
            let hint = LanguageManager.t("block.feedback.hint")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.purple).accessibilityHidden(true)
                    Text(LanguageManager.t("block.card.title")).font(.app(size: titleSize, weight: .bold)).foregroundStyle(AppColors.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
                }
                Text(hint).font(.app(size: hintSize)).foregroundStyle(AppColors.muted).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                ForEach(Array(muscles.enumerated()), id: \.element) { index, muscle in
                    if index > 0 { Rectangle().fill(AppColors.border.opacity(0.6)).frame(height: 1).padding(.top, 14) }
                    let current = answers[muscle] ?? MuscleFeedback()
                    Text(LanguageManager.t("block.feedback.title", ["muscle": LanguageManager.t("anatomy.muscle.\(muscle)")]))
                        .font(.app(size: muscleSize, weight: .semibold)).foregroundStyle(AppColors.purple)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                        .accessibilityAddTraits(.isHeader)
                    switch questions {
                    case .soreness:
                        BlockQuestion(title: LanguageManager.t("block.feedback.soreness"), hint: hint,
                                      options: MuscleFeedback.sorenessCodes.map { ($0, LanguageManager.t("block.soreness.\($0)")) },
                                      selected: current.soreness, identifier: "block-soreness-\(muscle)") { code in
                            var updated = current; updated.soreness = code; onAnswer(muscle, updated)
                        }
                        .padding(.top, 4)
                    case .pumpAndWorkload:
                        BlockQuestion(title: LanguageManager.t("block.feedback.pump"), hint: hint,
                                      options: MuscleFeedback.pumpCodes.map { ($0, LanguageManager.t("block.pump.\($0)")) },
                                      selected: current.pump, identifier: "block-pump-\(muscle)") { code in
                            var updated = current; updated.pump = code; onAnswer(muscle, updated)
                        }
                        .padding(.top, 4)
                        BlockQuestion(title: LanguageManager.t("block.feedback.workload"), hint: hint,
                                      options: MuscleFeedback.workloadCodes.map { ($0, LanguageManager.t("block.workload.\($0)")) },
                                      selected: current.workload, identifier: "block-workload-\(muscle)") { code in
                            var updated = current; updated.workload = code; onAnswer(muscle, updated)
                        }
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.purple.opacity(0.5), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("block-feedback-\(questions.rawValue)")
        }
    }
}

/// One block question: its title, then its answers as equal cells, three across for three answers and two across
/// otherwise. Cells in a row share one height when a label wraps. A narrow screen or large text takes fewer columns
/// rather than splitting a word across lines.
private struct BlockQuestion: View {
    let title: String
    let hint: String
    let options: [(String, String)]
    let selected: String?
    let identifier: String
    let onSelect: (String?) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var titleSize = 14.0
    @ScaledMetric(relativeTo: .subheadline) private var optionSize = 13.0
    @State private var width: CGFloat = 0

    private var columns: Int {
        let preferred = options.count == 3 ? 3 : 2
        guard width > 0 else { return preferred }
        // Measured semibold, the selected weight, so choosing an answer never changes the grid.
        let font = UIFont.systemFont(ofSize: optionSize * TextWidthScale.factor, weight: .semibold)
        let longestWord = options.flatMap { $0.1.split(separator: " ") }
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // A cell's text width: its share of the row less 10pt padding and the 1pt border on each side.
        return stride(from: preferred, through: 2, by: -1).first { n in
            (width - 8 * CGFloat(n - 1)) / CGFloat(n) - 22 >= ceil(longestWord)
        } ?? 1
    }

    var body: some View {
        let columns = columns
        let rows = stride(from: 0, to: options.count, by: columns).map { Array(options[$0..<min($0 + columns, options.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ForEach(rows[index], id: \.0) { code, label in choice(code: code, label: label) }
                    ForEach(0..<(columns - rows[index].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func choice(code: String, label: String) -> some View {
        let isSelected = code == selected
        return Button { onSelect(isSelected ? nil : code) } label: {
            Text(label)
                .font(.app(size: optionSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.secondaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: .infinity)
                .background(isSelected ? AppColors.positiveBg : AppColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(label)")
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier)-\(code)")
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
