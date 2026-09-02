import SwiftUI

public struct ProgramBuilderView: View {
    @ObservedObject var store: AppStore
    @State var program: Program
    let isNew: Bool
    var onDismiss: () -> Void

    @State private var selectedDay: Int = 1
    @State private var showAddExerciseSheet: Bool = false
    @State private var showExportSheet: Bool = false
    @State private var exportedJsonString: String = ""

    public init(store: AppStore, program: Program? = nil, onDismiss: @escaping () -> Void) {
        self.store = store
        let initial = program ?? Program(
            id: UUID().uuidString,
            name: "Custom Routine",
            description: "Custom hypertrophy and strength plan.",
            guidelines: ["Progressive overload", "Adequate sleep"],
            workouts: (1...7).map { Workout(day: $0, title: $0 % 2 == 1 ? "Workout Day" : "Rest Day") }
        )
        self._program = State(initialValue: initial)
        self.isNew = program == nil
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Program Details Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LanguageManager.t("editor.details"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageManager.t("editor.name"))
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.muted)
                            TextField("Program Name", text: $program.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.text)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(LanguageManager.t("editor.description"))
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.muted)
                            TextField("Description", text: $program.description)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.text)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                        }
                    }
                    .padding(16)
                    .background(AppColors.surfaceRaised)
                    .cornerRadius(14)

                    // Day Tabs
                    VStack(alignment: .leading, spacing: 14) {
                        Text(LanguageManager.t("editor.schedule"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.secondaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(1...7, id: \.self) { day in
                                    let isSel = selectedDay == day
                                    let dayName = LanguageManager.workoutDays.indices.contains(day - 1)
                                        ? String(LanguageManager.workoutDays[day - 1].prefix(3))
                                        : "D\(day)"
                                    Button(action: { selectedDay = day }) {
                                        Text("\(dayName) (\(day))")
                                            .font(.system(size: 13, weight: isSel ? .bold : .medium))
                                            .foregroundColor(isSel ? AppColors.todaySelectionText : AppColors.secondaryText)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(isSel ? AppColors.accent : AppColors.surface)
                                                    .overlay(Capsule().stroke(isSel ? AppColors.accent : AppColors.border, lineWidth: 1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Day Workout Editor
                        let currentWorkoutIndex = program.workouts.firstIndex { $0.day == selectedDay }
                        if let workoutIdx = currentWorkoutIndex {
                            let workout = program.workouts[workoutIdx]
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LanguageManager.t("editor.workoutTitle"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.muted)
                                    TextField("Day Title", text: $program.workouts[workoutIdx].title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AppColors.text)
                                        .padding(10)
                                        .background(AppColors.surface)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                                }

                                // Exercise List for Day
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(LanguageManager.t("today.exercises"))
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(AppColors.text)
                                        Spacer()
                                        Button(action: { showAddExerciseSheet = true }) {
                                            Label(LanguageManager.t("editor.addExercise"), systemImage: "plus")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(AppColors.accent)
                                        }
                                    }

                                    if workout.exercises.isEmpty {
                                        Text(LanguageManager.t("weekly.restDay"))
                                            .font(.system(size: 13))
                                            .foregroundColor(AppColors.muted)
                                            .padding(.vertical, 12)
                                    } else {
                                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { exIdx, exercise in
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(exercise.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(AppColors.text)
                                                    Text(exercise.displayPrescription)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(AppColors.muted)
                                                }

                                                Spacer()

                                                // Reorder up/down buttons
                                                Button(action: { moveExercise(workoutIndex: workoutIdx, from: exIdx, to: exIdx - 1) }) {
                                                    Image(systemName: "chevron.up")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(exIdx > 0 ? AppColors.text : AppColors.muted.opacity(0.3))
                                                }
                                                .disabled(exIdx == 0)

                                                Button(action: { moveExercise(workoutIndex: workoutIdx, from: exIdx, to: exIdx + 1) }) {
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(exIdx < workout.exercises.count - 1 ? AppColors.text : AppColors.muted.opacity(0.3))
                                                }
                                                .disabled(exIdx >= workout.exercises.count - 1)

                                                // Delete exercise
                                                Button(action: { deleteExercise(workoutIndex: workoutIdx, at: exIdx) }) {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 13))
                                                        .foregroundColor(AppColors.danger)
                                                }
                                            }
                                            .padding(12)
                                            .background(AppColors.surface)
                                            .cornerRadius(10)
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                        }
                                    }
                                }
                            }
                            .padding(16)
                            .background(AppColors.surfaceRaised)
                            .cornerRadius(14)
                        }
                    }

                    // Save & Export Buttons
                    VStack(spacing: 10) {
                        Button(action: saveProgram) {
                            Text(LanguageManager.t("editor.save"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppColors.todaySelectionText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AppColors.accent)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        Button(action: exportProgram) {
                            Text(LanguageManager.t("editor.export"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AppColors.surface)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(isNew ? LanguageManager.t("programs.new") : LanguageManager.t("editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LanguageManager.t("modal.cancel"), action: onDismiss)
                        .foregroundColor(AppColors.muted)
                }
            }
            .sheet(isPresented: $showAddExerciseSheet) {
                AddExercisePickerSheet(catalogue: store.exerciseCatalogue) { selected in
                    if let workoutIdx = program.workouts.firstIndex(where: { $0.day == selectedDay }) {
                        var ex = selected
                        ex.id = UUID().uuidString
                        program.workouts[workoutIdx].exercises.append(ex)
                    }
                    showAddExerciseSheet = false
                }
            }
            .sheet(isPresented: $showExportSheet) {
                ShareSheet(text: exportedJsonString)
            }
        }
    }

    private func moveExercise(workoutIndex: Int, from: Int, to: Int) {
        guard to >= 0 && to < program.workouts[workoutIndex].exercises.count else { return }
        let item = program.workouts[workoutIndex].exercises.remove(at: from)
        program.workouts[workoutIndex].exercises.insert(item, at: to)
    }

    private func deleteExercise(workoutIndex: Int, at index: Int) {
        program.workouts[workoutIndex].exercises.remove(at: index)
    }

    private func saveProgram() {
        if isNew {
            store.addProgram(program)
        } else {
            store.updateProgram(program)
        }
        onDismiss()
    }

    private func exportProgram() {
        if let data = try? JSONEncoder().encode(program), let str = String(data: data, encoding: .utf8) {
            exportedJsonString = str
            showExportSheet = true
        }
    }
}

struct AddExercisePickerSheet: View {
    let catalogue: [ExerciseCatalogEntry]
    var onSelect: (Exercise) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { entry in
                    Button(action: { onSelect(entry.exercise) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.exercise.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.text)
                            Text(entry.exercise.resolvedMovement.rawValue.capitalized)
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle(LanguageManager.t("editor.addExercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LanguageManager.t("modal.cancel")) { dismiss() }
                }
            }
        }
    }

    private var filtered: [ExerciseCatalogEntry] {
        if search.isEmpty { return catalogue }
        return catalogue.filter { $0.exercise.name.localizedCaseInsensitiveContains(search) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
