import SwiftUI

public enum LibraryFilterModal: String, Identifiable {
    case equipment
    case muscle

    public var id: String { rawValue }
}

public struct LibraryView: View {
    @ObservedObject var store: AppStore
    var onSelectExercise: (Exercise) -> Void
    var onOpenSettings: () -> Void

    @State private var query: String = ""
    @State private var selectedEquipment: String? = nil
    @State private var selectedMuscle: String? = nil
    @State private var activeModal: LibraryFilterModal? = nil
    @AppStorage("library_is_card_view") private var isCardView: Bool = false

    public init(
        store: AppStore,
        onSelectExercise: @escaping (Exercise) -> Void,
        onOpenSettings: @escaping () -> Void,
        initialModal: LibraryFilterModal? = nil
    ) {
        self.store = store
        self.onSelectExercise = onSelectExercise
        self.onOpenSettings = onOpenSettings
        self._activeModal = State(initialValue: initialModal)
    }

    public var body: some View {
        let catalogue = store.exerciseCatalogue
        let search = ExerciseSearch.Query(query)
        let filtered = catalogue.compactMap { entry -> (ExerciseCatalogEntry, Int)? in
            let matchEquipment = EquipmentCatalog.shared.matches(entry.exercise.exerciseId, selected: selectedEquipment)
            let matchMuscle = ExerciseMetadata.matchesMuscle(exercise: entry.exercise, muscleKey: selectedMuscle)
            guard matchEquipment, matchMuscle,
                let score = ExerciseSearch.score(search, exercise: entry.exercise,
                localizedName: entry.exercise.displayName,
                category: "\(LanguageManager.t("category.\(entry.exercise.resolvedMovement.rawValue)")) \(entry.exercise.metadataSubtitle)") else { return nil }
            return (entry, score)
        }.sorted { $0.1 == $1.1 ? ExercisePriority.compare($0.0.exercise, $1.0.exercise) : $0.1 < $1.1 }
            .map { $0.0 }
        let hasActiveFilters = selectedEquipment != nil || selectedMuscle != nil

        if let selectedId = store.selectedExerciseId, let selectedExercise = store.findExercise(id: selectedId) {
            ExerciseDetailView(exercise: selectedExercise, onBack: {
                store.selectExerciseInLibrary(id: nil)
            })
        } else {
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

                    // View mode toggle button
                    FormHeaderIconButton(
                        icon: isCardView ? "list.bullet" : "square.grid.2x2",
                        contentDescription: isCardView ? LanguageManager.t("library.viewList") : LanguageManager.t("library.viewCards"),
                        tint: isCardView ? AppColors.accent : AppColors.secondaryText,
                        onClick: { isCardView.toggle() }
                    )
                }
                .padding(.horizontal, 20)

                // 2 equally spaced category buttons: Equipment, Muscle Group
                HStack(spacing: 8) {
                    // Equipment pill
                    let equipTitle = EquipmentCatalog.shared.categories.first(where: { $0.id == selectedEquipment })?.title
                        ?? LanguageManager.t("library.filter.allEquipments")
                    LibraryFilterPill(
                        title: equipTitle,
                        isSelected: selectedEquipment != nil,
                        equipment: EquipmentCatalog.shared.categories.first(where: { $0.id == selectedEquipment }),
                        onTap: { activeModal = .equipment },
                        onClear: { selectedEquipment = nil }
                    )
                    .accessibilityIdentifier(selectedEquipment != nil ? "library-active-filter-equipment" : "library-filter-equipment")

                    // Muscle pill
                    let muscleTitle = selectedMuscle != nil ? LanguageManager.t("exercise.muscle.\(selectedMuscle!)") : LanguageManager.t("library.filter.allMuscles")
                    LibraryFilterPill(
                        title: muscleTitle,
                        isSelected: selectedMuscle != nil,
                        onTap: { activeModal = .muscle },
                        onClear: { selectedMuscle = nil }
                    )
                    .accessibilityIdentifier(selectedMuscle != nil ? "library-active-filter-muscle" : "library-filter-muscle")
                }
                .padding(.horizontal, 20)

                if isCardView {
                    // Exercise cards grid (2 columns)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(filtered, id: \.id) { entry in
                            let exercise = entry.exercise
                            Button(action: { onSelectExercise(exercise) }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(AppColors.exerciseThumbnailSurface)

                                        MovementIllustration(exerciseId: exercise.exerciseId)
                                        .padding(4)
                                    }
                                    .frame(height: 96)
                                    .frame(maxWidth: .infinity)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(exercise.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppColors.text)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

                                        Text(exercise.metadataSubtitle)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.muted)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(10)
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
                    }
                    .padding(.horizontal, 20)

