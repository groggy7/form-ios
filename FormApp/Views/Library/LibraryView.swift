import SwiftUI

public struct LibraryView: View {
    @ObservedObject var store: AppStore
    var onSelectExercise: (Exercise) -> Void
    var onOpenSettings: () -> Void

    @State private var query: String = ""
    @State private var selectedMovement: MovementType? = nil
    @State private var showFiltersSheet: Bool = false

    public init(
        store: AppStore,
        onSelectExercise: @escaping (Exercise) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.store = store
        self.onSelectExercise = onSelectExercise
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let catalogue = store.exerciseCatalogue
        let filtered = catalogue.filter { entry in
            let matchQuery = query.isEmpty || entry.exercise.name.localizedCaseInsensitiveContains(query)
            let matchMovement = selectedMovement == nil || entry.exercise.resolvedMovement == selectedMovement
            return matchQuery && matchMovement
        }
        let hasActiveFilters = selectedMovement != nil

        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    Text(LanguageManager.t("library.title"))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(AppColors.text)

                    Spacer()

                    FormHeaderIconButton(
                        icon: "gearshape.fill",
                        contentDescription: LanguageManager.t("settings.title"),
                        onClick: onOpenSettings
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Search & Filter Row
                HStack(spacing: 8) {
                    // Search box
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.muted)

                        TextField(LanguageManager.t("library.search"), text: $query)
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.text)
                            .accentColor(AppColors.accent)

                        if !query.isEmpty {
                            Button(action: { query = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    )

                    // Filters button
                    FormHeaderIconButton(
                        icon: "slider.horizontal.3",
                        contentDescription: LanguageManager.t("library.filters"),
                        tint: hasActiveFilters ? AppColors.accent : AppColors.secondaryText,
                        onClick: { showFiltersSheet = true }
                    )
                }
                .padding(.horizontal, 20)

                // Active filters row
                if hasActiveFilters {
                    HStack(spacing: 8) {
                        if let mov = selectedMovement {
                            HStack(spacing: 6) {
                                Text(LanguageManager.t("category.\(mov.key)"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.accent)

                                Button(action: { selectedMovement = nil }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(AppColors.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.positiveBg)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
                            )
                        }

                        Button(action: {
                            selectedMovement = nil
                            query = ""
                        }) {
                            Text(LanguageManager.t("library.clearFilters"))
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)

                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }

                // Exercise items list
                VStack(spacing: 8) {
                    ForEach(filtered, id: \.id) { entry in
                        let exercise = entry.exercise
                        Button(action: { onSelectExercise(exercise) }) {
                            HStack(spacing: 12) {
                                MovementIcon(
                                    name: exercise.name,
                                    size: 72,
                                    movementType: exercise.resolvedMovement,
                                    movementAssetId: exercise.movementAssetId
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .lineSpacing(2)
                                        .foregroundColor(AppColors.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Text(LanguageManager.t("category.\(exercise.resolvedMovement.key)"))
                                        .font(.system(size: 11))
                                        .foregroundColor(AppColors.muted)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.muted.opacity(0.6))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(AppColors.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if filtered.isEmpty {
                        Text(LanguageManager.t("library.noResults"))
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.muted)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 16)
            }
        }
        .sheet(isPresented: $showFiltersSheet) {
            filterMovementSheet()
        }
    }

    private func filterMovementSheet() -> some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LanguageManager.t("library.filterMovement"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.text)
                            .padding(.top, 16)

                        let movements = MovementType.allCases
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(movements, id: \.rawValue) { (mov: MovementType) in
                                let isSelected = selectedMovement == mov
                                Button(action: {
                                    if isSelected { selectedMovement = nil }
                                    else { selectedMovement = mov }
                                    showFiltersSheet = false
                                }) {
                                    Text(LanguageManager.t("category.\(mov.key)"))
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? AppColors.accent : AppColors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(isSelected ? AppColors.positiveBg : AppColors.surface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer().frame(height: 20)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitle(LanguageManager.t("library.filters"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LanguageManager.t("common.done")) {
                        showFiltersSheet = false
                    }
                    .foregroundColor(AppColors.accent)
                }
            }
        }
    }
}
