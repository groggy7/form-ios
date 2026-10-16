import SwiftUI

/// "Machine taken?" picker: curated substitutes first, then a library search. The choice replaces
/// the exercise for this workout only; the program is unchanged.
struct ExerciseSwapSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    let exercise: Exercise
    let excludedIds: Set<String>
    var onReplace: (String) -> Void
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var excluded: Set<String> { excludedIds.union([exercise.exerciseId].compactMap { $0 }) }

    private var suggestions: [ExerciseSwapSuggestion] {
        ExerciseSwaps.suggestions(for: exercise.exerciseId, excluding: excluded)
    }

    private var results: [Exercise] {
        let query = ExerciseSearch.Query(search)
        guard !query.tokens.isEmpty else { return [] }
        return ExerciseCatalog.canonicalExercises.values
            .filter { !excluded.contains($0.id) }
            .map { $0.toExercise() }
            .compactMap { candidate -> (Exercise, Int)? in
                ExerciseSearch.score(query, exercise: candidate, localizedName: candidate.displayName,
                    category: "\(LanguageManager.t("category.\(candidate.resolvedMovement.rawValue)")) \(candidate.metadataSubtitle)")
                    .map { (candidate, $0) }
            }
            .sorted { $0.1 == $1.1 ? ExercisePriority.compare($0.0, $1.0) : $0.1 < $1.1 }
            .prefix(30).map { $0.0 }
    }

    var body: some View {
        let _ = theme.currentTheme
        let isSearching = !ExerciseSearch.Query(search).tokens.isEmpty
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text(exercise.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                    Text(LanguageManager.t("session.replace.subtitle"))
                        .font(.footnote)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                    if isSearching {
                        let found = results
                        if found.isEmpty {
                            message("session.replace.noResults")
                        }
                        ForEach(found, id: \.id) { row($0) }
                    } else {
                        let all = suggestions
                        if all.isEmpty {
                            message("session.replace.noSuggestions")
                        }
                        group("session.replace.sameMovement", all.filter(\.samePattern))
                        group("session.replace.related", all.filter { !$0.samePattern })
                    }
                }
                .padding(20)
            }
            .background(AppColors.background)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: LanguageManager.t("session.replace.search"))
            .navigationTitle(LanguageManager.t("session.replace.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(LanguageManager.t("common.close"))
                    .accessibilityIdentifier("exercise-swap-close")
                }
            }
        }
        .accessibilityIdentifier("exercise-swap-sheet")
    }

    @ViewBuilder
    private func group(_ titleKey: String, _ items: [ExerciseSwapSuggestion]) -> some View {
        let rows = items.compactMap { ExerciseCatalog.canonicalExercises[$0.exerciseId]?.toExercise() }
        if !rows.isEmpty {
            Text(LanguageManager.t(titleKey))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.top, 4)
            ForEach(rows, id: \.id) { row($0) }
        }
    }

    private func message(_ key: String) -> some View {
        Text(LanguageManager.t(key))
            .font(.footnote)
            .foregroundStyle(AppColors.secondaryText)
            .padding(.vertical, 8)
    }

    private func row(_ candidate: Exercise) -> some View {
        let id = candidate.exerciseId ?? candidate.id
        return Button { onReplace(id) } label: {
            HStack(spacing: 12) {
                MovementIcon(exerciseId: candidate.exerciseId, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(2)
                    if !candidate.metadataSubtitle.isEmpty {
                        Text(candidate.metadataSubtitle)
                            .font(.caption)
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(minHeight: 64)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exercise-swap-option-\(id)")
    }
}
