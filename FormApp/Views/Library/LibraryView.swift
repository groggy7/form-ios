import SwiftUI

public struct LibraryView: View {
    @ObservedObject var store: AppStore
    var onOpenSettings: () -> Void
    var onSelectExercise: (Exercise) -> Void

    @State private var searchText = ""
    @State private var selectedMovement: MovementType? = nil

    public init(
        store: AppStore,
        onOpenSettings: @escaping () -> Void,
        onSelectExercise: @escaping (Exercise) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onSelectExercise = onSelectExercise
    }

    public var body: some View {
        let entries = filteredCatalogue

        ScrollView {
            VStack(spacing: 16) {
                AppHeader(
                    title: LanguageManager.t("library.title"),
                    subtitle: "\(entries.count) " + LanguageManager.t("today.exercises").lowercased(),
                    onSettingsClick: onOpenSettings
                )

                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.muted)
                    TextField(LanguageManager.t("library.searchPlaceholder"), text: $searchText)
                        .foregroundColor(AppColors.text)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.muted)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                .padding(.horizontal, 20)

                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: LanguageManager.t("library.allMovements"), isSelected: selectedMovement == nil) {
                            selectedMovement = nil
                        }

                        ForEach(MovementType.allCases, id: \.self) { mov in
                            filterChip(title: mov.rawValue.capitalized, isSelected: selectedMovement == mov) {
                                selectedMovement = mov
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Exercise List
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        let ex = entry.exercise
                        Button(action: { onSelectExercise(ex) }) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ex.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                        .lineLimit(1)

                                    HStack(spacing: 8) {
                                        Text(ex.resolvedMovement.rawValue.uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(AppColors.accent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AppColors.positiveBg)
                                            .cornerRadius(4)

                                        if !ex.displayPrescription.isEmpty {
                                            Text(ex.displayPrescription)
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.muted.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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

                Spacer().frame(height: 100)
            }
        }
    }

    private var filteredCatalogue: [ExerciseCatalogEntry] {
        store.exerciseCatalogue.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.exercise.name.localizedCaseInsensitiveContains(searchText) ||
                entry.exercise.cues.localizedCaseInsensitiveContains(searchText)
            let matchesMovement = selectedMovement == nil || entry.exercise.resolvedMovement == selectedMovement
            return matchesSearch && matchesMovement
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? AppColors.todaySelectionText : AppColors.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? AppColors.accent : AppColors.surface)
                        .overlay(Capsule().stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}
