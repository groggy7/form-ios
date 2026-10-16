import SwiftUI

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
    @State private var pendingTemplate: Program?
    @State private var recoveryChecked = false
    @State private var creatingCopy = false
    @State private var conflictDraft: ProgramBuilderDraft?
    @State private var applyOnSave = false
    @State private var saveError: String?
    @State private var removalUndo: ProgramRemovalUndo?
    @State private var sharingItem: ProgramShareItem?
    var onDismiss: () -> Void

    public init(store: AppStore, program: Program? = nil, template: Program? = nil, onDismiss: @escaping () -> Void) {
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
    }

    private var isDirty: Bool { program != original || ((isNew || creatingCopy) && (!program.name.isEmpty || !program.workouts.isEmpty || !program.description.isEmpty || !program.guidelines.isEmpty)) }
    private var validationMessage: String? {
        if (isNew || creatingCopy) && store.state.programs.count >= ProgramEditing.maxPrograms { return LanguageManager.t("builder.programLimit") }
        if !isNew && !creatingCopy && store.state.programs.first(where: { $0.id == original.id }) != original { return LanguageManager.t("builder.draftConflict") }
        do { try ProgramEditing.validate(program, original: original, editingTitles: false); return nil }
        catch { return error.localizedDescription }
    }
    private var needsCover: Bool { (isNew || creatingCopy) && program.coverId == nil }
    private var canSave: Bool { validationMessage == nil && !needsCover }
    private var incompleteDays: Int { program.workouts.filter { $0.exercises.isEmpty }.count }

    public var body: some View {
        let _ = themeManager.currentTheme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    details
                    if isNew {
                        BuilderActionButton("builder.startTemplate", systemImage: "doc.on.doc") { showTemplates = true }
                    }
                    overview
                    HStack {
                        Text(LanguageManager.t("builder.trainingDays")).font(.headline)
                        Spacer()
                        Text(LanguageManager.t("builder.dayCount", ["count": program.workouts.count])).font(.caption).foregroundStyle(AppColors.muted)
                    }
                    if program.workouts.isEmpty {
                        BuilderSurface {
                            Text(LanguageManager.t("builder.noDays")).font(.headline)
                            Text(LanguageManager.t("builder.noDaysHint")).font(.subheadline).foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    ForEach(program.workouts.sorted { $0.day < $1.day }) { workout in
                        BuilderWorkoutCard(workout: workout, expanded: expandedIDs.contains(workout.id),
                            onToggle: { if !expandedIDs.insert(workout.id).inserted { expandedIDs.remove(workout.id) } },
                            onEdit: { editingWorkout = BuilderWorkoutContext(workout: workout, isNew: false) },
                            onAdd: { pickerWorkout = workout },
                            onEditExercise: { editingExercise = BuilderExerciseContext(workoutID: workout.id, exercise: $0) },
                            onMove: { moveExercise(workout.id, $0, $1) },
                            onRemove: { removeExercise(workout.id, $0) })
                    }
                    if program.workouts.count < 7 {
                        BuilderActionButton("builder.addTrainingDay", systemImage: "plus") {
                            let day = (1...7).first { day in !program.workouts.contains { $0.day == day } } ?? 1
                            editingWorkout = BuilderWorkoutContext(workout: Workout(day: day, title: ""), isNew: true)
                        }
                    }
                    if incompleteDays > 0 {
                        Text(LanguageManager.t("builder.incompleteDays", ["count": incompleteDays])).font(.caption).foregroundStyle(AppColors.muted)
                    }
                    if let message = saveError ?? validationMessage {
                        Text(message).font(.caption).foregroundStyle(AppColors.danger).accessibilityIdentifier("program-validation")
                    }
                }.padding(20)
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
                        if let index = program.workouts.firstIndex(where: { $0.id == context.workout.id }) { removalUndo = .workout(program.workouts[index], index); program.workouts.remove(at: index) }
                    },
                    onCopy: context.isNew ? nil : { workout, day in
                        let copy = ProgramEditing.copyWorkout(workout, day: day)
                        program.workouts.append(copy); expandedIDs.insert(copy.id)
                    })
            }
            .sheet(item: $pickerWorkout) { workout in
                AddExercisePickerSheet(catalogue: store.exerciseCatalogue, existing: workout.exercises,
                    defaultRest: store.defaultRestSeconds) { selected in
                    guard let index = program.workouts.firstIndex(where: { $0.id == workout.id }) else { return }
                    let existing = Set(program.workouts[index].exercises.map(ProgramEditing.selectionKey))
                    let additions = selected.filter { !existing.contains(ProgramEditing.selectionKey($0)) }
                    guard program.workouts[index].exercises.count + additions.count <= ProgramEditing.maxExercises else {
                        store.showErrorNotice(LanguageManager.t("builder.exerciseLimit")); return
                    }
                    program.workouts[index].exercises.append(contentsOf: additions)
                    pickerWorkout = nil
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
                NavigationStack {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(AppStore.loadBundledStarterPrograms()) { source in
                                BuilderActionButton(source.displayName, systemImage: "doc.on.doc") {
                                    showTemplates = false
                                    if isDirty { pendingTemplate = source } else { useTemplate(source) }
                                }
                            }
                        }.padding(20)
                    }.background(AppColors.background).navigationTitle(LanguageManager.t("builder.startTemplate"))
                        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(LanguageManager.t("modal.cancel")) { showTemplates = false }.foregroundStyle(AppColors.secondaryText) } }
                }
            }
            .confirmationDialog(LanguageManager.t("builder.replaceDraft"), isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }), titleVisibility: .visible) {
                Button(LanguageManager.t("builder.startTemplate"), role: .destructive) { if let source = pendingTemplate { useTemplate(source) }; pendingTemplate = nil }
                Button(LanguageManager.t("modal.cancel"), role: .cancel) { pendingTemplate = nil }
            }
            .sheet(item: $sharingItem) { ProgramShareSheet(url: $0.url) }
            .onAppear(perform: recoverDraft)
            .onChange(of: program) { _, _ in saveError = nil; persistDraft() }
        }
    }

    private var details: some View {
        BuilderSurface {
            Text(LanguageManager.t("builder.details")).font(.headline)
            Text(LanguageManager.t("programs.cover")).font(.caption).foregroundStyle(AppColors.secondaryText)
            if !isNew || program.coverId != nil {
                Image(ProgramCover.forProgram(program).assetName).resizable().aspectRatio(1.5, contentMode: .fit)
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            } else {
                Text(LanguageManager.t("programs.cover.none")).font(.subheadline).foregroundStyle(AppColors.muted)
                    .accessibilityIdentifier("program-cover-empty")
            }
            BuilderActionButton("programs.cover.choose", systemImage: "photo") { showCoverPicker = true }
            BuilderTextField("modal.program.name", text: $program.name, limit: 100)
                .accessibilityIdentifier("program-builder-name")
            BuilderTextField("modal.program.desc", text: $program.description, limit: 500, multiline: true)
            BuilderTextField("modal.program.notes", text: Binding(get: { program.guidelines.joined(separator: "\n") }, set: { program.guidelines = $0.components(separatedBy: "\n") }), limit: nil, multiline: true)
        }
    }

    private var overview: some View {
        BuilderSurface {
            Text(LanguageManager.t("builder.overview")).font(.headline)
            Text(LanguageManager.t("builder.overviewCounts", [
                "days": program.workouts.filter { !$0.exercises.isEmpty }.count,
                "exercises": program.workouts.reduce(0) { $0 + $1.exercises.count },
                "sets": program.workouts.flatMap(\.exercises).reduce(0) { $0 + WorkoutSessionUtils.initialSetCount(exercise: $1) }
            ])).font(.subheadline).foregroundStyle(AppColors.secondaryText)
            Text(LanguageManager.t("builder.defaultRest", ["seconds": store.defaultRestSeconds])).font(.caption).foregroundStyle(AppColors.muted)
            if isNew || creatingCopy {
                Toggle(LanguageManager.t("builder.applyOnSave"), isOn: $applyOnSave).tint(AppColors.accent)
                if applyOnSave && program.workouts.allSatisfy({ $0.exercises.isEmpty }) {
                    Text(LanguageManager.t("builder.emptyApplyWarning")).font(.caption).foregroundStyle(AppColors.muted)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if needsCover {
                Text(LanguageManager.t("builder.coverRequired")).font(.caption).foregroundStyle(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("program-cover-required")
            }
            if let undo = removalUndo {
                BuilderActionButton("builder.undoRemoval", systemImage: "arrow.uturn.backward") { if let restored = undo.restoring(program) { program = restored; removalUndo = nil } }.disabled(undo.restoring(program) == nil)
            }
            BuilderActionButton("programs.export", systemImage: "square.and.arrow.up") {
                do { sharingItem = ProgramShareItem(url: try ProgramFileCodec.shareURL(program, defaultRest: store.defaultRestSeconds)) }
                catch { saveError = error.localizedDescription; store.showErrorNotice(error.localizedDescription) }
            }.disabled(!canSave)
            Button(action: saveProgram) {
                Text(LanguageManager.t("modal.program.save")).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(AppColors.todaySelectionText).background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.5).accessibilityIdentifier("program-builder-save")
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
        removalUndo = .exercise(workoutID, program.workouts[w].exercises[e], e)
        program.workouts[w].exercises.remove(at: e)
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
        guard canSave else { return }
        var clean = program
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.description = clean.description.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.guidelines = clean.guidelines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        clean.workouts.sort { $0.day < $1.day }
        // Record the exact submitted value so recovery recognizes a commit interrupted before draft cleanup.
        ProgramBuilderDraftStore.save(ProgramBuilderDraft(program: clean, original: original, creatingCopy: creatingCopy), id: draftKey)
        let saved = (isNew || creatingCopy) ? store.addProgram(clean, activate: applyOnSave) : store.updateProgram(clean, expected: original)
        guard saved else { saveError = LanguageManager.t("builder.saveFailed"); return }
        ProgramBuilderDraftStore.clear(draftKey)
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
