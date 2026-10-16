import SwiftUI

struct BuilderSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }
}

struct BuilderTextField: View {
    let label: String
    @Binding var text: String
    let limit: Int?
    var multiline = false
    var originalText: String?
    init(_ label: String, text: Binding<String>, limit: Int?, multiline: Bool = false, originalText: String? = nil) {
        self.label = label; self._text = text; self.limit = limit; self.multiline = multiline; self.originalText = originalText
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LanguageManager.t(label)).font(.caption).foregroundStyle(AppColors.secondaryText)
            TextField(LanguageManager.t(label), text: $text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 2...6 : 1...1).font(.body).padding(12)
                .foregroundStyle(AppColors.text)
                .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tooLong ? AppColors.danger : AppColors.border, lineWidth: 1))
            if let limit {
                Text("\(characterCount)/\(limit)").font(.caption).foregroundStyle(tooLong ? AppColors.danger : AppColors.muted)
            }
        }
    }
    private var characterCount: Int { label == "modal.workout.name" ? Workout.titleLength(text) : text.utf16.count }
    private var tooLong: Bool { (limit.map { characterCount > $0 } ?? false) && (originalText == nil || text.trimmingCharacters(in: .whitespacesAndNewlines) != originalText?.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

struct BuilderActionButton: View {
    var label: String
    var systemImage: String
    var action: () -> Void
    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Label(LanguageManager.t(label), systemImage: systemImage).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 10)
                .foregroundStyle(AppColors.accent)
                .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct BuilderRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct BuilderWorkoutCard: View {
    var workout: Workout
    var expanded: Bool
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onAdd: () -> Void
    var onEditExercise: (Exercise) -> Void
    var onMove: (String, Int) -> Void
    var onRemove: (String) -> Void
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var draggedID: String?
    @State private var pointerY: CGFloat = 0
    @State private var grabOffset: CGFloat = 0
    private var coordinateName: String { "builder-exercises-\(workout.id)" }

    var body: some View {
        BuilderSurface {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        Text(LanguageManager.dayLabels[workout.day - 1]).font(.caption.weight(.bold))
                            .frame(width: 50, height: 50).foregroundStyle(AppColors.accent)
                            .background(AppColors.positiveBg, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title).font(.headline).foregroundStyle(AppColors.text)
                            Text(workout.displayFocus().isEmpty ? LanguageManager.t("builder.exerciseCount", ["count": workout.exercises.count]) : workout.displayFocus())
                                .font(.caption).foregroundStyle(AppColors.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(AppColors.muted)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint(LanguageManager.t(expanded ? "builder.collapseDay" : "builder.expandDay"))
                Button(action: onEdit) {
                    Image(systemName: "pencil").frame(width: 48, height: 48)
                }.foregroundStyle(AppColors.secondaryText).accessibilityLabel(LanguageManager.t("builder.editDay"))
            }
            if expanded {
                VStack(spacing: 9) {
                    ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseRow(exercise, index: index)
                    }
                    BuilderActionButton("builder.addExercises", systemImage: "plus", action: onAdd)
                        .disabled(workout.exercises.count >= ProgramEditing.maxExercises)
                    if workout.exercises.count >= ProgramEditing.maxExercises {
                        Text(LanguageManager.t("builder.exerciseLimit")).font(.caption).foregroundStyle(AppColors.muted)
                    }
                }.coordinateSpace(name: coordinateName)
                    .onPreferenceChange(BuilderRowFrames.self) { rowFrames = $0 }
            }
        }.accessibilityIdentifier("program-day-\(workout.day)")
    }

    private func exerciseRow(_ exercise: Exercise, index: Int) -> some View {
        HStack(spacing: 10) {
            MovementIcon(exerciseId: exercise.exerciseId, size: 56)
            Button { onEditExercise(exercise) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.text)
                    Text(exercise.displayPrescription).font(.caption).foregroundStyle(AppColors.purple)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48)
            }.buttonStyle(.plain)
            Menu {
                Button(LanguageManager.t("builder.editExercise")) { onEditExercise(exercise) }
                Button(LanguageManager.t("builder.moveEarlier")) { onMove(exercise.id, index - 1) }.disabled(index == 0)
                Button(LanguageManager.t("builder.moveLater")) { onMove(exercise.id, index + 1) }.disabled(index == workout.exercises.count - 1)
                Button(LanguageManager.t("builder.removeExercise"), role: .destructive) { onRemove(exercise.id) }
            } label: { Image(systemName: "ellipsis").frame(width: 48, height: 48).foregroundStyle(AppColors.secondaryText) }
                .accessibilityLabel(LanguageManager.t("builder.exerciseActions") + " " + exercise.displayName)
        }.padding(10).background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(draggedID == exercise.id ? AppColors.accent : AppColors.border, lineWidth: 1))
            .background(GeometryReader { geometry in
                Color.clear.preference(key: BuilderRowFrames.self, value: [exercise.id: geometry.frame(in: .named(coordinateName))])
            })
            .offset(y: draggedID == exercise.id ? pointerY - grabOffset - (rowFrames[exercise.id]?.minY ?? 0) : 0)
            .zIndex(draggedID == exercise.id ? 1 : 0)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateName)))
                .onChanged { value in
                    guard case .second(true, let drag?) = value else { return }
                    if draggedID == nil {
                        draggedID = exercise.id
                        grabOffset = drag.startLocation.y - (rowFrames[exercise.id]?.minY ?? drag.startLocation.y)
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    pointerY = drag.location.y
                    guard let current = workout.exercises.firstIndex(where: { $0.id == exercise.id }), let frame = rowFrames[exercise.id] else { return }
                    let center = pointerY - grabOffset + frame.height / 2
                    if current > 0, let previous = rowFrames[workout.exercises[current - 1].id], center < previous.midY { onMove(exercise.id, current - 1) }
                    else if current + 1 < workout.exercises.count, let next = rowFrames[workout.exercises[current + 1].id], center > next.midY { onMove(exercise.id, current + 1) }
                }.onEnded { _ in draggedID = nil })
    }
}

