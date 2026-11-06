import SwiftUI
import Combine

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
    var previousSets: [Int: SessionSetLog] = [:]
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
    var logbookBeatenSets: [Int: LogbookBeatResult] = [:]
    /// Drop sets, rest-pause and partials (docs/design/intensity-sets.md).
    var intensity: IntensityActions? = nil
    /// The exercise's ratings, shown directly beneath its last set when the caller asks for them.
    var ratings: AnyView? = nil
    /// The keyboard bar's previous, next and Done controls.
    var fieldNavigator: SessionFieldNavigator? = nil
    @State private var knownExtensionIds: [String] = []

    public init(
        sets: [ExerciseSetLog],
        prescription: String = "",
        isRestActive: Bool = false,
        isRestForCurrentExercise: Bool = true,
        previousSets: [Int: SessionSetLog] = [:],
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
        logbookBeatenSets: [Int: LogbookBeatResult] = [:],
        intensity: IntensityActions? = nil,
        ratings: AnyView? = nil,
        fieldNavigator: SessionFieldNavigator? = nil
    ) {
        self.sets = sets
        self.prescription = prescription
        self.isRestActive = isRestActive
        self.isRestForCurrentExercise = isRestForCurrentExercise
        self.previousSets = previousSets
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
        self.logbookBeatenSets = logbookBeatenSets
        self.intensity = intensity
        self.ratings = ratings
        self.fieldNavigator = fieldNavigator
    }

    private func weightInputFontSize(_ text: String, width: CGFloat) -> CGFloat {
        // Measure at the rendered size; the returned size is authored and `Font.app` applies the width scale.
        let measured = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width * TextWidthScale.factor
        // Keep exact pound inputs visible without changing their text or physical load.
        return min(15, max(12, 15 * max(1, width - 8) / max(1, measured)))
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        ScrollViewReader { scrollProxy in
        VStack(spacing: 8) {
            let workingSets = sets.filter { !$0.isWarmup }
            let done = workingSets.filter(\.isCompleted).count
            let target = WorkoutSessionUtils.sessionPrescription(prescription)
            let title = Text(LanguageManager.t("matrix.stat.totalSets"))
                .font(.app(size: 15, weight: .semibold)).foregroundStyle(AppColors.text)
            let progress = Text("\(done)/\(workingSets.count)")
                .font(.app(size: 13, weight: .medium)).foregroundStyle(AppColors.secondaryText)
                .accessibilityLabel(LanguageManager.t("table.setsDone", ["done": done, "total": workingSets.count]))
                .accessibilityIdentifier("working-sets-progress")
            let pill = Text(target).font(.app(size: 12, weight: .medium)).foregroundStyle(AppColors.purple)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(AppColors.purpleBg, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier("working-sets-target")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    title.fixedSize()
                    if !target.isEmpty { pill.fixedSize().padding(.leading, 8) }
                    Spacer(minLength: 12)
                    progress.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        progress.fixedSize()
                    }
                    if !target.isEmpty { pill }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("working-sets-header")
                .tourTarget("workout.sets.row.0", cornerRadius: 12)
            Rectangle().fill(AppColors.border).frame(height: 1).accessibilityHidden(true)
            // Table Header
            HStack(spacing: 8) {
                Text(LanguageManager.t("table.setHeading"))
                    .frame(width: 32, alignment: .center)
                Text(LanguageManager.t("table.prev"))
                    .frame(width: 56, alignment: .center)
                Text(weightUnit.uppercaseLabel).frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.reps"))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                Text(LanguageManager.t("table.doneHeading")).frame(width: 44)
            }
            .font(.app(size: 11, weight: .bold))
            .foregroundStyle(AppColors.muted)
            .padding(.horizontal, 14)
            .tourTarget("workout.sets.row.1", cornerRadius: 12)

            let weightHint = isAssisted ? LanguageManager.t("table.assistance_hint") : [
                isBodyweight ? "BW = \(LanguageManager.t("exercise.history.bodyweight"))." : nil,
                allowsZeroWeight ? LanguageManager.t("table.no_added_weight") : nil
            ].compactMap { $0 }.joined(separator: " ")
            if !weightHint.isEmpty {
                Text(weightHint)
                    .font(.app(size: 12)).foregroundStyle(AppColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
            }
            let latestCompletedIndex = sets.lastIndex(where: { $0.isCompleted && !$0.isWarmup })
            let selectedIndex = sets.firstIndex(where: { Self.field(selectedField, belongsTo: $0) })
            // Set rows sit closer than the table's other blocks; every input keeps its 48pt target.
            VStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    VStack(spacing: 8) {
                        let isSetEnabled = set.isCompleted || WorkoutSessionUtils.isSetEnabled(sets: sets, index: index)
                        let selectedInSet = Self.field(selectedField, belongsTo: set)
                        let isSetInputEnabled = isSetEnabled
                        // A technique follows a finished effort: offered under the newest completed working set until a
                        // later set is being edited, and under any completed set being edited.
                        let showsTechniqueMenu = intensity != nil && !set.isWarmup && set.isCompleted
                            && (selectedInSet || (index == latestCompletedIndex && (selectedIndex ?? index) <= index))
                        let previous = set.isWarmup ? nil : previousSets[index].flatMap { $0.isWarmup ? nil : $0 }
                        let previousText: String = {
                            guard let previous, let load = previous.weightKg, load.isFinite, load >= 0,
                                  let count = previous.reps, (1...999).contains(count) else { return "—" }
                            return WorkoutSessionUtils.formatSessionPr(weightKg: load, reps: count, unit: weightUnit, isBodyweight: isBodyweight, isAssisted: isAssisted)
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

                        let canComplete = set.isCompleted || (WorkoutSessionUtils.canCompleteSet(set, allowsZeroWeight: allowsZeroWeight))

                        // A set and its drops, rest-pause efforts and partials share one container, so they read as one set.
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(set.isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                                    .font(.app(size: set.isWarmup ? 13 : 14, weight: .bold))
                                    .foregroundStyle(
                                        set.isWarmup
                                            ? AppColors.warmupAmber
                                            : (set.isCompleted
                                                ? AppColors.accent
                                                : (isSetEnabled ? AppColors.secondaryText : AppColors.secondaryText.opacity(0.35)))
                                    )
                                    .frame(width: 32, alignment: .center)

                                let beatResult = set.isCompleted ? logbookBeatenSets[index] : nil
                                if set.isWarmup {
                                    Text(LanguageManager.t("warmup.badge"))
                                        .font(.app(size: 10.5, weight: .bold))
                                        .foregroundStyle(AppColors.warmupAmber.opacity(0.85))
                                        .lineLimit(1)
                                        .frame(width: 56, alignment: .center)
                                } else {
                                    let beaten = beatResult != nil && previous != nil
                                    Text(previousText.replacingOccurrences(of: " ×", with: "\n×").replacingOccurrences(of: "BW +", with: "BW+"))
                                        .accessibilityLabel(WorkoutSessionUtils.sessionPrAccessibilityLabel(previousText, unit: weightUnit) +
                                            (previous == nil ? "" : beatResult.map { ", \(WorkoutSessionUtils.formatLogbookBeatBadge(result: $0, unit: weightUnit))" } ?? ""))
                                        .accessibilityIdentifier("set-prev-\(set.id)")
                                        .font(.app(size: 13, weight: .medium))
                                        .foregroundStyle(beaten ? AppColors.accent : AppColors.secondaryText)
                                        .lineLimit(previousText.hasPrefix("BW") ? 2 : 1)
                                        .multilineTextAlignment(.center)
                                        .minimumScaleFactor(previousText.hasPrefix("BW") ? 0.7 : 1)
                                        .frame(width: 56, alignment: .center)
                                        .background(beaten ? AppColors.positiveBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(beaten ? AppColors.accent.opacity(0.35) : .clear))
                                }

                                GeometryReader { geometry in
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
                                        .font(.app(size: weightInputFontSize(weightBinding.wrappedValue, width: geometry.size.width), weight: .semibold))
                                        .foregroundStyle(isSetInputEnabled ? AppColors.text : AppColors.muted.opacity(0.5))
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 48)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(AppColors.surfaceRaised.opacity(isSetInputEnabled ? 1.0 : 0.5)).padding(.vertical, 4))
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedField == Field(id: set.id, weight: true) && isSetInputEnabled ? AppColors.accent : .clear).padding(.vertical, 4))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)

                                // A Smart Progression target is only a hint: the field stays empty until the user enters actual reps.
                                let targetRepsHint = set.targetReps.flatMap { (1...999).contains($0) && !set.isCompleted ? $0 : nil }
                                TextField("0", text: repsBinding, prompt: Text(targetRepsHint.map(String.init) ?? "0").foregroundStyle(AppColors.muted.opacity(isSetInputEnabled ? 0.6 : 0.25)))
                                    .focused($focusedField, equals: Field(id: set.id, weight: false))
                                    .simultaneousGesture(TapGesture().onEnded {
                                        if isSetInputEnabled {
                                            selectedField = Field(id: set.id, weight: false)
                                        }
                                    })
                                    .disabled(!isSetInputEnabled)
                                    .accessibilityLabel("\(LanguageManager.t("table.set")) \(set.setNumber), \(LanguageManager.t("table.actualReps"))"
                                        + (targetRepsHint.map { ", " + LanguageManager.t("progression.coach.reps_target_hint", ["reps": "\($0)"]) } ?? ""))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .font(.app(size: 15, weight: .semibold))
                                    .foregroundStyle(isSetInputEnabled ? AppColors.text : AppColors.muted.opacity(0.5))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 48)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(AppColors.surfaceRaised.opacity(isSetInputEnabled ? 1.0 : 0.5)).padding(.vertical, 4))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedField == Field(id: set.id, weight: false) && isSetInputEnabled ? AppColors.accent : .clear).padding(.vertical, 4))

                                Button(action: {
                                    if set.isCompleted {
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
                            if let intensity, !set.isWarmup {
                                intensityRows(set: set, index: index, actions: intensity, inputEnabled: isSetInputEnabled, rowEnabled: isSetEnabled)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    set.isCompleted
                                        ? (set.isWarmup ? AppColors.warmupAmberBg.opacity(0.4) : AppColors.positiveBg.opacity(0.4))
                                        : (set.isWarmup
                                            ? AppColors.warmupAmberBg.opacity(0.35)
                                            : (isSetEnabled ? AppColors.surfaceRaised.opacity(0.55) : AppColors.surface.opacity(0.5)))
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
                            if let intensity, !set.isWarmup, set.isCompleted {
                                Menu {
                                    techniqueMenuItems(set: set, index: index, actions: intensity)
                                } label: {
                                    Label(LanguageManager.t("intensity.add"), systemImage: "plus")
                                }
                            }
                            if sets.count > 1 {
                                Button(role: .destructive, action: { onRemoveSet(index) }) {
                                    Label(LanguageManager.t("table.deleteSet"), systemImage: "trash")
                                }
                            }
                        }
                        .id(Self.groupId(set.id))

                        if validationSetId == set.id, !set.isCompleted,
                           let key = WorkoutSessionUtils.setValidationError(set, allowsZeroWeight: allowsZeroWeight) {
                            Text(LanguageManager.t(key)).font(.app(size: 12)).foregroundStyle(AppColors.danger)
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
                                        .font(.app(size: 12)).foregroundStyle(AppColors.secondaryText)
                                    Spacer()
                                    Button(LanguageManager.t("table.done")) { focusedField = nil; selectedField = nil }
                                        .font(.app(size: 12)).foregroundStyle(AppColors.accent)
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
                                            Text(label).font(.app(size: 16)).foregroundStyle(AppColors.text)
                                                .frame(maxWidth: .infinity, minHeight: 48)
                                                .background(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
                                                .contentShape(RoundedRectangle(cornerRadius: 8))
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
                                                    .font(.app(size: 12, weight: .medium))
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
                                                .font(.app(size: 12, weight: .medium))
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
                        if showsTechniqueMenu, let intensity {
                            techniqueMenu(set: set, index: index, actions: intensity)
                        }
                    }
                    .tourTarget("workout.sets.row.\(index + 2)", cornerRadius: 10)
                }
            }

            if let ratings { ratings }

            // Add Set and Remove Last Buttons
            HStack(spacing: 8) {
                Button(action: onAddSet) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(LanguageManager.t("table.addSet"))
                            .font(.app(size: 13, weight: .semibold))
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
                            .font(.app(size: 12, weight: .medium))
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
            updateNavigator()
        }
        .onChange(of: selectedField) { _, value in reveal(value, scrollProxy) }
        .onReceive(fieldNavigator.map { $0.commands.eraseToAnyPublisher() } ?? Empty().eraseToAnyPublisher()) { perform($0) }
        .onChange(of: sets.map(\.id)) { _, _ in
            if let selectedField, !sets.contains(where: { Self.field(selectedField, belongsTo: $0) }) { self.selectedField = nil; focusedField = nil }
        }
        .onAppear { knownExtensionIds = sets.flatMap { $0.extensions?.map(\.id) ?? [] } }
        .onChange(of: sets) { _, latest in
            if let selectedField, !latest.contains(where: { Self.field(selectedField, belongsTo: $0) }) { self.selectedField = nil; focusedField = nil }
            // A newly added drop or rest-pause effort takes focus, so its numbers can be typed straight away.
            let ids = latest.flatMap { $0.extensions?.map(\.id) ?? [] }
            if let added = ids.first(where: { !knownExtensionIds.contains($0) }),
               let owner = latest.first(where: { $0.extensions?.contains { $0.id == added } == true }) {
                let part = owner.extensions?.first { $0.id == added }
                let wantsWeight = IntensitySets.technique(of: owner) == .drop && (part?.weightInput.isEmpty ?? true)
                focusedField = Field(id: added, weight: wantsWeight)
            }
            knownExtensionIds = ids
            updateNavigator()
        }
        .onChange(of: isRestActive) { _, active in
            if active {
                self.selectedField = nil
                self.focusedField = nil
            }
        }
        }
    }

    // MARK: Drop sets, rest-pause and partials

    private static func partialsFieldId(_ ownerId: String) -> String { ownerId + "-partials" }

    private static func field(_ field: Field?, belongsTo set: ExerciseSetLog) -> Bool {
        guard let id = field?.id else { return false }
        if id == set.id || id == partialsFieldId(set.id) { return true }
        return (set.extensions ?? []).contains { $0.id == id || partialsFieldId($0.id) == id }
    }

    private func displayedWeight(_ weightInput: String, _ weightKg: Double?) -> String {
        weightInput.isEmpty ? (weightKg.flatMap { $0 >= 0 ? WorkoutSessionUtils.formatWeightInput($0, unit: weightUnit) : nil } ?? "") : weightInput
    }

    /// The same part in the previous occurrence, as the PR column's hint.
    private func previousPartText(set: ExerciseSetLog, index: Int, extensionIndex: Int, actions: IntensityActions) -> String {
        guard let previous = actions.previousSets[index], let technique = IntensitySets.technique(of: set),
              previous.setTechnique == technique, let part = previous.setExtensions[safe: extensionIndex], let reps = part.reps else { return "-" }
        if technique == .restPause { return "×\(reps)" }
        return WorkoutSessionUtils.formatSessionPr(weightKg: part.weightKg ?? 0, reps: reps, unit: weightUnit, isBodyweight: isBodyweight, isAssisted: isAssisted)
    }

    private func previousPartialsText(index: Int, extensionIndex: Int?, actions: IntensityActions) -> String {
        guard let previous = actions.previousSets[index] else { return "-" }
        let count = extensionIndex.map { previous.setExtensions[safe: $0]?.partialReps } ?? previous.partialReps
        return count.map { "+\($0)" } ?? "-"
    }

    @ViewBuilder
    private func intensityRows(set: ExerciseSetLog, index: Int, actions: IntensityActions, inputEnabled: Bool, rowEnabled: Bool) -> some View {
        if let input = set.partialRepsInput {
            partialsRow(set: set, index: index, extensionIndex: nil, ownerId: set.id, input: input, actions: actions, inputEnabled: inputEnabled, rowEnabled: rowEnabled)
        }
        let technique = IntensitySets.technique(of: set) ?? .drop
        ForEach(Array((set.extensions ?? []).enumerated()), id: \.element.id) { extensionIndex, part in
            extensionRow(set: set, index: index, extensionIndex: extensionIndex, part: part, technique: technique,
                         actions: actions, inputEnabled: inputEnabled, rowEnabled: rowEnabled)
            if validationSetId == part.id, !part.isCompleted,
               let key = IntensitySets.extensionValidationError(set, at: extensionIndex, exercise: actions.exercise, unit: weightUnit) {
                Text(LanguageManager.t(key)).font(.app(size: 12)).foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                    .accessibilityIdentifier("set-validation-\(part.id)")
            }
            if let input = part.partialRepsInput {
                partialsRow(set: set, index: index, extensionIndex: extensionIndex, ownerId: part.id, input: input, actions: actions, inputEnabled: inputEnabled, rowEnabled: rowEnabled)
            }
        }
    }

    private func subRowField(_ binding: Binding<String>, field: Field, prompt: String, enabled: Bool, label: String, keyboard: UIKeyboardType) -> some View {
        TextField("0", text: binding, prompt: Text(prompt).foregroundStyle(AppColors.muted.opacity(enabled ? 0.6 : 0.25)))
            .focused($focusedField, equals: field)
            .simultaneousGesture(TapGesture().onEnded { if enabled { selectedField = field } })
            .disabled(!enabled)
            .accessibilityLabel(label)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.app(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? AppColors.text : AppColors.muted.opacity(0.5))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.surfaceRaised.opacity(enabled ? 1.0 : 0.5)).padding(.vertical, 4))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selectedField == field && enabled ? AppColors.accent : .clear).padding(.vertical, 4))
    }

    private func extensionRow(set: ExerciseSetLog, index: Int, extensionIndex: Int, part: SetExtensionLog, technique: SetTechnique,
                              actions: IntensityActions, inputEnabled: Bool, rowEnabled: Bool) -> some View {
        let isDrop = technique == .drop
        let label = LanguageManager.t(isDrop ? "intensity.a11y.drop" : "intensity.a11y.restPause", ["set": set.setNumber, "index": extensionIndex + 1])
        let canTick = IntensitySets.extensionValidationError(set, at: extensionIndex, exercise: actions.exercise, unit: weightUnit) == nil
        let weightText = isDrop ? displayedWeight(part.weightInput, part.weightKg) : ""
        let weightBinding = Binding<String>(
            get: { weightText },
            set: { newValue in
                guard inputEnabled, let sanitized = WorkoutSessionUtils.sanitizedWeightInput(newValue, unit: weightUnit) else { return }
                actions.onUpdateExtension(index, extensionIndex, sanitized, part.repsInput)
            }
        )
        let repsBinding = Binding<String>(
            get: { part.repsInput == "0" ? "" : part.repsInput },
            set: { newValue in
                guard inputEnabled else { return }
                if newValue == "0" || newValue == "00" { actions.onUpdateExtension(index, extensionIndex, weightText, ""); return }
                if let sanitized = WorkoutSessionUtils.sanitizedRepsInput(newValue) { actions.onUpdateExtension(index, extensionIndex, weightText, sanitized) }
            }
        )
        let previous = previousPartText(set: set, index: index, extensionIndex: extensionIndex, actions: actions)
        return HStack(spacing: 8) {
            subRowMarker(isDrop ? "arrow.down.right" : "pause", enabled: rowEnabled)
            Text(previous)
                .font(.app(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText.opacity(part.isCompleted ? 0.6 : (rowEnabled ? 1 : 0.35)))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 56, alignment: .center)
                .accessibilityLabel(previous)
            if isDrop {
                subRowField(weightBinding, field: Field(id: part.id, weight: true), prompt: "0", enabled: inputEnabled,
                            label: "\(label), \(isAssisted ? LanguageManager.t("table.assistance") : LanguageManager.t(weightUnit == .lbs ? "table.weightLbs" : "table.weightKg"))",
                            keyboard: .decimalPad)
            } else {
                // Rest-pause keeps the main part's load.
                Text(displayedWeight(set.weightInput, set.weightKg))
                    .font(.app(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityLabel("\(label), \(displayedWeight(set.weightInput, set.weightKg)) \(weightUnit.label)")
            }
            subRowField(repsBinding, field: Field(id: part.id, weight: false), prompt: "0", enabled: inputEnabled,
                        label: "\(label), \(LanguageManager.t("table.actualReps"))", keyboard: .numberPad)
            Button(action: {
                if part.isCompleted || canTick {
                    validationSetId = nil
                    actions.onToggleExtension(index, extensionIndex)
                    focusedField = nil
                    selectedField = nil
                } else {
                    validationSetId = part.id
                }
            }) {
                Image(systemName: part.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(part.isCompleted ? AppColors.accent : (inputEnabled ? AppColors.muted.opacity(canTick ? 0.5 : 0.2) : AppColors.muted.opacity(0.15)))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!inputEnabled)
            .accessibilityLabel("\(LanguageManager.t("table.doneHeading")) \(label)")
            .accessibilityIdentifier("extension-complete-\(part.id)")
        }
        .padding(.horizontal, 14)
        .accessibilityIdentifier("extension-row-\(part.id)")
    }

    private func partialsRow(set: ExerciseSetLog, index: Int, extensionIndex: Int?, ownerId: String, input: String,
                             actions: IntensityActions, inputEnabled: Bool, rowEnabled: Bool) -> some View {
        let field = Field(id: Self.partialsFieldId(ownerId), weight: false)
        let label = LanguageManager.t("intensity.a11y.partials", ["set": set.setNumber])
        let binding = Binding<String>(
            get: { input },
            set: { newValue in
                guard inputEnabled, let sanitized = IntensitySets.sanitizedPartialInput(newValue) else { return }
                actions.onUpdatePartials(index, extensionIndex, sanitized)
            }
        )
        return HStack(spacing: 8) {
            subRowMarker("circle.lefthalf.filled", enabled: rowEnabled)
            Text(previousPartialsText(index: index, extensionIndex: extensionIndex, actions: actions))
                .font(.app(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText.opacity(rowEnabled ? 1 : 0.35))
                .frame(width: 56, alignment: .center)
            Text(LanguageManager.t("intensity.partialsShort"))
                .font(.app(size: 12, weight: .medium))
                .foregroundStyle(AppColors.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .accessibilityHidden(true)
            subRowField(binding, field: field, prompt: "0", enabled: inputEnabled, label: label, keyboard: .numberPad)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 14)
        .accessibilityIdentifier("partials-row-\(ownerId)")
    }

    /// The SET column of a drop, rest-pause or partials row: a purple rule joining it to its set, then its glyph.
    private func subRowMarker(_ systemName: String, enabled: Bool) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(AppColors.purple.opacity(enabled ? 0.35 : 0.15)).frame(width: 2).padding(.leading, 9)
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.purple.opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 32, height: 48)
        .accessibilityHidden(true)
    }

    /// Drop, Rest-pause and Partials, then a remove action that names what it removes. One technique per set.
    @ViewBuilder
    private func techniqueMenuItems(set: ExerciseSetLog, index: Int, actions: IntensityActions) -> some View {
        Button { actions.onAddExtension(index, .drop) } label: {
            Label(LanguageManager.t("intensity.drop"), systemImage: "arrow.down.right")
        }
        .disabled(!IntensitySets.canAdd(.drop, to: set))
        Button { actions.onAddExtension(index, .restPause) } label: {
            Label(LanguageManager.t("intensity.restPause"), systemImage: "pause")
        }
        .disabled(!IntensitySets.canAdd(.restPause, to: set))
        Button { actions.onAddPartials(index) } label: {
            Label(LanguageManager.t("intensity.partialsChip"), systemImage: "circle.lefthalf.filled")
        }
        .disabled(!IntensitySets.canAddPartials(to: set))
        if let part = IntensitySets.lastRemovablePart(set) {
            Divider()
            Button(role: .destructive) { actions.onRemoveLastPart(index) } label: {
                Label(LanguageManager.t(Self.removeKey(part)), systemImage: "minus.circle")
            }
        }
    }

    static func removeKey(_ part: IntensitySets.RemovablePart) -> String {
        switch part {
        case .drop: return "intensity.removeDrop"
        case .restPause: return "intensity.removeRestPause"
        case .partials: return "intensity.removePartials"
        }
    }

    /// One quiet purple pill under the set; the menu holds the techniques.
    private func techniqueMenu(set: ExerciseSetLog, index: Int, actions: IntensityActions) -> some View {
        Menu {
            techniqueMenuItems(set: set, index: index, actions: actions)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text(LanguageManager.t("intensity.add")).font(.app(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(AppColors.purple)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        // The menu's glyphs use the focused-training-detail purple, like the sub-rows they add.
        .tint(AppColors.purple)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .accessibilityIdentifier("technique-menu")
    }

    // MARK: Keyboard bar

    static func groupId(_ setId: String) -> String { "set-group-" + setId }

    /// Every field the table can focus, in reading order; locked future sets are skipped.
    private var orderedFields: [Field] {
        sets.enumerated().flatMap { index, set -> [Field] in
            guard set.isCompleted || WorkoutSessionUtils.isSetEnabled(sets: sets, index: index) else { return [] }
            var fields = [Field(id: set.id, weight: true), Field(id: set.id, weight: false)]
            guard intensity != nil, !set.isWarmup else { return fields }
            if set.partialRepsInput != nil { fields.append(Field(id: Self.partialsFieldId(set.id), weight: false)) }
            let isDrop = IntensitySets.technique(of: set) != .restPause
            for part in set.extensions ?? [] {
                if isDrop { fields.append(Field(id: part.id, weight: true)) }
                fields.append(Field(id: part.id, weight: false))
                if part.partialRepsInput != nil { fields.append(Field(id: Self.partialsFieldId(part.id), weight: false)) }
            }
            return fields
        }
    }

    private func neighbor(of field: Field?, by step: Int) -> Field? {
        let fields = orderedFields
        guard let field, let position = fields.firstIndex(of: field), fields.indices.contains(position + step) else { return nil }
        return fields[position + step]
    }

    private func updateNavigator() {
        fieldNavigator?.update(previous: neighbor(of: focusedField, by: -1) != nil, next: neighbor(of: focusedField, by: 1) != nil)
    }

    private func perform(_ command: SessionFieldNavigator.Command) {
        switch command {
        case .previous: if let field = neighbor(of: focusedField, by: -1) { focusedField = field }
        case .next: if let field = neighbor(of: focusedField, by: 1) { focusedField = field }
        case .done: focusedField = nil; selectedField = nil
        }
    }

    /// Brings the edited set to the top of the visible area, so its adjustments and techniques stay above the keyboard.
    private func reveal(_ field: Field?, _ proxy: ScrollViewProxy) {
        guard let field, let set = sets.first(where: { Self.field(field, belongsTo: $0) }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.groupId(set.id), anchor: .top) }
        }
    }
}

/// Moves focus between the session table's fields from the bar above the keyboard.
@MainActor
public final class SessionFieldNavigator: ObservableObject {
    public enum Command { case previous, next, done }
    @Published public private(set) var canMovePrevious = false
    @Published public private(set) var canMoveNext = false
    let commands = PassthroughSubject<Command, Never>()

    public init() {}

    public func send(_ command: Command) { commands.send(command) }

    func update(previous: Bool, next: Bool) {
        if canMovePrevious != previous { canMovePrevious = previous }
        if canMoveNext != next { canMoveNext = next }
    }
}

/// What the session table needs to log drop sets, rest-pause and partials.
public struct IntensityActions {
    public let exercise: Exercise
    /// The previous occurrence's working set at each row index, for PR hints.
    public let previousSets: [Int: SessionSetLog]
    public let onAddExtension: (Int, SetTechnique) -> Void
    public let onUpdateExtension: (Int, Int, String, String) -> Void
    public let onToggleExtension: (Int, Int) -> Void
    public let onAddPartials: (Int) -> Void
    public let onUpdatePartials: (Int, Int?, String) -> Void
    public let onRemoveLastPart: (Int) -> Void
}
