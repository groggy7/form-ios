import SwiftUI

public struct ProgramExerciseEditorSheet: View {
    let exercise: Exercise
    var onSave: (Exercise) -> Void
    var onDelete: (() -> Void)?
    @Environment(\.dismiss) var dismiss

    @State private var sets: Int
    @State private var isCustom: Bool
    @State private var minRepsString: String
    @State private var maxRepsString: String
    @State private var toFailure: Bool
    @State private var perSide: Bool
    @State private var customPrescription: String
    @State private var restSeconds: Int

    public init(
        exercise: Exercise,
        onSave: @escaping (Exercise) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        self.onSave = onSave
        self.onDelete = onDelete

        let initialSets = exercise.sets ?? 3
        _sets = State(initialValue: max(1, min(10, initialSets)))

        let hasCustom = exercise.reps == nil && !exercise.prescription.trimmingCharacters(in: .whitespaces).isEmpty
        _isCustom = State(initialValue: hasCustom)
        _customPrescription = State(initialValue: exercise.prescription)

        if let reps = exercise.reps {
            _minRepsString = State(initialValue: reps.min.map { String($0) } ?? "8")
            _maxRepsString = State(initialValue: reps.max.map { String($0) } ?? "12")
            _toFailure = State(initialValue: reps.toFailure)
            _perSide = State(initialValue: reps.perSide)
        } else {
            _minRepsString = State(initialValue: "8")
            _maxRepsString = State(initialValue: "12")
            _toFailure = State(initialValue: false)
            _perSide = State(initialValue: false)
        }

        _restSeconds = State(initialValue: exercise.restSeconds ?? 90)
    }

    private var isValid: Bool {
        guard sets >= 1 && sets <= 10 else { return false }
        if isCustom {
            let trimmed = customPrescription.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.count <= 100
        }
        if toFailure { return true }
        let cleanMin = minRepsString.trimmingCharacters(in: .whitespaces)
        let cleanMax = maxRepsString.trimmingCharacters(in: .whitespaces)
        guard let min = Int(cleanMin), let max = Int(cleanMax) else { return false }
        return min >= 1 && max <= 999 && min <= max
    }