struct BuilderWorkoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    @State var workout: Workout
    var isNew: Bool
    var occupiedDays: Set<Int>
    var onSave: (Workout) -> Void
    var onRemove: (() -> Void)?
    var onCopy: ((Workout, Int) -> Void)?
    var catalogue: [ExerciseCatalogEntry] = []
    var defaultRest: Int = 90
    @State private var showExercises = false
    private let originalTitle: String
    init(workout: Workout, isNew: Bool, occupiedDays: Set<Int>, onSave: @escaping (Workout) -> Void, onRemove: (() -> Void)?, onCopy: ((Workout, Int) -> Void)?, catalogue: [ExerciseCatalogEntry] = [], defaultRest: Int = 90) {
        self.catalogue = catalogue; self.defaultRest = defaultRest
        self._workout = State(initialValue: workout); self.isNew = isNew; self.occupiedDays = occupiedDays
        self.onSave = onSave; self.onRemove = onRemove; self.onCopy = onCopy; self.originalTitle = workout.title
    }
    private var canSave: Bool { Workout.isValidTitle(workout.title, originalTitle: isNew ? nil : originalTitle) && !occupiedDays.contains(workout.day) }
    var body: some View {
        let _ = theme.currentTheme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BuilderSurface {
                        BuilderTextField("modal.workout.name", text: $workout.title, limit: Workout.maxTitleLength, originalText: isNew ? nil : originalTitle)
                        Text(LanguageManager.t("modal.workout.day")).font(.headline)
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(1...7, id: \.self) { day in
                                    Button { workout.day = day } label: {
                                        Text(LanguageManager.workoutDays[day - 1]).font(.subheadline)
                                            .padding(.horizontal, 12).frame(minHeight: 48)
                                            .background(workout.day == day ? AppColors.positiveBg : AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                                            .foregroundStyle(workout.day == day ? AppColors.accent : AppColors.secondaryText)
                                    }.buttonStyle(.plain).disabled(occupiedDays.contains(day))
                                }
                            }
                        }
                    }
                    BuilderSurface {
                        Text(LanguageManager.t("builder.chooseExercises")).font(.headline)
                        ForEach(workout.exercises) { exercise in
                            HStack(spacing: 10) {
                                Text(exercise.displayName).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) { workout.exercises.removeAll { $0.id == exercise.id } } label: {
                                    Image(systemName: "minus.circle").frame(width: 48, height: 48)
                                }.accessibilityLabel(LanguageManager.t("builder.removeExercise") + " " + exercise.displayName)
                            }
                        }
                        BuilderActionButton("builder.addExercises", systemImage: "plus") { showExercises = true }
                            .disabled(workout.exercises.count >= ProgramEditing.maxExercises)
                    }
                    BuilderSurface {
                        Text(LanguageManager.t("builder.mainFocus")).font(.headline)
                        Text(workout.displayFocus().isEmpty ? LanguageManager.t("builder.focusEmpty") : workout.displayFocus())
                            .font(.subheadline).foregroundStyle(AppColors.secondaryText)
                            .accessibilityIdentifier("workout-derived-focus")
                        Text(LanguageManager.t("builder.focusAutomatic", ["limit": Workout.maxFocusAreas]))
                            .font(.caption).foregroundStyle(AppColors.muted)
                    }
                    if let onCopy {
                        Menu {
                            ForEach((1...7).filter { !occupiedDays.contains($0) && $0 != workout.day }, id: \.self) { day in
                                Button(LanguageManager.workoutDays[day - 1]) { onCopy(workout, day); dismiss() }
                            }
                        } label: { Label(LanguageManager.t("builder.copyDay"), systemImage: "doc.on.doc").frame(maxWidth: .infinity, minHeight: 48) }
                        .disabled(occupiedDays.count >= 6 || !canSave)
                    }
                    if let onRemove {
                        Button(LanguageManager.t("modal.delete"), role: .destructive) { onRemove(); dismiss() }.frame(minHeight: 48)
                    }
                }.padding(20)
            }.background(AppColors.background)
                .navigationTitle(LanguageManager.t(isNew ? "modal.workout.titleAdd" : "modal.workout.titleEdit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(LanguageManager.t("modal.cancel")) { dismiss() }.foregroundStyle(AppColors.secondaryText) } }
                .safeAreaInset(edge: .bottom) {
                    BuilderActionButton("modal.workout.save", systemImage: "checkmark") {
                        workout.title = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(workout); dismiss()
                    }.disabled(!canSave).padding(20).background(AppColors.background)
                }
        }
        .sheet(isPresented: $showExercises) {
            AddExercisePickerSheet(catalogue: catalogue, existing: workout.exercises, defaultRest: defaultRest) { selected in
                let existing = Set(workout.exercises.map(ProgramEditing.selectionKey))
                let additions = selected.filter { !existing.contains(ProgramEditing.selectionKey($0)) }
                guard workout.exercises.count + additions.count <= ProgramEditing.maxExercises else { return }
                workout.exercises.append(contentsOf: additions)
                showExercises = false
            }
        }
    }
}

