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
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.surfaceRaised)
                            .frame(height: 220)

                        if let assetId = exercise.movementAssetId, !assetId.isEmpty {
                            let imageName = "anatomy_" + assetId.replacingOccurrences(of: "-", with: "_")
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 210)
                        } else {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 60))
                                .foregroundColor(AppColors.muted.opacity(0.4))
                        }
                    }

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

                    // Form Cues
                    if !exercise.cues.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LanguageManager.t("editor.cues"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.text)
                            Text(exercise.cues)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                    }

                    // What to avoid
                    if !exercise.avoid.trimmingCharacters(in: .whitespaces).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LanguageManager.t("editor.avoid"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.danger)
                            Text(exercise.avoid)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.secondaryText)
                                .lineSpacing(4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
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
            .navigationTitle(LanguageManager.t("library.detail"))
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
}
