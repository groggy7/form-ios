import SwiftUI

public struct ExerciseDetailSheet: View {
    @ObservedObject var store: AppStore = AppStore.shared
    let initialExercise: Exercise
    var onDismiss: () -> Void

    @State private var showVideoLinks: Bool = false

    public init(exercise: Exercise, onDismiss: @escaping () -> Void) {
        self.initialExercise = exercise
        self.onDismiss = onDismiss
    }

    private var currentExercise: Exercise {
        let key = initialExercise.name.trimmingCharacters(in: .whitespaces).lowercased()
        if let catalogExercise = store.exerciseCatalogue.first(where: { $0.key == key })?.exercise {
            if !catalogExercise.videos.isEmpty || initialExercise.videos.isEmpty {
                return catalogExercise
            }
        }
        return initialExercise
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title & Movement Badge
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentExercise.displayName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppColors.text)

                        Text(currentExercise.resolvedMovement.rawValue.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.positiveBg)
                            .cornerRadius(6)
                    }

                    // Local exercise video; the muscle panel is independent of playback.
                    ExerciseDetailVideo(exerciseId: currentExercise.exerciseId)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.exerciseVideoSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppColors.border, lineWidth: 1)
                        )

                    ExerciseMusclesCard(exerciseId: currentExercise.exerciseId)

                    // Technique Cues
                    let cuesText = currentExercise.displayCues.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cuesText.isEmpty {
                        TechniqueSectionView(
                            title: LanguageManager.t("modal.exercise.cues"),
                            text: cuesText,
                            accent: AppColors.accent,
                            isAvoid: false
                        )
                    }

                    // What to Avoid
                    let avoidText = currentExercise.displayAvoid.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !avoidText.isEmpty {
                        TechniqueSectionView(
                            title: LanguageManager.t("modal.exercise.avoid"),
                            text: avoidText,
                            accent: AppColors.danger,
                            isAvoid: true
                        )
                    }

                    // Technique Videos
                    ExerciseVideosView(
                        exercise: currentExercise,
                        onAddVideo: { showVideoLinks = true },
                        onRemoveVideo: { urlToRemove in
                            let remaining = currentExercise.videos.filter { $0 != urlToRemove }
                            store.setExerciseVideos(exerciseName: currentExercise.name, videoUrls: remaining)
                        }
                    )
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
            .sheet(isPresented: $showVideoLinks) {
                ExerciseVideoLinksSheet(
                    exercise: currentExercise,
                    onDismiss: { showVideoLinks = false }
                )
            }
        }
    }
}

struct TechniqueSectionView: View {
    let title: String
    let text: String
    let accent: Color
    let isAvoid: Bool
    @State private var isExpanded: Bool

    init(title: String, text: String, accent: Color, isAvoid: Bool, initiallyExpanded: Bool = false) {
        self.title = title
        self.text = text
        self.accent = accent
        self.isAvoid = isAvoid
        self._isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.muted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            if isExpanded {
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isAvoid ? AppColors.avoidBg : AppColors.cuesBg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isAvoid ? AppColors.avoidBorder : AppColors.cuesBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}