struct AddExercisePickerSheet: View {
    @ObservedObject private var theme = ThemeManager.shared
    let catalogue: [ExerciseCatalogEntry]
    let existing: [Exercise]
    let defaultRest: Int
    var onAdd: ([Exercise]) -> Void
    @State private var search = ""
    @State private var movement: MovementType?
    @State private var selected: [String] = []
    @State private var showCustom = false
    @Environment(\.dismiss) private var dismiss
    private var existingKeys: Set<String> { Set(existing.map(ProgramEditing.selectionKey)) }
    private var capacity: Int { max(0, ProgramEditing.maxExercises - existing.count) }
    private var filtered: [ExerciseCatalogEntry] {
        let query = ExerciseSearch.Query(search)
        return catalogue.compactMap { entry -> (ExerciseCatalogEntry, Int)? in
            guard movement == nil || movement == entry.exercise.resolvedMovement else { return nil }
            guard let score = ExerciseSearch.score(query, exercise: entry.exercise, localizedName: entry.exercise.displayName,
                category: "\(LanguageManager.t("category.\(entry.exercise.resolvedMovement.rawValue)")) \(entry.exercise.metadataSubtitle)") else { return nil }
            return (entry, score)
        }.sorted { $0.1 == $1.1 ? ExercisePriority.compare($0.0.exercise, $1.0.exercise) : $0.1 < $1.1 }.map { $0.0 }
    }
    var body: some View {
        let _ = theme.currentTheme
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            movementButton(nil)
                            ForEach(MovementType.allCases, id: \.rawValue) { movementButton($0) }
                        }
                    }
                    BuilderActionButton("builder.customExercise", systemImage: "plus") { showCustom = true }.disabled(capacity == 0)
                    ForEach(filtered) { entry in pickerRow(entry) }
                    if filtered.isEmpty { Text(LanguageManager.t("library.noResults")).foregroundStyle(AppColors.muted) }
                    if selected.count >= capacity && capacity > 0 { Text(LanguageManager.t("builder.exerciseLimit")).font(.caption).foregroundStyle(AppColors.muted) }
                }.padding(20)
            }.background(AppColors.background).searchable(text: $search)
                .navigationTitle(LanguageManager.t("builder.chooseExercises")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(LanguageManager.t("modal.cancel")) { dismiss() }.foregroundStyle(AppColors.secondaryText) } }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        let entries = selected.compactMap { key in catalogue.first { ProgramEditing.selectionKey($0.exercise) == key } }
                        onAdd(entries.map { ProgramEditing.picked($0.exercise, defaultRest: defaultRest) })
                    } label: { Text(LanguageManager.t("builder.addSelected", ["count": selected.count])).font(.headline).frame(maxWidth: .infinity, minHeight: 52) }
                    .buttonStyle(.borderedProminent).tint(AppColors.accent).disabled(selected.isEmpty).padding(20).background(AppColors.background)
                }
                .sheet(isPresented: $showCustom) {
                    ProgramExerciseEditorSheet(exercise: Exercise(name: "", sets: 3, reps: RepTarget(min: 8, max: 12), restSeconds: defaultRest), onSave: { onAdd([$0]) }, isNew: true)
                }
        }
    }
    private func movementButton(_ value: MovementType?) -> some View {
        Button { movement = value } label: {
            Text(LanguageManager.t(value.map { "category.\($0.rawValue)" } ?? "builder.allMovements")).font(.subheadline)
                .padding(.horizontal, 12).frame(minHeight: 48)
                .background(movement == value ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(movement == value ? AppColors.accent : AppColors.secondaryText)
        }.buttonStyle(.plain).accessibilityAddTraits(movement == value ? .isSelected : [])
    }
    private func pickerRow(_ entry: ExerciseCatalogEntry) -> some View {
        let key = ProgramEditing.selectionKey(entry.exercise)
        let added = existingKeys.contains(key)
        let isSelected = selected.contains(key)
        return Button {
            if isSelected { selected.removeAll { $0 == key } }
            else if selected.count < capacity { selected.append(key) }
        } label: {
            HStack(spacing: 12) {
                MovementIcon(exerciseId: entry.exercise.exerciseId, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.exercise.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(added ? AppColors.muted : AppColors.text)
                    Text(added ? LanguageManager.t("builder.alreadyAdded") : entry.exercise.metadataSubtitle).font(.caption).foregroundStyle(AppColors.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if added || isSelected { Image(systemName: "checkmark").foregroundStyle(isSelected ? AppColors.accent : AppColors.muted) }
            }.padding(10).frame(minHeight: 64)
                .background(isSelected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: 1))
        }.buttonStyle(.plain).disabled(added || (!isSelected && selected.count >= capacity))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProgramImportReview: View {
    let preview: ProgramImportPreview
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        let _ = theme.currentTheme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BuilderSurface {
                        Text(preview.incoming.name).font(.headline)
                        if preview.existing != nil { Text(LanguageManager.t("programs.importReplaceHint")).font(.subheadline).foregroundStyle(AppColors.secondaryText) }
                        ForEach(["added", "updated", "removed"], id: \.self) { kind in
                            Text(LanguageManager.t("programs.import" + kind.prefix(1).uppercased() + kind.dropFirst(), ["count": preview.changes.filter { $0.kind == kind }.count]))
                                .font(.subheadline).foregroundStyle(kind == "removed" ? AppColors.danger : AppColors.secondaryText)
                        }
                    }
                    ForEach(Array(preview.changes.enumerated()), id: \.offset) { _, change in
                        HStack {
                            Image(systemName: change.kind == "added" ? "plus" : change.kind == "removed" ? "minus" : "pencil")
                            Text(change.label).font(.subheadline)
                        }.foregroundStyle(change.kind == "removed" ? AppColors.danger : AppColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 13))
                    }
                }.padding(20)
            }.background(AppColors.background)
                .navigationTitle(LanguageManager.t("programs.importPreview")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(LanguageManager.t("modal.cancel")) { dismiss() }.foregroundStyle(AppColors.secondaryText) } }
                .safeAreaInset(edge: .bottom) {
                    BuilderActionButton("programs.importConfirm", systemImage: "square.and.arrow.down", action: onConfirm).padding(20).background(AppColors.background)
                }
        }
    }
}

