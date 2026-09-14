import SwiftUI

public struct SetLoggingTable: View {
    private struct Field: Hashable {
        let id: String
        let weight: Bool
    }
    @FocusState private var focusedField: Field?
    @State private var selectedField: Field?
    let sets: [ExerciseSetLog]
    let prescription: String
    var onUpdateSet: (Int, String, String) -> Void
    var onToggleCompleteSet: (Int) -> Void
    var onAddSet: () -> Void
    var onRemoveSet: (Int) -> Void
    var onEmptyWarning: (() -> Void)? = nil

    public init(
        sets: [ExerciseSetLog],
        prescription: String = "",
        onUpdateSet: @escaping (Int, String, String) -> Void,
        onToggleCompleteSet: @escaping (Int) -> Void,
        onAddSet: @escaping () -> Void,
        onRemoveSet: @escaping (Int) -> Void,
        onEmptyWarning: (() -> Void)? = nil
    ) {
        self.sets = sets
        self.prescription = prescription
        self.onUpdateSet = onUpdateSet
        self.onToggleCompleteSet = onToggleCompleteSet
        self.onAddSet = onAddSet
        self.onRemoveSet = onRemoveSet
        self.onEmptyWarning = onEmptyWarning
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if !prescription.isEmpty {
                    Text(prescription)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(!sets.isEmpty && sets.allSatisfy(\.isCompleted)
                     ? LanguageManager.t("table.allSetsDone", ["total": sets.count])
                     : LanguageManager.t("table.currentSet", ["current": WorkoutSessionUtils.currentSetNumber(sets), "total": sets.count]))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12).background(AppColors.positiveBg).cornerRadius(10)
            // Table Header
            HStack(spacing: 8) {
                Text(LanguageManager.t("table.set"))
                    .frame(width: 38, alignment: .leading)
                Text(LanguageManager.t("table.weightKg"))
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.reps"))
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.doneHeading")).frame(width: 44)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(AppColors.muted)
            .padding(.horizontal, 14)

            // Set Rows
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                let weightBinding = Binding<String>(
                    get: { set.weightInput.isEmpty ? (set.weightKg.map { WorkoutSessionUtils.formatWeight($0) } ?? "") : set.weightInput },
                    set: { newVal in
                        if let sanitized = WorkoutSessionUtils.sanitizedWeightInput(newVal) {
                            let reps = set.repsInput.isEmpty ? (set.completedReps.map { "\($0)" } ?? "") : set.repsInput
                            onUpdateSet(index, sanitized, reps)
                        }
                    }
                )

                let repsBinding = Binding<String>(
                    get: {
                        if set.repsInput == "0" { return "" }
                        return set.repsInput.isEmpty ? (set.completedReps.flatMap { $0 > 0 ? "\($0)" : nil } ?? "") : set.repsInput
                    },
                    set: { newVal in
                        if let sanitized = WorkoutSessionUtils.sanitizedRepsInput(newVal) {
                            let weight = set.weightInput.isEmpty ? (set.weightKg.map { WorkoutSessionUtils.formatWeight($0) } ?? "") : set.weightInput
                            onUpdateSet(index, weight, sanitized)
                        }
                    }
                )

                let canComplete = set.isCompleted || WorkoutSessionUtils.canCompleteSet(set)

                HStack(spacing: 8) {
                    Text("\(set.setNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(set.isCompleted ? AppColors.accent : AppColors.secondaryText)
                        .frame(width: 38, alignment: .leading)

                    TextField("0", text: weightBinding, prompt: Text("0").foregroundColor(AppColors.muted))
                        .focused($focusedField, equals: Field(id: set.id, weight: true))
                        .simultaneousGesture(TapGesture().onEnded { selectedField = Field(id: set.id, weight: true) })
                        .accessibilityLabel("\(LanguageManager.t("table.set")) \(set.setNumber), \(LanguageManager.t("table.weightKg"))")
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedField == Field(id: set.id, weight: true) ? AppColors.accent : .clear))

                    TextField("0", text: repsBinding, prompt: Text("0").foregroundColor(AppColors.muted))
                        .focused($focusedField, equals: Field(id: set.id, weight: false))
                        .simultaneousGesture(TapGesture().onEnded { selectedField = Field(id: set.id, weight: false) })
                        .accessibilityLabel("\(LanguageManager.t("table.set")) \(set.setNumber), \(LanguageManager.t("table.actualReps"))")
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedField == Field(id: set.id, weight: false) ? AppColors.accent : .clear))

                    Button(action: {
                        if canComplete {
                            onToggleCompleteSet(index)
                            focusedField = nil
                            selectedField = nil
                        } else {
                            onEmptyWarning?()
                        }
                    }) {
                        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(
                                set.isCompleted
                                    ? AppColors.accent
                                    : (canComplete ? AppColors.muted.opacity(0.5) : AppColors.muted.opacity(0.2))
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(set.isCompleted ? AppColors.positiveBg.opacity(0.4) : AppColors.surface)
                )
                .contextMenu {
                    if sets.count > 1 {
                        Button(role: .destructive, action: { onRemoveSet(index) }) {
                            Label(LanguageManager.t("table.deleteSet"), systemImage: "trash")
                        }
                    }
                }
                if let selected = selectedField, selected.id == set.id {
                    let fieldLabel = LanguageManager.t(selected.weight ? "table.weightKg" : "table.actualReps")
                    let setLabel = "\(LanguageManager.t("table.set")) \(set.setNumber)"
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(setLabel) · \(fieldLabel)")
                                .font(.system(size: 12)).foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Button(LanguageManager.t("table.done")) { focusedField = nil; selectedField = nil }
                                .font(.system(size: 12)).foregroundColor(AppColors.accent)
                                .frame(minWidth: 48, minHeight: 48)
                        }
                        HStack(spacing: 8) {
                            ForEach(selected.weight ? [-10, -5, 5, 10] : [-1, 1], id: \.self) { step in
                                let label = step > 0 ? "+\(step)" : "−\(-step)"
                                Button {
                                    if selected.weight {
                                        weightBinding.wrappedValue = WorkoutSessionUtils.adjustWeight(weightBinding.wrappedValue, by: step)
                                    } else {
                                        repsBinding.wrappedValue = WorkoutSessionUtils.adjustReps(repsBinding.wrappedValue, by: step)
                                    }
                                } label: {
                                    Text(label).font(.system(size: 16)).foregroundColor(AppColors.text)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(setLabel), \(fieldLabel), \(label)")
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppColors.surfaceRaised).cornerRadius(10)
                    .accessibilityIdentifier("set-adjustments")
                }
            }

            // Add Set and Remove Last Buttons
            HStack(spacing: 10) {
                Button(action: onAddSet) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(LanguageManager.t("table.addSet"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    if sets.count > 1 {
                        onRemoveSet(sets.count - 1)
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                        Text(LanguageManager.t("table.removeSet"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(sets.count > 1 ? AppColors.accent : AppColors.muted.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(sets.count > 1 ? AppColors.border : AppColors.border.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(sets.count <= 1)
            }
            .padding(.top, 8)
        }
        .tint(AppColors.accent)
        .onChange(of: focusedField) { _, value in
            if let value { selectedField = value }
        }
        .onChange(of: sets.map(\.id)) { _, ids in
            if let selectedField, !ids.contains(selectedField.id) { self.selectedField = nil; focusedField = nil }
        }
    }
}