                    if filtered.isEmpty {
                        Text(LanguageManager.t("library.noResults"))
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.muted)
                            .padding(.top, 40)
                    }
                } else {
                    // Exercise items list
                    VStack(spacing: 8) {
                        ForEach(filtered, id: \.id) { entry in
                            let exercise = entry.exercise
                            Button(action: { onSelectExercise(exercise) }) {
                                HStack(spacing: 12) {
                                    MovementIcon(
                                        exerciseId: exercise.exerciseId,
                                        size: 72
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.displayName)
                                            .font(.system(size: 15, weight: .medium))
                                            .lineSpacing(2)
                                            .foregroundColor(AppColors.text)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)

                                        Text(exercise.metadataSubtitle)
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
                }

                Spacer().frame(height: 16)
            }
        }
        .overlay {
            if let modal = activeModal {
                ZStack {
                    Color.black.opacity(0.65)
                        .ignoresSafeArea()
                        .onTapGesture {
                            activeModal = nil
                        }

                    VStack(spacing: 0) {
                        switch modal {
                        case .equipment:
                            equipmentModalView()
                        case .muscle:
                            muscleModalView()
                        }
                    }
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 380, maxHeight: 580)
                    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 12)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeModal)
        .onAppear {
            if let selectedId = store.selectedExerciseId, store.findExercise(id: selectedId) == nil {
                store.selectExerciseInLibrary(id: nil)
            }
        }
        }
    }

    private func modalHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.text)
            Spacer()
            Button(action: { activeModal = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LanguageManager.t("common.done"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func equipmentModalView() -> some View {
        VStack(spacing: 0) {
            modalHeader(title: LanguageManager.t("library.equipment"))
            ScrollView {
                VStack(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(EquipmentCatalog.shared.categories) { category in
                            let isSelected = selectedEquipment == category.id
                            let solidColor = equipmentSolidColor(categoryId: category.id)
                            Button(action: {
                                selectedEquipment = isSelected ? nil : category.id
                                activeModal = nil
                            }) {
                                HStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(solidColor.opacity(0.16))
                                        EquipmentIcon(category: category, tint: solidColor)
                                    }
                                    .frame(width: 34, height: 34)

                                    Text(category.title)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundColor(isSelected ? AppColors.accent : AppColors.text)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(isSelected ? AppColors.positiveBg : AppColors.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("equipment-\(category.id)")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .accessibilityIdentifier("library-equipment-modal")
    }

    private func muscleModalView() -> some View {
        VStack(spacing: 0) {
            modalHeader(title: LanguageManager.t("library.muscles"))
            ScrollView {
                VStack(spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(MuscleGroupFilter.allCases) { muscle in
                            let isSelected = selectedMuscle == muscle.rawValue
                            Button(action: {
                                selectedMuscle = isSelected ? nil : muscle.rawValue
                                activeModal = nil
                            }) {
                                VStack(spacing: 0) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.black)
                                        MuscleArtwork(view: muscle.bodyView, muscles: muscle.muscleGroups, centered: true)
                                            .padding(4)
                                    }
                                    .frame(height: 84)
                                    .frame(maxWidth: .infinity)

                                    Text(LanguageManager.t(muscle.translationKey))
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                        .foregroundColor(isSelected ? AppColors.accent : AppColors.text)
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 8)
                                }
                                .background(isSelected ? AppColors.positiveBg : AppColors.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("muscle-\(muscle.rawValue)")
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .accessibilityIdentifier("library-muscle-modal")
    }
}

struct LibraryFilterPill: View {
    let title: String
    let isSelected: Bool
    var equipment: EquipmentCategory? = nil
    let onTap: () -> Void
    let onClear: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    if let equipment {
                        EquipmentIcon(category: equipment, tint: isSelected ? equipmentSolidColor(categoryId: equipment.id) : AppColors.secondaryText)
                    }
                    Text(title)
                        .font(.system(size: labelSize, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? AppColors.accent : AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)

            if isSelected {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LanguageManager.t("library.clearFilter"))
            } else {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppColors.muted)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? AppColors.accent.opacity(0.6) : AppColors.border, lineWidth: 1)
        )
    }
}

struct LibraryFilterOption: View {
    let title: String
    let selected: Bool
    var equipment: EquipmentCategory? = nil
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13

    init(title: String, selected: Bool, equipment: EquipmentCategory? = nil, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.equipment = equipment
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let equipment {
                    EquipmentIcon(category: equipment, tint: selected ? equipmentSolidColor(categoryId: equipment.id) : AppColors.secondaryText)
                }
                Text(title).font(.system(size: labelSize, weight: selected ? .semibold : .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? AppColors.accent : AppColors.secondaryText)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? AppColors.accent : AppColors.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
