import SwiftUI

public struct ExerciseDetailSheet: View {
    let exercise: Exercise
    var onDismiss: () -> Void

    public init(exercise: Exercise, onDismiss: @escaping () -> Void) {
        self.exercise = exercise
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Anatomy Artwork Banner
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )

                        MovementIllustration(
                            name: exercise.name,
                            movementType: exercise.resolvedMovement,
                            movementAssetId: exercise.movementAssetId,
                            allowCategoryFallback: false
                        )
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 224)

                    // Title & Movement Badge
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(exercise.resolvedMovement.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.positiveBg)
                                .cornerRadius(6)

                            Spacer()

                            if let rest = exercise.restSeconds {
                                Label("\(rest)s rest", systemImage: "timer")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.muted)
                            }
                        }

                        Text(exercise.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppColors.text)

                        if !exercise.displayPrescription.isEmpty {
                            Text(exercise.displayPrescription)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppColors.accent)
                        }
                    }

                    // Technique Cues
                    let cuesText = exercise.cues.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cuesText.isEmpty {
                        techniqueSection(
                            title: LanguageManager.t("modal.exercise.cues"),
                            text: cuesText,
                            accent: AppColors.accent,
                            isAvoid: false
                        )
                    }

                    // What to Avoid
                    let avoidText = exercise.avoid.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !avoidText.isEmpty {
                        techniqueSection(
                            title: LanguageManager.t("modal.exercise.avoid"),
                            text: avoidText,
                            accent: AppColors.danger,
                            isAvoid: true
                        )
                    }

                    // Video Links
                    if !exercise.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("editor.videos"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.text)

                            ForEach(Array(exercise.videos.enumerated()), id: \.offset) { index, urlString in
                                if let url = URL(string: urlString) {
                                    Link(destination: url) {
                                        HStack {
                                            Image(systemName: "play.rectangle.fill")
                                                .foregroundColor(AppColors.coral)
                                            Text("Demo Video \(index + 1)")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(AppColors.text)
                                            Spacer()
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)
                                        }
                                        .padding(14)
                                        .background(AppColors.surface)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("library.details"))
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

    private func techniqueSection(title: String, text: String, accent: Color, isAvoid: Bool) -> some View {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: isAvoid ? "xmark" : "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(accent)
                            .padding(.top, 3)

                        let cleanLine = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
                        Text(LanguageManager.content(cleanLine))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}
