import SwiftUI

public struct SetLoggingTable: View {
    @ObservedObject var themeManager = ThemeManager.shared
    private struct Field: Hashable {
        let id: String
        let weight: Bool
    }
    @FocusState private var focusedField: Field?
    @State private var selectedField: Field?
    @State private var validationSetId: String?
    let sets: [ExerciseSetLog]
    let prescription: String
    var isRestActive: Bool = false
    var isRestForCurrentExercise: Bool = true
    var prText: String = "-"
    var onUpdateSet: (Int, String, String) -> Void
    var onToggleCompleteSet: (Int) -> Void
    var onAddSet: () -> Void
    var onRemoveSet: (Int) -> Void
    var onRestWarning: (() -> Void)? = nil
    var onInspectPlates: ((Double) -> Void)? = nil
    var onToggleWarmup: ((Int) -> Void)? = nil
    var weightUnit: WeightUnit = .kg
    var allowsZeroWeight: Bool = false
    var isAssisted: Bool = false
    var isBodyweight: Bool = false
    var ghostTargets: [Int: GhostTarget] = [:]
    var logbookBeatenSets: [Int: LogbookBeatResult] = [:]

    public init(
        sets: [ExerciseSetLog],
        prescription: String = "",
        isRestActive: Bool = false,
        isRestForCurrentExercise: Bool = true,
        prText: String = "-",
        onUpdateSet: @escaping (Int, String, String) -> Void,
        onToggleCompleteSet: @escaping (Int) -> Void,
        onAddSet: @escaping () -> Void,
        onRemoveSet: @escaping (Int) -> Void,
        onRestWarning: (() -> Void)? = nil,
        onInspectPlates: ((Double) -> Void)? = nil,
        onToggleWarmup: ((Int) -> Void)? = nil,
        weightUnit: WeightUnit = .kg,
        allowsZeroWeight: Bool = false,
        isAssisted: Bool = false,
        isBodyweight: Bool = false,
        ghostTargets: [Int: GhostTarget] = [:],
        logbookBeatenSets: [Int: LogbookBeatResult] = [:]
    ) {
        self.sets = sets
        self.prescription = prescription
        self.isRestActive = isRestActive
        self.isRestForCurrentExercise = isRestForCurrentExercise
        self.prText = prText
        self.onUpdateSet = onUpdateSet
        self.onToggleCompleteSet = onToggleCompleteSet
        self.onAddSet = onAddSet
        self.onRemoveSet = onRemoveSet
        self.onRestWarning = onRestWarning
        self.onInspectPlates = onInspectPlates
        self.onToggleWarmup = onToggleWarmup
        self.weightUnit = weightUnit
        self.allowsZeroWeight = allowsZeroWeight
        self.isAssisted = isAssisted
        self.isBodyweight = isBodyweight
        self.ghostTargets = ghostTargets
        self.logbookBeatenSets = logbookBeatenSets
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        VStack(spacing: 8) {
            let workingSets = sets.filter { !$0.isWarmup }
            let relevantSets = workingSets.isEmpty ? sets : workingSets
            let allRelevantDone = !relevantSets.isEmpty && relevantSets.allSatisfy(\.isCompleted)
            let progressText: String = {
                if allRelevantDone {
                    return LanguageManager.t("table.allSetsDone", ["total": relevantSets.count])
                } else {
                    return LanguageManager.t("table.currentSet", [
                        "current": WorkoutSessionUtils.currentSetNumber(relevantSets),
                        "total": relevantSets.count
                    ])
                }
            }()

            HStack(spacing: 12) {
                if !prescription.isEmpty {
                    Text(prescription)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(progressText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12).background(AppColors.positiveBg).clipShape(RoundedRectangle(cornerRadius: 10))
            // Table Header
            HStack(spacing: 8) {
                Text(LanguageManager.t("table.set"))
                    .frame(width: 32, alignment: .leading)
                Text(LanguageManager.t("table.pr"))
                    .frame(width: 56, alignment: .center)
                Text(weightUnit.uppercaseLabel)
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.reps"))
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.doneHeading")).frame(width: 44)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(AppColors.muted)
            .padding(.horizontal, 14)

            let weightHint = isAssisted ? LanguageManager.t("table.assistance_hint") : [
                isBodyweight ? "BW = \(LanguageManager.t("exercise.history.bodyweight"))." : nil,
                allowsZeroWeight ? LanguageManager.t("table.no_added_weight") : nil
            ].compactMap { $0 }.joined(separator: " ")
            if !weightHint.isEmpty {
                Text(weightHint)
                    .font(.system(size: 12)).foregroundStyle(AppColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            }
            let currentLoggedIndex = (isRestActive && isRestForCurrentExercise) ? sets.lastIndex(where: { $0.isCompleted }) : nil
            // Set Rows
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                let isSetEnabled = set.isCompleted || WorkoutSessionUtils.isSetEnabled(sets: sets, index: index)
                let isSetInputEnabled = isRestActive
                    ? (currentLoggedIndex == index || (isRestForCurrentExercise && selectedField?.id == set.id))
                    : isSetEnabled
                let ghostTarget = ghostTargets[index]
                let contextualPr: String = {
                    if let gt = ghostTarget, let prevW = gt.lastWeekWeightKg, let prevR = gt.lastWeekReps, prevW >= 0.0, prevR > 0 {
                        return WorkoutSessionUtils.formatSessionPr(weightKg: prevW, reps: prevR, unit: weightUnit, isBodyweight: isBodyweight, isAssisted: isAssisted)
                    }
                    return prText.isEmpty ? "-" : prText
                }()
                let weightBinding = Binding<String>(
                    get: {
                        return set.weightInput.isEmpty ? (set.weightKg.flatMap { $0 >= 0 ? WorkoutSessionUtils.formatWeightInput($0, unit: weightUnit) : nil } ?? "") : set.weightInput
                    },
                    set: { newVal in
                        guard isSetInputEnabled else { return }
                        if let sanitized = WorkoutSessionUtils.sanitizedWeightInput(newVal, unit: weightUnit) {
                            let reps = (set.repsInput == "0" || set.repsInput.isEmpty) ? (set.completedReps.flatMap { $0 > 0 ? "\($0)" : nil } ?? "") : set.repsInput
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
                        guard isSetInputEnabled else { return }
                        if newVal == "0" || newVal == "00" {
                            let weight = set.weightInput.isEmpty ? (set.weightKg.flatMap { $0 >= 0 ? WorkoutSessionUtils.formatWeightInput($0, unit: weightUnit) : nil } ?? "") : set.weightInput
                            onUpdateSet(index, weight, "")
                            return
                        }
                        if let sanitized = WorkoutSessionUtils.sanitizedRepsInput(newVal) {
                            let weight = set.weightInput.isEmpty ? (set.weightKg.flatMap { $0 >= 0 ? WorkoutSessionUtils.formatWeightInput($0, unit: weightUnit) : nil } ?? "") : set.weightInput
                            onUpdateSet(index, weight, sanitized)
                        }
                    }
                )

                let canComplete = set.isCompleted || (WorkoutSessionUtils.canCompleteSet(set, allowsZeroWeight: allowsZeroWeight) && !isRestActive)

                HStack(spacing: 8) {
                    Text(set.isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                        .font(.system(size: set.isWarmup ? 13 : 14, weight: .bold))
                        .foregroundStyle(
                            set.isWarmup
                                ? AppColors.warmupAmber
                                : (set.isCompleted
                                    ? AppColors.accent
                                    : (isSetEnabled ? AppColors.secondaryText : AppColors.secondaryText.opacity(0.35)))
                        )
                        .frame(width: 32, alignment: .leading)

                    let beatResult = set.isCompleted ? logbookBeatenSets[index] : nil
                    if set.isWarmup {
                        Text(LanguageManager.t("warmup.badge"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(AppColors.warmupAmber.opacity(0.85))
                            .lineLimit(1)
                            .frame(width: 56, alignment: .center)
                    } else if let beat = beatResult {
                        Text(WorkoutSessionUtils.formatLogbookBeatBadge(result: beat, unit: weightUnit))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppColors.positiveBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.accent.opacity(0.35)))
                            .frame(width: 56, alignment: .center)
                    } else {
                        Text(contextualPr.replacingOccurrences(of: " ×", with: "\n×").replacingOccurrences(of: "BW +", with: "BW+"))
                            .accessibilityLabel(WorkoutSessionUtils.sessionPrAccessibilityLabel(contextualPr, unit: weightUnit))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                set.isCompleted
                                    ? AppColors.secondaryText.opacity(0.6)
                                    : (isSetEnabled ? AppColors.secondaryText : AppColors.secondaryText.opacity(0.35))
                            )
                            .lineLimit(contextualPr.hasPrefix("BW") ? 2 : 1)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(contextualPr.hasPrefix("BW") ? 0.7 : 1)
                            .frame(width: 56, alignment: .center)
                    }

                    TextField("0", text: weightBinding, prompt: Text("0").foregroundStyle(AppColors.muted.opacity(isSetInputEnabled ? 0.6 : 0.25)))
                        .focused($focusedField, equals: Field(id: set.id, weight: true))
                        .simultaneousGesture(TapGesture().onEnded {
                            if isSetInputEnabled {
                                selectedField = Field(id: set.id, weight: true)
                            }
                        })
                        .disabled(!isSetInputEnabled)
                        .accessibilityLabel("\(LanguageManager.t("table.set")) \(set.setNumber), \((isAssisted ? "\(LanguageManager.t("table.assistance")) (\(weightUnit.label))" : LanguageManager.t(weightUnit == .lbs ? "table.weightLbs" : "table.weightKg")))")
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSetInputEnabled ? AppColors.text : AppColors.muted.opacity(0.5))
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised.opacity(isSetInputEnabled ? 1.0 : 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedField == Field(id: set.id, weight: true) && isSetInputEnabled ? AppColors.accent : .clear))

                    TextField("0", text: repsBinding, prompt: Text("0").foregroundStyle(AppColors.muted.opacity(isSetInputEnabled ? 0.6 : 0.25)))
                        .focused($focusedField, equals: Field(id: set.id, weight: false))
                        .simultaneousGesture(TapGesture().onEnded {
                            if isSetInputEnabled {
                                selectedField = Field(id: set.id, weight: false)
                            }
                        })
                        .disabled(!isSetInputEnabled)
                        .accessibilityLabel("\(LanguageManager.t("table.set")) \(set.setNumber), \(LanguageManager.t("table.actualReps"))")
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSetInputEnabled ? AppColors.text : AppColors.muted.opacity(0.5))
                        .padding(.vertical, 8)
                        .background(AppColors.surfaceRaised.opacity(isSetInputEnabled ? 1.0 : 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedField == Field(id: set.id, weight: false) && isSetInputEnabled ? AppColors.accent : .clear))

                    Button(action: {
                        if isRestActive {
                            if set.isCompleted && index == currentLoggedIndex {
                                focusedField = nil
                                selectedField = nil
                            } else {
                                onRestWarning?()
                            }
                        } else if set.isCompleted {
                            onToggleCompleteSet(index)
                            focusedField = nil
                            selectedField = nil
                        } else if canComplete {
                            validationSetId = nil
                            onToggleCompleteSet(index)
                            focusedField = nil
                            selectedField = nil
                        } else {
                            validationSetId = set.id
                        }
                    }) {
                        Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                set.isCompleted
                                    ? (set.isWarmup ? AppColors.warmupAmber : AppColors.accent)
                                    : (!isSetEnabled
                                        ? AppColors.muted.opacity(0.15)
                                        : (canComplete ? AppColors.muted.opacity(0.5) : AppColors.muted.opacity(0.2)))
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(LanguageManager.t("table.doneHeading")) \(LanguageManager.t("table.set")) \(set.setNumber)")
                    .accessibilityIdentifier("set-complete-\(set.id)")
                    .disabled(!isSetEnabled && !set.isCompleted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            set.isCompleted
                                ? (set.isWarmup ? AppColors.warmupAmberBg.opacity(0.4) : AppColors.positiveBg.opacity(0.4))
                                : (set.isWarmup
                                    ? AppColors.warmupAmberBg.opacity(0.35)
                                    : (isSetEnabled ? AppColors.surface : AppColors.surface.opacity(0.5)))
                        )
                )
                .contextMenu {
                    if let toggleWarmup = onToggleWarmup {
                        Button(action: { toggleWarmup(index) }) {
                            Label(
                                LanguageManager.t(set.isWarmup ? "warmup.convert_to_working" : "warmup.convert_to_warmup"),
                                systemImage: set.isWarmup ? "dumbbell" : "flame"
                            )
                        }
                    }
                    let plateWeight = (WarmupPlateEngine.hasWorkingLoad(set.weightKg) ? set.weightKg : nil)
                        ?? Double(weightBinding.wrappedValue.replacingOccurrences(of: ",", with: ".")).map {
                        weightUnit.toCanonicalKg($0)
                    }
                    if let inspect = onInspectPlates, let plateWeight, WarmupPlateEngine.hasWorkingLoad(plateWeight) {
                        Button(action: { inspect(plateWeight) }) {
                            Label(LanguageManager.t("warmup.tab_plates"), systemImage: "square.stack.3d.up")
                        }
                    }
                    if sets.count > 1 {
                        Button(role: .destructive, action: { onRemoveSet(index) }) {
                            Label(LanguageManager.t("table.deleteSet"), systemImage: "trash")
                        }
                    }
                }

                if validationSetId == set.id, !set.isCompleted,
                   let key = WorkoutSessionUtils.setValidationError(set, allowsZeroWeight: allowsZeroWeight) {
                    Text(LanguageManager.t(key)).font(.system(size: 12)).foregroundStyle(AppColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                        .accessibilityIdentifier("set-validation-\(set.id)")
                }
                if let selected = selectedField, selected.id == set.id, isSetInputEnabled {
                    let weightLabelKey = weightUnit == .lbs ? "table.weightLbs" : "table.weightKg"
                    let fieldLabel = LanguageManager.t(selected.weight ? weightLabelKey : "table.actualReps")
                    let setLabel = "\(LanguageManager.t("table.set")) \(set.setNumber)"
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(setLabel) · \(fieldLabel)")
                                .font(.system(size: 12)).foregroundStyle(AppColors.secondaryText)
                            Spacer()
                            Button(LanguageManager.t("table.done")) { focusedField = nil; selectedField = nil }
                                .font(.system(size: 12)).foregroundStyle(AppColors.accent)
                                .frame(minWidth: 48, minHeight: 48)
                        }
                        HStack(spacing: 8) {
                            ForEach(selected.weight ? [-10, -5, 5, 10] : [-1, 1], id: \.self) { step in
                                let label = step > 0 ? "+\(step)" : "−\(-step)"
                                Button {
                                    if selected.weight {
                                        weightBinding.wrappedValue = WorkoutSessionUtils.adjustWeight(weightBinding.wrappedValue, by: step, unit: weightUnit)
                                    } else {
                                        repsBinding.wrappedValue = WorkoutSessionUtils.adjustReps(repsBinding.wrappedValue, by: step)
                                    }
                                } label: {
                                    Text(label).font(.system(size: 16)).foregroundStyle(AppColors.text)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(setLabel), \(fieldLabel), \(label)")
                            }
                        }

                        HStack(spacing: 8) {
                            let plateWeight = (WarmupPlateEngine.hasWorkingLoad(set.weightKg) ? set.weightKg : nil)
                                ?? Double(weightBinding.wrappedValue.replacingOccurrences(of: ",", with: ".")).map {
                                weightUnit.toCanonicalKg($0)
                            }
                            if let inspect = onInspectPlates, let plateWeight, WarmupPlateEngine.hasWorkingLoad(plateWeight) {
                                Button {
                                    inspect(plateWeight)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.stack.3d.up")
                                            .font(.system(size: 13))
                                        Text(LanguageManager.t("warmup.tab_plates"))
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(AppColors.accent)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                onToggleWarmup?(index)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: set.isWarmup ? "dumbbell" : "flame")
                                        .font(.system(size: 13))
                                    Text(LanguageManager.t(set.isWarmup ? "warmup.convert_to_working" : "warmup.convert_to_warmup"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(set.isWarmup ? AppColors.secondaryText : AppColors.warmupAmber)
                                .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("set-adjustments")
                }
            }

            // Add Set and Remove Last Buttons
            HStack(spacing: 8) {
                Button(action: onAddSet) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(LanguageManager.t("table.addSet"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppColors.positiveBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppColors.accent.opacity(0.45), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    if sets.count > 1 {
                        onRemoveSet(sets.count - 1)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(LanguageManager.t("table.removeSet"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(sets.count > 1 ? AppColors.muted : AppColors.muted.opacity(0.35))
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(sets.count > 1 ? AppColors.muted.opacity(0.35) : AppColors.muted.opacity(0.15), lineWidth: 1)
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
        .onChange(of: isRestActive) { _, active in
            if active {
                self.selectedField = nil
                self.focusedField = nil
            }
        }
    }
}