struct BuilderCoverPicker: View {
    let programID: String
    @Binding var selection: String?
    var showAutomatic = true
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        let _ = theme.currentTheme
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if showAutomatic {
                        BuilderActionButton("programs.cover.automatic", systemImage: selection == nil ? "checkmark" : "photo") { selection = nil; dismiss() }
                            .accessibilityAddTraits(selection == nil ? .isSelected : [])
                    } else if selection != nil {
                        BuilderActionButton("programs.cover.remove", systemImage: "xmark") { selection = nil; dismiss() }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ProgramCover.allCases, id: \.rawValue) { cover in
                            Button { selection = cover.rawValue; dismiss() } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(cover.assetName).resizable().aspectRatio(1.5, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(LanguageManager.t("programs.cover." + cover.rawValue)).font(.subheadline).foregroundStyle(AppColors.text)
                                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                }.padding(8).background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selection == cover.rawValue ? AppColors.accent : AppColors.border, lineWidth: selection == cover.rawValue ? 2 : 1))
                            }.buttonStyle(.plain).accessibilityAddTraits(selection == cover.rawValue ? .isSelected : [])
                        }
                    }
                }.padding(20)
            }.background(AppColors.background).navigationTitle(LanguageManager.t("programs.cover.choose"))
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(LanguageManager.t("modal.cancel")) { dismiss() }.foregroundStyle(AppColors.secondaryText) } }
        }
    }
}
