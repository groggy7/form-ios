import SwiftUI

public struct SetLoggingTable: View {
    let sets: [ExerciseSetLog]
    var onUpdateSet: (Int, String, String) -> Void
    var onToggleCompleteSet: (Int) -> Void
    var onAddSet: () -> Void
    var onRemoveSet: (Int) -> Void

    public init(
        sets: [ExerciseSetLog],
        onUpdateSet: @escaping (Int, String, String) -> Void,
        onToggleCompleteSet: @escaping (Int) -> Void,
        onAddSet: @escaping () -> Void,
        onRemoveSet: @escaping (Int) -> Void
    ) {
        self.sets = sets
        self.onUpdateSet = onUpdateSet
        self.onToggleCompleteSet = onToggleCompleteSet
        self.onAddSet = onAddSet
        self.onRemoveSet = onRemoveSet
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Table Header
            HStack(spacing: 8) {
                Text(LanguageManager.t("table.set"))
                    .frame(width: 38, alignment: .leading)
                Text(LanguageManager.t("table.weightKg"))
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.reps"))
                    .frame(maxWidth: .infinity)
                Spacer().frame(width: 44)
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

                HStack(spacing: 8) {
                    Text("\(set.setNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(set.isCompleted ? AppColors.accent : AppColors.secondaryText)
                        .frame(width: 38, alignment: .leading)

                    TextField("0", text: weightBinding)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity)

                    TextField("0", text: repsBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised)
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity)

                    Button(action: {
                        onToggleCompleteSet(index)
                    }) {
                        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(set.isCompleted ? AppColors.accent : AppColors.muted.opacity(0.5))
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
    }
}
