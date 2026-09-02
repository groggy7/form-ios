import SwiftUI

public struct HistoryView: View {
    @ObservedObject var store: AppStore
    var onOpenSettings: () -> Void
    var onSelectRecord: (WorkoutSessionRecord) -> Void

    public init(
        store: AppStore,
        onOpenSettings: @escaping () -> Void,
        onSelectRecord: @escaping (WorkoutSessionRecord) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onSelectRecord = onSelectRecord
    }

    public var body: some View {
        let history = store.state.history

        ScrollView {
            VStack(spacing: 16) {
                AppHeader(
                    title: LanguageManager.t("nav.history"),
                    subtitle: "\(history.count) " + LanguageManager.t("history.workoutsCount").lowercased(),
                    onSettingsClick: onOpenSettings
                )

                if history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(AppColors.muted.opacity(0.4))
                            .padding(.top, 40)

                        Text(LanguageManager.t("history.empty"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.text)

                        Text(LanguageManager.t("history.emptyHint"))
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(history) { record in
                            Button(action: { onSelectRecord(record) }) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(record.workoutTitle)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(AppColors.text)

                                        Spacer()

                                        if record.isComplete == false {
                                            Text(LanguageManager.t("history.unfinished"))
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(AppColors.unfinishedText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(AppColors.unfinishedSurface)
                                                .cornerRadius(6)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppColors.positive)
                                                .font(.system(size: 16))
                                        }
                                    }

                                    HStack(spacing: 16) {
                                        Label(RestTimerUtils.formatSecondsToTime(record.durationSeconds), systemImage: "timer")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppColors.muted)

                                        Label("\(record.totalCompletedSets) sets", systemImage: "checkmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppColors.muted)

                                        Label("\(Int(record.totalVolumeKg)) kg", systemImage: "scalemass")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppColors.muted)

                                        Spacer()

                                        Text(shortDate(record.completedAt))
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.muted)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppColors.border, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 100)
            }
        }
    }

    private func shortDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let out = DateFormatter()
        out.dateStyle = .short
        return out.string(from: date)
    }
}
