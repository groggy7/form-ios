import SwiftUI

struct TrainingSetupView: View {
    @ObservedObject var store: AppStore
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var theme = ThemeManager.shared
    let completeSetup: Bool
    var onClose: () -> Void
    var onSkip: (() -> Void)?
    @State private var profile: TrainingProfile
    @State private var step: Int
    @State private var programID: String
    @State private var editedProgram: Program?
    @State private var search = ""
    @State private var excludedSearch = ""
    @State private var error: String?
    @State private var editing = false

    init(store: AppStore, completeSetup: Bool = true, onClose: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.store = store; self.completeSetup = completeSetup; self.onClose = onClose; self.onSkip = onSkip
        let draft = TrainingSetupStore.draft()
        var initial = TrainingProfile()
        initial.equipment = TrainingCatalog.bundled?.presets["commercial_gym"] ?? []
        _profile = State(initialValue: draft?.profile ?? TrainingSetupStore.profile() ?? initial)
        _step = State(initialValue: min(max(draft?.step ?? 1, 1), 6))
        _programID = State(initialValue: draft?.programId ?? UUID().uuidString)
        _editedProgram = State(initialValue: draft?.program)
    }
    private var generated: GeneratedTrainingPlan? { try? TrainingSetupStore.generate(profile, id: programID) }
    private var program: Program? { editedProgram ?? generated?.program }
    private var canContinue: Bool { TrainingCatalog.bundled != nil && (step == 3 ? profile.equipmentConfirmed : (step != 6 || program != nil)) }
    private var title: String {
        switch step {
        case 1: return "onboarding.goal.title"
        case 2: return "onboarding.experience.title"
        case 3: return "setup.equipment.title"
        case 4: return "onboarding.days.title"
        case 5: return "setup.duration.title"
        default: return "setup.preview.title"
        }
    }
    var body: some View {
        let _ = theme.currentTheme
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: back) { Image(systemName: "arrow.left").frame(width: 48, height: 48) }
                    .accessibilityLabel(LanguageManager.t("onboarding.back")).accessibilityIdentifier("onboarding-back")
                ProgressView(value: Double(step), total: 6).tint(AppColors.accent)
                if let onSkip { Button(LanguageManager.t("onboarding.skip"), action: onSkip).foregroundStyle(AppColors.secondaryText).frame(minHeight: 48) }
            }.padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LanguageManager.t(title)).font(.system(size: 24, weight: .bold)).foregroundStyle(AppColors.text)
                    if let catalog = TrainingCatalog.bundled {
                        switch step {
                        case 1:
                            ForEach(OnboardingGoal.allCases, id: \.rawValue) { goal in
                                choice(LanguageManager.t("onboarding.goal.\(goal.rawValue).title"), selected: profile.goal == goal.rawValue) { profile.goal = goal.rawValue }
                            }
                        case 2:
                            ForEach(OnboardingExperience.allCases, id: \.rawValue) { experience in
                                choice(LanguageManager.t("onboarding.experience.\(experience.rawValue).title"), selected: profile.experience == experience.rawValue,
                                    hint: LanguageManager.t("onboarding.experience.\(experience.rawValue).desc")) { profile.experience = experience.rawValue; profile.advancedLifts = false }
                            }
                        case 3: equipment(catalog)
                        case 4: days
                        case 5: preferences(catalog)
                        default:
                            if let program { preview(program, catalog: catalog) }
                            else { Text(LanguageManager.t("setup.generationFailed")).foregroundStyle(AppColors.danger) }
                        }
                    } else { Text(LanguageManager.t("setup.generationFailed")).foregroundStyle(AppColors.danger) }
                    if let error { Text(error).foregroundStyle(AppColors.danger) }
                }.padding(20).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
            }.id(step)
            Button(action: next) {
                Text(LanguageManager.t(step < 6 ? "onboarding.next" : "setup.start"))
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(AppColors.background)
                    .frame(maxWidth: .infinity).frame(minHeight: 52).padding(.vertical, 4)
                    .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.45)
                .padding(20).accessibilityIdentifier("setup-next")
        }
        .background(AppColors.background).foregroundStyle(AppColors.text)
        .onAppear(perform: persist)
        .onChange(of: profile) { _, _ in editedProgram = nil; error = nil; persist() }
        .onChange(of: step) { _, _ in persist() }
        .onChange(of: editedProgram) { _, _ in persist() }
        .sheet(isPresented: $editing) {
            if let program, let catalog = TrainingCatalog.bundled {
                let eligible = TrainingPlanGenerator.eligible(profile, catalog: catalog)
                ProgramBuilderView(store: store, program: program,
                    draftCatalogue: store.exerciseCatalogue.filter { entry in eligible.contains { $0.id == entry.exercise.exerciseId } },
                    onDraftSave: { updated in
                        guard !updated.workouts.isEmpty, updated.workouts.allSatisfy({ !$0.exercises.isEmpty }),
                              updated.workouts.flatMap(\.exercises).allSatisfy({ ex in eligible.contains { $0.id == ex.exerciseId } }) else { return false }
                        editedProgram = updated; return true
                    }, onDismiss: { editing = false })
            }
        }
    }
    @ViewBuilder private func equipment(_ catalog: TrainingCatalog) -> some View {
        Text(LanguageManager.t("setup.equipment.hint")).foregroundStyle(AppColors.secondaryText)
        ForEach(["commercial_gym", "machines_only", "home"], id: \.self) { location in
            choice(LanguageManager.t("setup.location.\(location)"), selected: profile.location == location, tag: "setup-location-\(location)") {
                profile.location = location; profile.equipment = catalog.presets[location] ?? []; profile.equipmentConfirmed = false
            }
        }
        choice(LanguageManager.t("setup.equipment.none"), selected: profile.equipment.isEmpty && profile.equipmentConfirmed, tag: "setup-no-equipment") {
            profile.equipment = []; profile.equipmentConfirmed = true
        }
        if profile.location != "home" && !profile.equipment.isEmpty {
            choice(LanguageManager.t("setup.equipment.confirm"), selected: profile.equipmentConfirmed, multiple: true) { profile.equipmentConfirmed.toggle() }
        }
        TextField("", text: $search, prompt: Text(LanguageManager.t("setup.equipment.search")).foregroundStyle(AppColors.muted))
            .textFieldStyle(.plain).padding(14).background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border)).accessibilityLabel(LanguageManager.t("setup.equipment.search"))
        ForEach(["weights", "supports", "pulling", "bands", "accessories", "machines"], id: \.self) { group in
            let items = catalog.equipment.filter { $0.group == group && (search.isEmpty || LanguageManager.t("setup.gear.\($0.id)").localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)) }
            if !items.isEmpty {
                Text(LanguageManager.t("setup.group.\(group)")).font(.headline).foregroundStyle(AppColors.secondaryText)
                ForEach(items, id: \.id) { item in
                    choice(LanguageManager.t("setup.gear.\(item.id)"), selected: profile.equipment.contains(item.id), multiple: true, tag: "setup-gear-\(item.id)") {
                        toggle(item.id, in: &profile.equipment); profile.equipmentConfirmed = true
                    }
                    equipmentDetails(item.id)
                }
            }
        }
    }
    @ViewBuilder private func equipmentDetails(_ id: String) -> some View {
        if profile.equipment.contains(id) {
            if id == "dumbbells" {
                choice(LanguageManager.t("setup.dumbbell.pair"), selected: profile.dumbbellPair, multiple: true) { profile.dumbbellPair.toggle() }
                TrainingLoadField(key: "setup.dumbbell.max", value: $profile.maxDumbbellKg)
            }
            if ["barbell", "ez-bar", "trap-bar"].contains(id) && id == profile.equipment.first(where: { ["barbell", "ez-bar", "trap-bar"].contains($0) }) {
                TrainingLoadField(key: "setup.barbell.max", value: $profile.maxBarbellKg)
            }
            if id == "pull-up-bar" {
                Text(LanguageManager.t("setup.pullUps.title")).font(.headline)
                ForEach([0, 1, 3, 8], id: \.self) { count in
                    choice(LanguageManager.t("setup.pullUps.\(count)"), selected: profile.pullUpReps == count) { profile.pullUpReps = count }
                }
            }
        }
    }
    private var days: some View {
        Group {
            Text(LanguageManager.t("setup.days.hint")).foregroundStyle(AppColors.secondaryText)
            ForEach(OnboardingFrequency.allCases, id: \.rawValue) { count in
                choice(LanguageManager.t("setup.days.count", ["count": count.rawValue]), selected: profile.selectedDays.count == count.rawValue) { profile.selectedDays = count.defaultWeekdays }
            }
            ForEach(1...7, id: \.self) { day in
                choice(LanguageManager.workoutDays[day - 1], selected: profile.selectedDays.contains(day), multiple: true, tag: "setup-day-\(day)") {
                    if profile.selectedDays.contains(day) && profile.selectedDays.count > 2 { profile.selectedDays.removeAll { $0 == day } }
                    else if !profile.selectedDays.contains(day) && profile.selectedDays.count < 6 { profile.selectedDays.append(day); profile.selectedDays.sort() }
                }
            }
        }
    }
    @ViewBuilder private func preferences(_ catalog: TrainingCatalog) -> some View {
        ForEach([20, 30, 45, 60, 75, 90], id: \.self) { minutes in
            choice(LanguageManager.t("setup.minutes", ["count": minutes]), selected: profile.minutes == minutes) { profile.minutes = minutes }
        }
        if profile.experience != "beginner" {
            choice(LanguageManager.t("setup.advanced"), selected: profile.advancedLifts, multiple: true) { profile.advancedLifts.toggle() }
        }
        Text(LanguageManager.t("setup.priority.title")).font(.headline)
        ForEach(["", "push", "row", "squat", "shoulders", "biceps", "core"], id: \.self) { priority in
            choice(LanguageManager.t("setup.priority.\(priority.isEmpty ? "balanced" : priority)"), selected: profile.priority == priority) { profile.priority = priority }
        }
        Text(LanguageManager.t("setup.exclude.title")).font(.headline)
        TextField("", text: $excludedSearch, prompt: Text(LanguageManager.t("setup.exclude.search")).foregroundStyle(AppColors.muted))
            .textFieldStyle(.plain).padding(14).background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border)).accessibilityLabel(LanguageManager.t("setup.exclude.search"))
        let excluded = catalog.candidates.filter { profile.excludedExerciseIds.contains($0.id) }
        let matches = catalog.candidates.filter { row in !profile.excludedExerciseIds.contains(row.id) &&
            excludedSearch.count >= 2 && ExerciseCatalog.canonicalExercises[row.id]?.toExercise().displayName.localizedCaseInsensitiveContains(excludedSearch) == true }
        ForEach(excluded + Array(matches.prefix(20)), id: \.id) { row in
            choice(ExerciseCatalog.canonicalExercises[row.id]?.toExercise().displayName ?? row.id, selected: profile.excludedExerciseIds.contains(row.id), multiple: true) {
                toggle(row.id, in: &profile.excludedExerciseIds)
            }
        }
    }
    @ViewBuilder private func preview(_ program: Program, catalog: TrainingCatalog) -> some View {
        if program.name != LanguageManager.t("setup.program.name") { Text(program.name).font(.title2.bold()) }
        Text(program.description).foregroundStyle(AppColors.secondaryText)
        Text("\(LanguageManager.t("onboarding.goal.\(profile.goal).title")) · \(LanguageManager.t("onboarding.experience.\(profile.experience).title"))")
            .foregroundStyle(AppColors.secondaryText)
        ForEach(generated?.warningKeys ?? [], id: \.self) { key in Text(LanguageManager.t(key)).foregroundStyle(AppColors.secondaryText) }
        ForEach(program.workouts) { workout in
            VStack(alignment: .leading, spacing: 10) {
                Text("\(LanguageManager.workoutDays[workout.day - 1]) · \(workout.title)").font(.headline)
                let minutes = (300 + workout.exercises.reduce(0) { $0 + TrainingPlanGenerator.estimateSeconds($1) } + 59) / 60
                Text(LanguageManager.t("setup.minutes", ["count": minutes])).font(.caption).foregroundStyle(AppColors.muted)
                ForEach(workout.exercises) { exercise in
                    Text(exercise.displayName)
                    Text("\(prescription(exercise)) · \(LanguageManager.t("setup.rest", ["seconds": exercise.restSeconds ?? 90]))")
                        .font(.caption).foregroundStyle(AppColors.secondaryText)
                    let role = catalog.candidates.first { $0.id == exercise.exerciseId }?.role
                    let replacement = TrainingPlanGenerator.eligible(profile, catalog: catalog).first { row in row.role == role && !workout.exercises.contains { $0.exerciseId == row.id } }
                    Button(LanguageManager.t("setup.replace")) { if let replacement { replace(exercise, in: workout, with: replacement, program: program) } }
                        .disabled(replacement == nil).frame(minHeight: 48)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border))
        }
        Button(LanguageManager.t("setup.editAnswers")) { step = 1 }.buttonStyle(.bordered).frame(minHeight: 48)
        Button(LanguageManager.t("modal.program.titleEdit")) { editing = true }.buttonStyle(.bordered).frame(minHeight: 48)
    }
    private func choice(_ label: String, selected: Bool, hint: String = "", multiple: Bool = false, tag: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).fontWeight(.medium).foregroundStyle(AppColors.text)
                    if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(AppColors.secondaryText) }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? (multiple ? "checkmark.square.fill" : "largecircle.fill.circle") : (multiple ? "square" : "circle"))
                    .foregroundStyle(selected ? AppColors.accent : AppColors.muted).accessibilityHidden(true)
            }.padding(14).frame(minHeight: 48).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).background(selected ? AppColors.positiveBg : AppColors.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? AppColors.accent : AppColors.border))
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(tag)
    }
    private func toggle(_ value: String, in values: inout [String]) {
        if values.contains(value) { values.removeAll { $0 == value } } else { values.append(value); values.sort() }
    }
    private func prescription(_ exercise: Exercise) -> String {
        guard let sets = exercise.sets, let reps = exercise.reps else { return LanguageManager.content(exercise.displayPrescription) }
        let range: String
        if reps.toFailure { range = LanguageManager.t("targets.failure") }
        else if let min = reps.min, let max = reps.max { range = min == max ? String(min) : "\(min)–\(max)" }
        else { return LanguageManager.content(exercise.displayPrescription) }
        return "\(sets) × \(range)" + (reps.perSide ? " · \(LanguageManager.t("targets.perSide"))" : "")
    }
    private func replace(_ exercise: Exercise, in workout: Workout, with row: TrainingCatalog.Candidate, program: Program) {
        guard var replacement = ExerciseCatalog.canonicalExercises[row.id]?.toExercise(),
              let w = program.workouts.firstIndex(where: { $0.id == workout.id }),
              let e = program.workouts[w].exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        replacement.id = UUID().uuidString; replacement.sets = exercise.sets; replacement.reps = exercise.reps
        replacement.reps?.perSide = row.perSide; replacement.restSeconds = exercise.restSeconds
        var updated = program; updated.workouts[w].exercises[e] = replacement; editedProgram = updated
    }
    private func back() { if step > 1 { step -= 1 } else { onClose() } }
    private func next() {
        if step < 6 { step += 1; search = "" }
        else if let program {
            if store.saveGeneratedPlan(profile: profile.normalized(), program: program, completeSetup: completeSetup) { onClose() }
            else { error = LanguageManager.t("setup.saveFailed") }
        }
    }
    private func persist() { TrainingSetupStore.saveDraft(.init(profile: profile, step: step, programId: programID, program: editedProgram)) }
}

private struct TrainingLoadField: View {
    let key: String
    @Binding var value: Double?
    @State private var input = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $input, prompt: Text(LanguageManager.t(key)).foregroundStyle(AppColors.muted))
                .keyboardType(.decimalPad).textFieldStyle(.plain).padding(14)
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border))
                .accessibilityLabel(LanguageManager.t(key))
            Text(LanguageManager.t("setup.load.optional")).font(.caption).foregroundStyle(AppColors.secondaryText)
        }.onAppear { input = value.map { String($0) } ?? "" }
            .onChange(of: input) { _, raw in value = Double(raw.replacingOccurrences(of: ",", with: ".")).flatMap { $0.isFinite && $0 > 0 && $0 <= 1000 ? $0 : nil } }
    }
}