    private var previewPrescription: String {
        if isCustom {
            let t = customPrescription.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "—" : t
        }
        if toFailure {
            return "\(sets) × \(LanguageManager.t("targets.failure"))" + (perSide ? " / side" : "")
        }
        let cleanMin = minRepsString.trimmingCharacters(in: .whitespaces)
        let cleanMax = maxRepsString.trimmingCharacters(in: .whitespaces)
        if let min = Int(cleanMin), let max = Int(cleanMax), min <= max {
            let repStr = min == max ? "\(min)" : "\(min)–\(max)"
            return "\(sets) × \(repStr)" + (perSide ? " / side" : "")
        }
        return "\(sets) sets"
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card with exercise info and live preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(exercise.resolvedMovement.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.positiveBg)
                                .cornerRadius(6)

                            Spacer()

                            Text("\(restSeconds)s rest")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppColors.muted)
                        }

                        Text(exercise.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.text)

                        HStack(spacing: 6) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.accent)

                            Text(previewPrescription)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                        }
                        .padding(.top, 2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.surfaceRaised)
                    .cornerRadius(14)

                    // Fixed Sets Card
                    editorSection(title: LanguageManager.t("targets.sets")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(sets) \(LanguageManager.t("targets.sets").lowercased())")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Text("1–10")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.muted)
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                Button(action: { if sets > 1 { sets -= 1 } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(sets > 1 ? AppColors.accent : AppColors.muted.opacity(0.3))
                                }
                                .disabled(sets <= 1)
                                .buttonStyle(.plain)

                                Text("\(sets)")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .frame(minWidth: 28)

                                Button(action: { if sets < 10 { sets += 1 } }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(sets < 10 ? AppColors.accent : AppColors.muted.opacity(0.3))
                                }
                                .disabled(sets >= 10)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }

                    // Rep Targets Card
                    editorSection(title: isCustom ? LanguageManager.t("modal.exercise.prescription") : LanguageManager.t("targets.reps")) {
                        VStack(spacing: 12) {
                            if !isCustom {
                                // Technical Failure Toggle
                                Toggle(isOn: $toFailure) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(LanguageManager.t("targets.failure"))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppColors.text)
                                    }
                                }
                                .tint(AppColors.accent)
                                .padding(.horizontal, 14)
                                .padding(.top, 14)

                                if !toFailure {
                                    Divider().background(AppColors.border).padding(.horizontal, 14)

                                    // Min & Max Rep inputs
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(LanguageManager.t("targets.min"))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)
                                            TextField("Min", text: $minRepsString)
                                                .keyboardType(.numberPad)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(AppColors.text)
                                                .padding(10)
                                                .background(AppColors.surfaceRaised)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(LanguageManager.t("targets.max"))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppColors.muted)
                                            TextField("Max", text: $maxRepsString)
                                                .keyboardType(.numberPad)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(AppColors.text)
                                                .padding(10)
                                                .background(AppColors.surfaceRaised)
                                                .cornerRadius(8)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                }

                                Divider().background(AppColors.border).padding(.horizontal, 14)

                                // Reps per side Toggle
                                Toggle(isOn: $perSide) {
                                    Text(LanguageManager.t("targets.perSide"))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(AppColors.text)
                                }
                                .tint(AppColors.accent)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 14)
                            } else {
                                // Custom prescription input
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("e.g. 3 rounds, hold 30s", text: $customPrescription)
                                        .font(.system(size: 15))
                                        .foregroundColor(AppColors.text)
                                        .padding(12)
                                        .background(AppColors.surfaceRaised)
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                                }
                                .padding(14)
                            }
                        }
                    }

                    // Structured / Custom Toggle Button
                    Button(action: {
                        isCustom.toggle()
                    }) {
                        Text(LanguageManager.t(isCustom ? "targets.structured" : "targets.custom"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }
                    .padding(.horizontal, 4)

                    // Rest Timer Card
                    editorSection(title: LanguageManager.t("programs.restSeconds")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("\(restSeconds)s")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(AppColors.text)

                                Spacer()

                                Stepper("", value: $restSeconds, in: 0...900, step: 15)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 14)

                            // Quick preset pills
                            HStack(spacing: 8) {
                                ForEach([60, 90, 120, 180], id: \.self) { preset in
                                    let isSel = restSeconds == preset
                                    Button(action: { restSeconds = preset }) {
                                        Text("\(preset)s")
                                            .font(.system(size: 12, weight: isSel ? .bold : .medium))
                                            .foregroundColor(isSel ? AppColors.todaySelectionText : AppColors.secondaryText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(isSel ? AppColors.accent : AppColors.surfaceRaised)
                                                    .overlay(Capsule().stroke(isSel ? AppColors.accent : AppColors.border, lineWidth: 1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                        }
                    }

                    // Validation warning
                    if !isValid {
                        Text(LanguageManager.t("targets.invalid"))
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.danger)
                            .padding(.horizontal, 4)
                    }

                    // Bottom Action Buttons
                    VStack(spacing: 12) {
                        Button(action: save) {
                            Text(LanguageManager.t("modal.exercise.save"))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isValid ? AppColors.todaySelectionText : AppColors.muted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(isValid ? AppColors.accent : AppColors.surface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isValid ? AppColors.accent : AppColors.border, lineWidth: 1)
                                )
                        }
                        .disabled(!isValid)
                        .buttonStyle(.plain)

                        if let onDelete = onDelete {
                            Button(action: {
                                onDelete()
                                dismiss()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                    Text(LanguageManager.t("modal.delete"))
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(AppColors.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(LanguageManager.t("modal.exercise.titleEdit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LanguageManager.t("modal.cancel")) { dismiss() }
                        .foregroundColor(AppColors.muted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LanguageManager.t("programs.save")) { save() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isValid ? AppColors.accent : AppColors.muted)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func editorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(AppColors.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        }
    }

    private func save() {
        guard isValid else { return }
        var updated = exercise
        updated.sets = sets
        if isCustom {
            updated.reps = nil
            updated.prescription = customPrescription.trimmingCharacters(in: .whitespaces)
        } else {
            updated.prescription = ""
            if toFailure {
                updated.reps = RepTarget(min: nil, max: nil, toFailure: true, perSide: perSide)
            } else {
                let cleanMin = minRepsString.trimmingCharacters(in: .whitespaces)
                let cleanMax = maxRepsString.trimmingCharacters(in: .whitespaces)
                let min = Int(cleanMin) ?? 8
                let max = Int(cleanMax) ?? 12
                updated.reps = RepTarget(min: min, max: max, toFailure: false, perSide: perSide)
            }
        }
        updated.restSeconds = restSeconds
        onSave(updated)
        dismiss()
    }
}
