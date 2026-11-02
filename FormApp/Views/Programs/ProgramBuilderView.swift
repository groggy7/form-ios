import SwiftUI
import UIKit

public struct ProgramBuilderView: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @ObservedObject var store: AppStore
    @State var program: Program
    let isNew: Bool
    private let initial: Program
    private let draftKey: String?
    @State private var original: Program
    @State private var expandedIDs: Set<String> = []
    @State private var editingWorkout: BuilderWorkoutContext?
    @State private var pickerWorkout: Workout?
    @State private var editingExercise: BuilderExerciseContext?
    @State private var showDiscard = false
    @State private var showCoverPicker = false
    @State private var showTemplates = false
    @State private var showDayPicker = false
    @State private var selectedNewDay: Int?
    @State private var pendingTemplate: Program?
    @State private var recoveryChecked = false
    @State private var creatingCopy = false
    @State private var conflictDraft: ProgramBuilderDraft?
    @State private var saveError: String?
    @State private var pendingAutomaticCoverID: String?
    @State private var saveAttempted = false
    @State private var validationAttempt = 0
    @State private var removalUndo: ProgramRemovalUndo?
    @State private var removalUndoToken = 0
    @State private var pendingNewDayID: String?
    @State private var optionalDetailsExpanded = false
    var onDismiss: () -> Void
    private var onDraftSave: ((Program) -> Bool)?
    private var draftCatalogue: [ExerciseCatalogEntry]?

    public init(store: AppStore, program: Program? = nil, template: Program? = nil, draftCatalogue: [ExerciseCatalogEntry]? = nil, onDraftSave: ((Program) -> Bool)? = nil, onDismiss: @escaping () -> Void) {
        self.store = store
        let initial = program ?? template.map { source in
            var copy = ProgramEditing.copyProgram(source)
            copy.coverId = ProgramCover.forProgram(source).rawValue
            return copy
        } ?? Program(name: "")
        self.initial = initial
        self._program = State(initialValue: initial)
        self._original = State(initialValue: initial)
        self.isNew = program == nil
        self.draftKey = template.map { "copy:" + $0.id } ?? program?.id
        self.onDismiss = onDismiss
        self.onDraftSave = onDraftSave
        self.draftCatalogue = draftCatalogue
    }

    private var isDirty: Bool { program != original || ((isNew || creatingCopy) && (!program.name.isEmpty || !program.workouts.isEmpty || !program.description.isEmpty || !program.guidelines.isEmpty)) }
    private var formError: String? {
        if onDraftSave != nil { return nil }
        if (isNew || creatingCopy) && store.state.programs.count >= ProgramEditing.maxPrograms { return LanguageManager.t("builder.programLimit") }
        if !isNew && !creatingCopy && store.state.programs.first(where: { $0.id == original.id }) != original { return LanguageManager.t("builder.draftConflict") }
        return nil
    }
    private var validationMessage: String? {
        if let formError { return formError }
        do { try ProgramEditing.validate(program, original: original, editingTitles: false); return nil }
        catch { return error.localizedDescription }
    }
    private var displayedCover: ProgramCover? { !isNew || program.coverId != nil ? ProgramCover.forProgram(program) : nil }
    private var canSave: Bool { validationMessage == nil }
    private var nameInvalid: Bool { program.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || program.name.utf16.count > 100 }
    private var descriptionInvalid: Bool { program.description.utf16.count > 500 }
    private var notesInvalid: Bool { program.guidelines.count > 50 || program.guidelines.contains { $0.utf16.count > 500 } }
    private var trainingError: String? { formError == nil && !nameInvalid && !descriptionInvalid && !notesInvalid ? validationMessage : nil }
    private var firstInvalidField: String {
        if formError != nil { return "program-details" }
        if nameInvalid { return "program-name" }
        if descriptionInvalid { return "program-description" }
        if notesInvalid { return "program-notes" }
        return "program-training-days"
    }
    private var incompleteDays: Int { program.workouts.filter { $0.exercises.isEmpty }.count }

    public var body: some View {
        let _ = themeManager.currentTheme
        NavigationStack {
            editorContent
            .confirmationDialog(LanguageManager.t("builder.unsavedTitle"), isPresented: $showDiscard, titleVisibility: .visible) {
                Button(LanguageManager.t("builder.keepDraft")) { persistDraft(); onDismiss() }
                Button(LanguageManager.t("builder.discard"), role: .destructive) { ProgramBuilderDraftStore.clear(draftKey); onDismiss() }
                Button(LanguageManager.t("builder.continueEditing"), role: .cancel) { }
            } message: { Text(LanguageManager.t("builder.unsavedMessage")) }
            .alert(LanguageManager.t("builder.unsavedTitle"), isPresented: Binding(get: { conflictDraft != nil }, set: { if !$0 { conflictDraft = nil } })) {
                Button(LanguageManager.t("builder.copyDraft")) {
                    if let retained = conflictDraft {
                        var copy = ProgramEditing.copyProgram(retained.program)
                        copy.coverId = ProgramCover.forProgram(retained.program).rawValue
                        program = copy; original = copy; creatingCopy = true
                    }
                    conflictDraft = nil; persistDraft()
                }
                Button(LanguageManager.t("builder.discard"), role: .destructive) { ProgramBuilderDraftStore.clear(draftKey); conflictDraft = nil }
                Button(LanguageManager.t("builder.keepDraft"), role: .cancel) { onDismiss() }
            } message: { Text(LanguageManager.t("builder.conflictDraftMessage")) }
            .sheet(item: $editingWorkout) { context in
                BuilderWorkoutEditor(workout: context.workout, isNew: context.isNew,
                    occupiedDays: Set(program.workouts.filter { $0.id != context.workout.id }.map(\.day)),
                    onSave: { updated in
                        if let index = program.workouts.firstIndex(where: { $0.id == updated.id }) { program.workouts[index] = updated }
                        else { program.workouts.append(updated); expandedIDs.insert(updated.id) }
                    },
                    onRemove: context.isNew ? nil : {
                        if let index = program.workouts.firstIndex(where: { $0.id == context.workout.id }) { offerUndo(.workout(program.workouts[index], index)); program.workouts.remove(at: index) }
                    },
                    onCopy: context.isNew ? nil : { workout, day in
                        let copy = ProgramEditing.copyWorkout(workout, day: day)
                        program.workouts.append(copy); expandedIDs.insert(copy.id)
                    })
            }
            .sheet(item: $pickerWorkout, onDismiss: dropPendingEmptyDay) { workout in
                AddExercisePickerSheet(catalogue: draftCatalogue ?? store.exerciseCatalogue, existing: workout.exercises,
                    defaultRest: store.defaultRestSeconds, workout: workout) { selected in
                    guard let index = program.workouts.firstIndex(where: { $0.id == workout.id }) else { return }
                    let existing = Set(program.workouts[index].exercises.map(ProgramEditing.selectionKey))
                    let additions = selected.filter { !existing.contains(ProgramEditing.selectionKey($0)) }
                    guard program.workouts[index].exercises.count + additions.count <= ProgramEditing.maxExercises else {
                        store.showErrorNotice(LanguageManager.t("builder.exerciseLimit")); return
                    }
                    program.workouts[index].exercises.append(contentsOf: additions)
                    pendingNewDayID = nil
                    pickerWorkout = nil
                }
            }
            .sheet(isPresented: $showDayPicker, onDismiss: {
                if let day = selectedNewDay {
                    selectedNewDay = nil
                    addTrainingDay(day: day)
                }
            }) {
                BuilderTrainingDayPicker(occupiedDays: Set(program.workouts.map(\.day))) { day in
                    selectedNewDay = day
                    showDayPicker = false
                }
            }
            .sheet(item: $editingExercise) { context in
                ProgramExerciseEditorSheet(exercise: context.exercise, onSave: { updated in
                    guard let w = program.workouts.firstIndex(where: { $0.id == context.workoutID }),
                          let e = program.workouts[w].exercises.firstIndex(where: { $0.id == context.exercise.id }) else { return }
                    program.workouts[w].exercises[e] = updated
                }, onDelete: { removeExercise(context.workoutID, context.exercise.id) })
            }
            .sheet(isPresented: $showCoverPicker) { BuilderCoverPicker(programID: program.id, selection: $program.coverId, showAutomatic: !isNew && !creatingCopy) }
            .sheet(isPresented: $showTemplates) {
                BuilderTemplatePicker(templates: AppStore.loadBundledStarterPrograms()) { source in
                    showTemplates = false
                    if isDirty { pendingTemplate = source } else { useTemplate(source) }
                }
            }
            .confirmationDialog(LanguageManager.t("builder.replaceDraft"), isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }), titleVisibility: .visible) {
                Button(LanguageManager.t("builder.startTemplate"), role: .destructive) { if let source = pendingTemplate { useTemplate(source) }; pendingTemplate = nil }
                Button(LanguageManager.t("modal.cancel"), role: .cancel) { pendingTemplate = nil }
            }
            .onAppear(perform: recoverDraft)
            .onChange(of: program) { _, _ in saveError = nil; persistDraft() }
            .task(id: removalUndoToken) {
                guard removalUndo != nil else { return }
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled { removalUndo = nil }
            }
        }
    }

    private var editorContent: some View {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isNew {
                            BuilderActionButton("builder.startTemplate", systemImage: "doc.on.doc") { showTemplates = true }
                                .accessibilityIdentifier("program-start-template")
                        }
                        details
                        VStack(alignment: .leading, spacing: 4) {
                            if saveAttempted, let trainingError {
                                Text(trainingError).appFont(.caption).foregroundStyle(AppColors.danger).accessibilityIdentifier("program-validation")
                            }
                            HStack {
                                Text(LanguageManager.t("builder.trainingDays")).appFont(.headline)
                                Spacer()
                                Text(LanguageManager.t("builder.dayCount", ["count": program.workouts.count])).appFont(.caption).foregroundStyle(AppColors.muted)
                            }
                            if !program.workouts.isEmpty {
                                Text(LanguageManager.t("builder.summaryCounts", [
                                    "exercises": program.workouts.reduce(0) { $0 + $1.exercises.count },
                                    "sets": program.workouts.flatMap(\.exercises).reduce(0) { $0 + WorkoutSessionUtils.initialSetCount(exercise: $1) }
                                ])).appFont(.caption).foregroundStyle(AppColors.muted).accessibilityIdentifier("program-summary")
                            }
                        }.id("program-training-days")
                        if program.workouts.isEmpty {
                            BuilderSurface {
                                Text(LanguageManager.t("builder.noDays")).appFont(.headline)
                                Text(LanguageManager.t("builder.noDaysHint")).appFont(.subheadline).foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        ForEach(program.workouts.sorted { $0.day < $1.day }) { workout in
                            BuilderWorkoutCard(workout: workout, expanded: expandedIDs.contains(workout.id),
                                onToggle: { if !expandedIDs.insert(workout.id).inserted { expandedIDs.remove(workout.id) } },
                                onEdit: { editingWorkout = BuilderWorkoutContext(workout: workout, isNew: false) },
                                onAdd: { pickerWorkout = workout },
                                onEditExercise: { editingExercise = BuilderExerciseContext(workoutID: workout.id, exercise: $0) },
                                onMove: { moveExercise(workout.id, $0, $1) },
                                onRemove: { removeExercise(workout.id, $0) },
                                onPair: { exerciseId in
                                    if let index = program.workouts.firstIndex(where: { $0.id == workout.id }) {
                                        program.workouts[index] = Supersets.toggled(program.workouts[index], exerciseId)
                                    }
                                })
                        }
                        if program.workouts.count < 7 {
                            BuilderActionButton("builder.addTrainingDay", systemImage: "plus") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                showDayPicker = true
                            }
                                .accessibilityIdentifier("program-add-day")
                        }
                        if incompleteDays > 0 {
                            Text(LanguageManager.t("builder.incompleteDays", ["count": incompleteDays])).appFont(.caption).foregroundStyle(AppColors.muted)
                        }
                    }.padding(20)
                }
                .onChange(of: validationAttempt) { _, _ in
                    let target = firstInvalidField
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation { reader.scrollTo(target, anchor: .top) }
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t(isNew || creatingCopy ? "modal.program.titleAdd" : "modal.program.titleEdit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LanguageManager.t("modal.cancel"), action: requestClose).foregroundStyle(AppColors.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .interactiveDismissDisabled(isDirty)
    }

    private var details: some View {
        BuilderSurface {
            Text(LanguageManager.t("builder.details")).appFont(.headline)
            if saveAttempted, let formError {
                Text(formError).appFont(.caption).foregroundStyle(AppColors.danger).accessibilityIdentifier("program-validation")
            }
            BuilderTextField("modal.program.name", text: $program.name, limit: 100,
                errorMessage: saveAttempted && nameInvalid ? LanguageManager.t("builder.nameError") : nil, showsLengthError: saveAttempted)
                .accessibilityIdentifier("program-builder-name").id("program-name")
            VStack(alignment: .leading, spacing: 12) {
                if let cover = displayedCover {
                    let label = LanguageManager.t("programs.cover.selected", ["name": LanguageManager.t("programs.cover." + cover.rawValue)])
                    Button { showCoverPicker = true } label: {
                        HStack(spacing: 8) {
                            Text(label).appFont(.caption).foregroundStyle(AppColors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(AppColors.accent)
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(label).accessibilityHint(LanguageManager.t("programs.cover.change"))
                        .accessibilityIdentifier("program-cover-change")
                    Image(cover.assetName).resizable().aspectRatio(1.5, contentMode: .fit)
                        .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                } else {
                    Text(LanguageManager.t("programs.cover")).appFont(.caption).foregroundStyle(AppColors.secondaryText)
                        .accessibilityIdentifier("program-cover-label")
                    BuilderActionButton("programs.cover.choose", systemImage: "photo") { showCoverPicker = true }
                        .accessibilityIdentifier("program-cover-choose")
                }
            }.id("program-cover")
            Button { withAnimation(.easeInOut(duration: 0.2)) { optionalDetailsExpanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "text.alignleft").foregroundStyle(AppColors.secondaryText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("builder.optionalDetails")).appFont(.subheadline, weight: .medium).foregroundStyle(AppColors.text)
                        Text(LanguageManager.t("builder.optional")).appFont(.caption2).foregroundStyle(AppColors.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: optionalDetailsExpanded ? "chevron.up" : "chevron.down").foregroundStyle(AppColors.muted)
                }.padding(.horizontal, 12).frame(minHeight: 54).contentShape(Rectangle())
                    .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
            }.buttonStyle(.plain)
                .accessibilityHint(LanguageManager.t(optionalDetailsExpanded ? "builder.hideOptionalDetails" : "builder.showOptionalDetails"))
                .accessibilityIdentifier("program-optional-details")
            if optionalDetailsExpanded {
                BuilderTextField("modal.program.desc", text: $program.description, limit: 500, multiline: true,
                    errorMessage: saveAttempted && descriptionInvalid ? LanguageManager.t("builder.descriptionError") : nil, showsLengthError: saveAttempted)
                    .id("program-description")
                BuilderTextField("modal.program.notes", text: Binding(get: { program.guidelines.joined(separator: "\n") }, set: { program.guidelines = $0.components(separatedBy: "\n") }), limit: nil, multiline: true,
                    errorMessage: saveAttempted && notesInvalid ? LanguageManager.t("builder.notesError") : nil, showsLengthError: saveAttempted)
                    .id("program-notes")
            }
        }.id("program-details")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let undo = removalUndo {
                HStack(spacing: 12) {
                    Text(LanguageManager.t({ if case .workout = undo { return "builder.dayRemoved" }; return "builder.exerciseRemoved" }()))
                        .appFont(.subheadline).foregroundStyle(AppColors.text).frame(maxWidth: .infinity, alignment: .leading)
                    Button(LanguageManager.t("builder.undo")) { if let restored = undo.restoring(program) { program = restored }; removalUndo = nil }
                        .appFont(.subheadline, weight: .semibold).foregroundStyle(AppColors.accent).frame(minWidth: 48, minHeight: 48)
                        .disabled(undo.restoring(program) == nil).accessibilityLabel(LanguageManager.t("builder.undoRemoval"))
                }.padding(.horizontal, 14).background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                    .accessibilityIdentifier("program-undo-removal")
            }
            if let saveError {
                Text(saveError).appFont(.caption).foregroundStyle(AppColors.danger).accessibilityIdentifier("program-validation")
            }
            Button(action: saveProgram) {
                Text(LanguageManager.t("modal.program.save")).appFont(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(AppColors.todaySelectionText).background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("program-builder-save")
        }.padding(.horizontal, 20).padding(.vertical, 10).background(AppColors.background)
    }

    private func moveExercise(_ workoutID: String, _ exerciseID: String, _ target: Int) {
        guard let w = program.workouts.firstIndex(where: { $0.id == workoutID }),
              let from = program.workouts[w].exercises.firstIndex(where: { $0.id == exerciseID }),
              program.workouts[w].exercises.indices.contains(target), from != target else { return }
        let exercise = program.workouts[w].exercises.remove(at: from)
        program.workouts[w].exercises.insert(exercise, at: target)
    }
    private func removeExercise(_ workoutID: String, _ exerciseID: String) {
        guard let w = program.workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        guard let e = program.workouts[w].exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        offerUndo(.exercise(workoutID, program.workouts[w].exercises[e], e))
        program.workouts[w].exercises.remove(at: e)
    }
    private func offerUndo(_ undo: ProgramRemovalUndo) { removalUndo = undo; removalUndoToken += 1 }
    private func addTrainingDay(day: Int) {
        guard let workout = ProgramEditing.newDay(for: program, day: day) else { return }
        program.workouts.append(workout); expandedIDs.insert(workout.id)
        pendingNewDayID = workout.id; pickerWorkout = workout
    }
    /// Cancelling the library for a day that was just added leaves no empty placeholder behind.
    private func dropPendingEmptyDay() {
        guard let pending = pendingNewDayID else { return }
        pendingNewDayID = nil
        if let index = program.workouts.firstIndex(where: { $0.id == pending }), program.workouts[index].exercises.isEmpty {
            program.workouts.remove(at: index); expandedIDs.remove(pending)
        }
    }
    private func useTemplate(_ source: Program) {
        var copy = ProgramEditing.copyProgram(source)
        copy.coverId = ProgramCover.forProgram(source).rawValue
        program = copy; original = copy; expandedIDs = []
        ProgramBuilderDraftStore.save(ProgramBuilderDraft(program: copy, original: copy), id: draftKey)
    }
    private func requestClose() { if isDirty { showDiscard = true } else { onDismiss() } }
    private func recoverDraft() {
        guard !recoveryChecked else { return }; recoveryChecked = true
        guard let draft = ProgramBuilderDraftStore.load(draftKey) else { return }
        if store.state.programs.contains(where: { $0 == draft.program }) { ProgramBuilderDraftStore.clear(draftKey); return }
        guard isNew || draft.creatingCopy || draft.original == initial else { conflictDraft = draft; return }
        creatingCopy = draft.creatingCopy
        program = draft.program
        original = draft.original ?? initial
        store.showNotice(LanguageManager.t("builder.draftRecovered"))
    }
    private func persistDraft() {
        guard recoveryChecked && conflictDraft == nil else { return }
        if isDirty { ProgramBuilderDraftStore.save(ProgramBuilderDraft(program: program, original: original, creatingCopy: creatingCopy), id: draftKey) }
        else { ProgramBuilderDraftStore.clear(draftKey) }
    }
    private func saveProgram() {
        guard canSave else {
            saveAttempted = true
            if descriptionInvalid || notesInvalid { optionalDetailsExpanded = true }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            validationAttempt += 1
            return
        }
        var clean = program
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.description = clean.description.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.guidelines = clean.guidelines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        clean.workouts.sort { $0.day < $1.day }
        let autoSelectedCover = (isNew || creatingCopy) && clean.coverId == nil
        if autoSelectedCover {
            let coverID = pendingAutomaticCoverID ?? (ProgramCover.allCases.randomElement() ?? .fullBody).rawValue
            pendingAutomaticCoverID = coverID
            clean.coverId = coverID
        }
        if let onDraftSave {
            guard onDraftSave(clean) else { saveError = LanguageManager.t("setup.edit.invalid"); return }
            ProgramBuilderDraftStore.clear(draftKey)
            onDismiss()
            return
        }
        // Record the exact submitted value so recovery recognizes a commit interrupted before draft cleanup.
        ProgramBuilderDraftStore.save(ProgramBuilderDraft(program: clean, original: original, creatingCopy: creatingCopy), id: draftKey)
        let saved = (isNew || creatingCopy) ? store.addProgram(clean, activate: false) : store.updateProgram(clean, expected: original)
        guard saved else { saveError = LanguageManager.t("builder.saveFailed"); return }
        ProgramBuilderDraftStore.clear(draftKey)
        if autoSelectedCover { store.showNotice(LanguageManager.t("notice.programCoverAutoSelected")) }
        onDismiss()
    }
}

struct BuilderWorkoutContext: Identifiable { var workout: Workout; var isNew: Bool; var id: String { workout.id } }
struct BuilderExerciseContext: Identifiable { var workoutID: String; var exercise: Exercise; var id: String { exercise.id } }

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [text], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
