import SwiftUI

extension JointStress {
    /// Marker colors: muted neutral, amber and danger. A user-reported High is their own warning.
    var markerColor: Color {
        switch self {
        case .noStress: return AppColors.muted
        case .mild: return AppColors.amber
        case .high: return AppColors.danger
        }
    }
}

/// Rep Lab's Joints tab (docs/design/body-and-joint-journal.md): the user's own ratings over 8 weeks beside
/// each session's heaviest working set. It draws no conclusion from them.
struct JointJournalView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let history: [WorkoutSessionRecord]
    let weightUnit: WeightUnit
    let isPreview: Bool
    let ratingsEnabled: Bool
    let onEnableRatings: () -> Void

    private var summaries: [JointExerciseSummary] {
        let today = BodyDay.today()
        return isPreview ? ProPreviewData.jointJournalSample(today: today) : JointJournal.summaries(history: history, today: today)
    }

    var body: some View {
        let _ = themeManager.currentTheme
        let summaries = summaries
        VStack(alignment: .leading, spacing: 12) {
            if !ratingsEnabled && !isPreview {
                notice(title: "form_lab.joints.off_title", body: "form_lab.joints.off_body", showsEnable: true)
            } else if summaries.isEmpty {
                notice(title: "form_lab.joints.empty_title", body: "form_lab.joints.empty_body", showsEnable: false)
            }
            if !summaries.isEmpty {
                legend
                ForEach(summaries) { exerciseCard($0) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joint-journal")
    }

    private func notice(title: String, body: String, showsEnable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LanguageManager.t(title)).font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(LanguageManager.t(body)).font(.app(size: 13)).lineSpacing(3).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showsEnable {
                Button(action: onEnableRatings) {
                    Text(LanguageManager.t("form_lab.joints.enable"))
                        .font(.app(size: 14, weight: .semibold)).foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppColors.accent).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("joint-journal-enable")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityIdentifier("joint-journal-notice")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                ForEach(JointStress.allCases, id: \.self) { rating in
                    HStack(spacing: 6) {
                        marker(rating, size: 12)
                        Text(LanguageManager.t(rating.labelKey)).font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
            Text(LanguageManager.t("form_lab.joints.load_caption", ["unit": weightUnit.label]))
                .font(.app(size: 12)).foregroundStyle(AppColors.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func marker(_ rating: JointStress, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(rating.markerColor.opacity(0.28))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(rating.markerColor.opacity(0.85), lineWidth: 1))
            .frame(width: size, height: size)
    }

    private func exerciseCard(_ summary: JointExerciseSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: summary.exerciseName))
                    .font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(LanguageManager.shared.plural("form_lab.joints.ratings", summary.total) + " · " +
                     LanguageManager.t("form_lab.joints.breakdown", ["high": summary.high, "mild": summary.mild, "none": summary.none]))
                    .font(.app(size: 12)).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(summary.recent.enumerated()), id: \.offset) { index, entry in
                            ratingColumn(entry).id(index)
                        }
                    }
                }
                // The most recent ratings are the ones in view.
                .onAppear { proxy.scrollTo(summary.recent.count - 1, anchor: .trailing) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joint-journal-\(summary.exerciseName)")
    }

    private func ratingColumn(_ entry: JointRatingEntry) -> some View {
        let date = shortDate(entry.date)
        let load = entry.topLoadKg.map { weightUnit.formatDisplayWeight($0) } ?? LanguageManager.t("form_lab.joints.bodyweight")
        let spokenLoad = entry.topLoadKg == nil ? load : "\(load) \(weightUnit.label)"
        return VStack(spacing: 6) {
            Text(date).font(.app(size: 10)).foregroundStyle(AppColors.muted).lineLimit(1)
            marker(entry.rating, size: 22)
            Text(load).font(.app(size: 11, weight: .medium)).foregroundStyle(AppColors.secondaryText).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 8).frame(minWidth: 52)
        .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LanguageManager.t("form_lab.joints.marker", ["date": date, "rating": LanguageManager.t(entry.rating.labelKey), "load": spokenLoad]))
    }

    private func shortDate(_ date: String) -> String {
        guard let parsed = WorkoutCalendar.parseDate(date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: parsed)
    }
}
