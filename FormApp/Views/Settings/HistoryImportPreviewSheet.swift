import SwiftUI

public struct HistoryImportPreviewSheet: View {
    public let preview: HistoryImportPreview
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(preview: HistoryImportPreview, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.preview = preview
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(LanguageManager.t("import.historyTitle"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppColors.text)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(width: 32, height: 32)
                            .background(AppColors.surfaceRaised)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().background(AppColors.border)

                ScrollView {
                    VStack(spacing: 16) {
                        // Source card
                        HStack {
                            Text(LanguageManager.t("import.source"))
                                .font(.system(size: 15))
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text(preview.source.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColors.accent.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .padding(16)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )

                        // Stats breakdown card
                        VStack(spacing: 14) {
                            statRow(
                                title: LanguageManager.t("import.workoutsToImport"),
                                value: "\(preview.newWorkoutsCount)",
                                isHighlight: true
                            )

                            if preview.duplicateWorkoutsCount > 0 {
                                Divider().background(AppColors.border)
                                statRow(
                                    title: LanguageManager.t("import.duplicatesSkipped"),
                                    value: "\(preview.duplicateWorkoutsCount)",
                                    isHighlight: false
                                )
                            }

                            Divider().background(AppColors.border)
                            statRow(
                                title: LanguageManager.t("import.totalSets"),
                                value: "\(preview.totalSetsCount)",
                                isHighlight: false
                            )

                            if let earliest = preview.earliestDate, let latest = preview.latestDate {
                                Divider().background(AppColors.border)
                                statRow(
                                    title: LanguageManager.t("import.dateRange"),
                                    value: "\(earliest) – \(latest)",
                                    isHighlight: false
                                )
                            }

                            Divider().background(AppColors.border)
                            statRow(
                                title: LanguageManager.t("import.exercisesRecognized"),
                                value: preview.customExercisesCount > 0
                                    ? "\(preview.canonicalMatchesCount) (+\(preview.customExercisesCount) custom)"
                                    : "\(preview.canonicalMatchesCount)",
                                isHighlight: false
                            )
                        }
                        .padding(16)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                    }
                    .padding(20)
                }

                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text(String(format: LanguageManager.t("import.confirmButton"), preview.newWorkoutsCount))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(preview.newWorkoutsCount > 0 ? AppColors.accent : AppColors.muted)
                            .cornerRadius(12)
                    }
                    .disabled(preview.newWorkoutsCount == 0)

                    Button(action: onCancel) {
                        Text(LanguageManager.t("import.cancelButton"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private func statRow(title: String, value: String, isHighlight: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppColors.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: isHighlight ? .bold : .medium))
                .foregroundColor(isHighlight ? AppColors.text : AppColors.secondaryText)
        }
    }
}
