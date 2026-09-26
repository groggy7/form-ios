import SwiftUI

public struct ExerciseReportSheet: View {
    let exercise: Exercise
    var onDismiss: () -> Void
    var onSubmit: (ExerciseIssueReport) -> Void

    @State private var selectedCategory: String = ExerciseReportStore.categories.first ?? "animation_form"
    @State private var comments: String = ""

    public init(
        exercise: Exercise,
        onDismiss: @escaping () -> Void,
        onSubmit: @escaping (ExerciseIssueReport) -> Void
    ) {
        self.exercise = exercise
        self.onDismiss = onDismiss
        self.onSubmit = onSubmit
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("report.title"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.text)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LanguageManager.t("common.close"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Scrollable Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Exercise Info Card
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.exerciseThumbnailSurface)

                                MovementIllustration(exerciseId: exercise.exerciseId)
                                    .padding(4)
                            }
                            .frame(width: 76, height: 76)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.displayName)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(2)

                                Text(LanguageManager.t("category.\(exercise.resolvedMovement.key)").uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Issue Category Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("report.category"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            VStack(spacing: 8) {
                                ForEach(ExerciseReportStore.categories, id: \.self) { cat in
                                    let isSelected = selectedCategory == cat
                                    Button(action: {
                                        selectedCategory = cat
                                    }) {
                                        HStack {
                                            Text(LanguageManager.t("report.category.\(cat)"))
                                                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(isSelected ? AppColors.accent : AppColors.text)

                                            Spacer()

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18))
                                                .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(isSelected ? AppColors.positiveBg : AppColors.surface)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                        .stroke(isSelected ? AppColors.accent.opacity(0.4) : AppColors.border, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Comments Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("report.detailsLabel"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            ZStack(alignment: .topLeading) {
                                if comments.isEmpty {
                                    Text(LanguageManager.t("report.detailsPlaceholder"))
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.muted)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }

                                TextEditor(text: $comments)
                                    .scrollContentBackground(.hidden)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.text)
                                    .frame(minHeight: 90)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.surfaceRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                // Bottom Submit Action
                VStack(spacing: 0) {
                    Divider().background(AppColors.border)

                    Button(action: {
                        let report = ExerciseIssueReport(
                            exerciseId: exercise.exerciseId,
                            exerciseName: exercise.name,
                            category: selectedCategory,
                            comment: comments.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSubmit(report)
                    }) {
                        Text(LanguageManager.t("report.submit"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(AppColors.surface)
            }
            .background(AppColors.background.ignoresSafeArea())
        }
    }
}
