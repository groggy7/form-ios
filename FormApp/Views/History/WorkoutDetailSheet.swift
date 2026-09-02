import SwiftUI

public struct WorkoutDetailSheet: View {
    let record: WorkoutSessionRecord
    var onDismiss: () -> Void

    public init(record: WorkoutSessionRecord, onDismiss: @escaping () -> Void) {
        self.record = record
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Metrics
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.workoutTitle)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppColors.text)

                        Text(formattedDate(record.completedAt))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.muted)
                    }

                    HStack(spacing: 12) {
                        metricTile(title: LanguageManager.t("summary.totalDuration"), value: RestTimerUtils.formatSecondsToTime(record.durationSeconds))
                        metricTile(title: LanguageManager.t("summary.setsCompleted"), value: "\(record.totalCompletedSets)")
                        metricTile(title: LanguageManager.t("summary.estimatedVolume"), value: "\(Int(record.totalVolumeKg)) kg")
                    }

                    Divider().background(AppColors.border)

                    // Exercise recap list
                    VStack(alignment: .leading, spacing: 14) {
                        Text(LanguageManager.t("summary.exerciseRecap"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.text)

                        ForEach(record.exerciseLogs, id: \.exerciseName) { exLog in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exLog.exerciseName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(AppColors.accent)

                                ForEach(exLog.sets, id: \.setNumber) { setLog in
                                    HStack {
                                        Text("\(LanguageManager.t("table.set")) \(setLog.setNumber)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppColors.muted)
                                            .frame(width: 60, alignment: .leading)

                                        Spacer()

                                        let weightText = setLog.weightKg.map { WorkoutSessionUtils.formatWeight($0) + " kg" } ?? "—"
                                        Text(weightText)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)

                                        Text("×")
                                            .foregroundColor(AppColors.muted)

                                        let repsText = setLog.reps.map { "\($0) reps" } ?? "—"
                                        Text(repsText)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(AppColors.surface)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(14)
                            .background(AppColors.surfaceRaised)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        }
                    }
                }
                .padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("history.workoutDetail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.muted)
                    }
                }
            }
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.muted)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }

    private func formattedDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}
