import SwiftUI

public struct ExerciseDetailView: View {
    @ObservedObject var store: AppStore = AppStore.shared
    let initialExercise: Exercise
    var onBack: () -> Void

    @State private var showVideoLinks: Bool = false
    @State private var showReportSheet: Bool = false

    public init(exercise: Exercise, onBack: @escaping () -> Void) {
        self.initialExercise = exercise
        self.onBack = onBack
    }

    public init(exercise: Exercise, onDismiss: @escaping () -> Void) {
        self.initialExercise = exercise
        self.onBack = onDismiss
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
        VStack(spacing: 0) {
            // Top Navigation Bar matching Android
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("common.back"))

                Text(LanguageManager.t("library.details"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title & Movement Category
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentExercise.displayName)
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundColor(AppColors.text)

                        let categoryKey = "category.\(currentExercise.resolvedMovement.rawValue)"
                        Text(LanguageManager.t(categoryKey))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.accent)
                            .tracking(0.7)
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

                    // Report an issue
                    Button(action: {
                        showReportSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "flag")
                                .font(.system(size: 14, weight: .medium))
                            Text(LanguageManager.t("report.action"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(AppColors.muted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .sheet(isPresented: $showVideoLinks) {
            ExerciseVideoLinksSheet(
                exercise: currentExercise,
                onDismiss: { showVideoLinks = false }
            )
        }
        .sheet(isPresented: $showReportSheet) {
            ExerciseReportSheet(
                exercise: currentExercise,
                onDismiss: { showReportSheet = false },
                onSubmit: { report in
                    ExerciseReportStore.shared.saveReport(report)
                    showReportSheet = false
                    store.showNotice(LanguageManager.t("report.submitted"))
                }
            )
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.startLocation.x < 50 && value.translation.width > 80 {
                        onBack()
                    }
                }
        )
    }
}

public typealias ExerciseDetailSheet = ExerciseDetailView

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
