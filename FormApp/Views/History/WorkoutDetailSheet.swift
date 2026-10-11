import SwiftUI

public struct WorkoutDetailSheet: View {
    let record: WorkoutSessionRecord
    var onDismiss: () -> Void
    var weightUnit: WeightUnit = .kg

    public init(record: WorkoutSessionRecord, onDismiss: @escaping () -> Void, weightUnit: WeightUnit = .kg) {
        self.record = record
        self.onDismiss = onDismiss
        self.weightUnit = weightUnit
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Metrics
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.workoutTitle)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.text)

                        Text(formattedDate(record.completedAt))
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.muted)
                    }

                    HStack(spacing: 12) {
                        metricTile(title: LanguageManager.t("summary.totalDuration"), value: RestTimerUtils.formatSecondsToTime(record.durationSeconds))
                        metricTile(title: LanguageManager.t("summary.setsCompleted"), value: "\(record.totalCompletedSets)")
                        metricTile(title: LanguageManager.t("summary.estimatedVolume"), value: "\(weightUnit.formatVolume(WorkoutSessionUtils.resistanceVolume(record))) \(weightUnit.label)")
                    }

                    Divider().background(AppColors.border)

                    // Exercise recap list
                    VStack(alignment: .leading, spacing: 14) {
                        Text(LanguageManager.t("summary.exerciseRecap"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.text)

                        ForEach(record.exerciseLogs, id: \.exerciseName) { exLog in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exLog.exerciseName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)

                                ForEach(exLog.sets, id: \.setNumber) { setLog in
                                    HStack {
                                        Text("\(LanguageManager.t("table.set")) \(setLog.setNumber)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(AppColors.muted)
                                            .frame(width: 60, alignment: .leading)

                                        Spacer()

                                        let weightText = setLog.weightKg.map { weightUnit.formatDisplayWeight($0) + " " + weightUnit.label } ?? "—"
                                        Text(weightText)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.text)

                                        Text("×")
                                            .foregroundStyle(AppColors.muted)

                                        let repsText = setLog.reps.map { "\($0) reps" } ?? "—"
                                        Text(repsText)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.text)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(AppColors.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(14)
                            .background(AppColors.surfaceRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
            }
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.muted)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AppColors.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }

    private func formattedDate(_ isoString: String) -> String {
        guard let date = WorkoutCalendar.parseIsoTimestamp(isoString) else { return isoString }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}
