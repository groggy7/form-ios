import SwiftUI

public struct SetLoggingTable: View {
    @ObservedObject var themeManager = ThemeManager.shared
    private struct Field: Hashable {
        let id: String
        let weight: Bool
    }
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
    /// Reps in reserve per completed working set (docs/adaptive-training.md); nil hides the effort line.
    var effort: EffortActions? = nil
    /// The exercise's ratings, shown directly beneath its last set when the caller asks for them.
    var ratings: AnyView? = nil
    /// The session's number pad; the selected field becomes its target.
    var keypad: SessionKeypad? = nil
    /// The ± step for loads in `weightUnit`, from the exercise's equipment.
    var weightStep: Double? = nil
    /// Converted previous loads use the nearest plate setup ("225", not "220.46").
    var barbellPlates: Bool = false
    /// Plates and the warm-up switch join the keypad heading for Warmup & Plates owners.
    var warmupToolsUnlocked: Bool = false
    @State private var ownKeypad = SessionKeypad()
    @State private var knownExtensionIds: [String] = []
    private var activeKeypad: SessionKeypad { keypad ?? ownKeypad }
    private var loadStep: Double { weightStep ?? WorkoutSessionUtils.defaultLoadStep(weightUnit) }

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
        effort: EffortActions? = nil,
        ratings: AnyView? = nil,
        keypad: SessionKeypad? = nil,
        weightStep: Double? = nil,
        barbellPlates: Bool = false,
        warmupToolsUnlocked: Bool = false
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
        self.effort = effort
        self.ratings = ratings
        self.keypad = keypad
        self.weightStep = weightStep
        self.barbellPlates = barbellPlates
        self.warmupToolsUnlocked = warmupToolsUnlocked
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
            // Set rows sit closer than the table's other blocks; every input keeps its 48pt target.
            VStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    VStack(spacing: 8) {
                        let isSetEnabled = set.isCompleted || WorkoutSessionUtils.isSetEnabled(sets: sets, index: index)
                        let selectedInSet = Self.field(selectedField, belongsTo: set)
                        let isSetInputEnabled = isSetEnabled
                        // A technique follows a finished effort: offered under the newest completed working set and under any
                        // completed set being edited. It stays while a later set is typed, so no row moves under the finger.
                        let followsFinishedEffort = !set.isWarmup && set.isCompleted && (selectedInSet || index == latestCompletedIndex)
                        let showsTechniqueMenu = intensity != nil && followsFinishedEffort
                        // Effort is asked where a technique is offered; elsewhere a rated set keeps a quiet tag.
                        let showsEffortLine = effort != nil && followsFinishedEffort
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
                        let completeSet = {
                            if set.isCompleted {
                                onToggleCompleteSet(index)
                                selectedField = nil
                            } else if canComplete {
                                validationSetId = nil
                                onToggleCompleteSet(index)
                                selectedField = nil
                            } else {
                                validationSetId = set.id
                            }
                        }
                        let setLabel = "\(LanguageManager.t("table.set")) \(set.setNumber)"
                        let weightName = isAssisted ? "\(LanguageManager.t("table.assistance")) (\(weightUnit.label))"
                            : LanguageManager.t(weightUnit == .lbs ? "table.weightLbs" : "table.weightKg")
                        let repsName = LanguageManager.t("table.actualReps")
                        let plateWeight = (WarmupPlateEngine.hasWorkingLoad(set.weightKg) ? set.weightKg : nil)
                            ?? Double(weightBinding.wrappedValue.replacingOccurrences(of: ",", with: ".")).map { weightUnit.toCanonicalKg($0) }
                        // One tap copies the previous occurrence's load and reps, then waits on the reps for Log set.
                        let usePrevious: KeypadShortcut? = {
                            guard !set.isCompleted, let previous, let load = previous.weightKg, load.isFinite, load >= 0,
                                  let count = previous.reps, (1...999).contains(count) else { return nil }
                            return KeypadShortcut(
                                tag: "keypad-previous",
                                description: LanguageManager.t("keypad.usePrevious", ["value": WorkoutSessionUtils.sessionPrAccessibilityLabel(previousText, unit: weightUnit)]),
                                text: previousText, systemImage: "clock.arrow.circlepath",
                                action: {
                                    onUpdateSet(index, WorkoutSessionUtils.formatWeightInput(load, unit: weightUnit, barbell: barbellPlates), "\(count)")
                                    selectedField = Field(id: set.id, weight: false)
                                })
                        }()
                        let tools: [KeypadShortcut] = !warmupToolsUnlocked ? [] : [
                            onInspectPlates.flatMap { inspect in
                                plateWeight.flatMap { WarmupPlateEngine.hasWorkingLoad($0) ? $0 : nil }.map { load in
                                    KeypadShortcut(tag: "keypad-plates", description: LanguageManager.t("warmup.tab_plates"),
                                                   systemImage: "square.stack.3d.up", tint: AppColors.accent, action: { inspect(load) })
                                }
                            },
                            onToggleWarmup.map { toggle in
                                KeypadShortcut(tag: "keypad-warmup",
                                               description: LanguageManager.t(set.isWarmup ? "warmup.convert_to_working" : "warmup.convert_to_warmup"),
                                               systemImage: set.isWarmup ? "dumbbell" : "flame",
                                               tint: set.isWarmup ? AppColors.secondaryText : AppColors.warmupAmber, action: { toggle(index) })
                            }
                        ].compactMap { $0 }
                        let targetRepsHint = set.targetReps.flatMap { (1...999).contains($0) && !set.isCompleted ? $0 : nil }
                        let weightField = KeypadField(
                            id: set.id + ":w", kind: .weight, unit: weightUnit,
                            label: "\(setLabel), \(weightName)", title: "\(setLabel) · \(weightName)",
                            value: weightBinding.wrappedValue, step: loadStep, action: .next,
                            onValue: { weightBinding.wrappedValue = $0 },
                            // Next goes on to the set's reps, like a form.
                            onAction: { selectedField = Field(id: set.id, weight: false) },
                            onDismiss: { selectedField = nil }, previous: usePrevious, tools: tools)
                        let repsField = KeypadField(
                            id: set.id + ":r", kind: .reps, unit: weightUnit,
                            label: "\(setLabel), \(repsName)" + (targetRepsHint.map { ", " + LanguageManager.t("progression.coach.reps_target_hint", ["reps": "\($0)"]) } ?? ""),
                            title: "\(setLabel) · \(repsName)",
                            value: repsBinding.wrappedValue, step: 1, action: set.isCompleted ? .done : .log,
                            onValue: { repsBinding.wrappedValue = $0 },
                            onAction: { if set.isCompleted { selectedField = nil } else { completeSet() } },
                            onDismiss: { selectedField = nil }, previous: usePrevious, tools: tools)

                        // A set and its drops, rest-pause efforts and partials share one container, so they read as one set.
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                VStack(spacing: 1) {
                                    Text(set.isWarmup ? "W\(set.setNumber)" : "\(set.setNumber)")
                                        .font(.app(size: set.isWarmup ? 13 : 14, weight: .bold))
                                        .foregroundStyle(
                                            set.isWarmup
                                                ? AppColors.warmupAmber
                                                : (set.isCompleted
                                                    ? AppColors.accent
                                                    : (isSetEnabled ? AppColors.secondaryText : AppColors.secondaryText.opacity(0.35)))
                                        )
                                    if let effort, !showsEffortLine, !set.isWarmup, let rir = set.rir {
                                        Text(SetEffort.tag(rir, scale: effort.scale))
                                            .font(.app(size: 9, weight: .bold))
                                            .foregroundStyle(AppColors.purple)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .accessibilityLabel(SetEffort.spokenLabel(rir, scale: effort.scale))
                                            .accessibilityIdentifier("effort-tag-\(set.id)")
                                    }
                                }
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
                                    KeypadValueField(field: weightField, keypad: activeKeypad, row: set,
                                                     selected: selectedField == Field(id: set.id, weight: true), enabled: isSetInputEnabled,
                                                     fontSize: weightInputFontSize(KeypadInput.display(weightBinding.wrappedValue), width: geometry.size.width),
                                                     onSelect: { selectedField = Field(id: set.id, weight: true) })
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)

                                // A Smart Progression target is only a hint: the field stays empty until the user enters actual reps.
                                KeypadValueField(field: repsField, keypad: activeKeypad, row: set,
                                                 selected: selectedField == Field(id: set.id, weight: false), enabled: isSetInputEnabled,
                                                 placeholder: targetRepsHint.map(String.init) ?? "0",
                                                 onSelect: { selectedField = Field(id: set.id, weight: false) })

                                Button(action: completeSet) {
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
                        if showsEffortLine, let effort {
                            effortLine(set: set, index: index, actions: effort)
                        }
                        if showsTechniqueMenu, let intensity {
                            techniqueMenu(set: set, index: index, actions: intensity)
                            if let count = IntensitySets.endingCount(sets, at: index) {
                                EndHereRow(set: set, index: index, count: count, actions: intensity)
                            }
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
        .onChange(of: selectedField) { _, value in reveal(value, scrollProxy) }
        .onChange(of: activeKeypad.requestedField, initial: true) { _, id in
            guard let id else { return }
            activeKeypad.consumeRequest()
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            let field = Field(id: parts[0], weight: parts.count > 1 && parts[1] == "w")
            if sets.contains(where: { Self.field(field, belongsTo: $0) }) { selectedField = field }
        }
        .onChange(of: sets.map(\.id)) { _, _ in
            if let selectedField, !sets.contains(where: { Self.field(selectedField, belongsTo: $0) }) { self.selectedField = nil }
        }
        .onAppear { knownExtensionIds = sets.flatMap { $0.extensions?.map(\.id) ?? [] } }
        .onChange(of: sets) { _, latest in
            if let selectedField, !latest.contains(where: { Self.field(selectedField, belongsTo: $0) }) { self.selectedField = nil }
            // A newly added drop or rest-pause effort takes focus, so its numbers can be typed straight away.
            let ids = latest.flatMap { $0.extensions?.map(\.id) ?? [] }
            if let added = ids.first(where: { !knownExtensionIds.contains($0) }),
               let owner = latest.first(where: { $0.extensions?.contains { $0.id == added } == true }) {
                let part = owner.extensions?.first { $0.id == added }
                let wantsWeight = IntensitySets.technique(of: owner) == .drop && (part?.weightInput.isEmpty ?? true)
                selectedField = Field(id: added, weight: wantsWeight)
            }
            knownExtensionIds = ids
        }
        .onChange(of: isRestActive) { _, active in
            if active { self.selectedField = nil }
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

    /// A drop, rest-pause or partials value, edited with the keypad like the set's own fields.
    private func subRowField(_ binding: Binding<String>, field: Field, kind: KeypadKind, label: String, title: String, enabled: Bool,
                             row: ExerciseSetLog, action: KeypadAction, onAction: @escaping () -> Void) -> some View {
        let keypadField = KeypadField(
            id: field.id + (kind == .weight ? ":w" : ":r"), kind: kind, unit: weightUnit, label: label, title: title,
            value: binding.wrappedValue, step: kind == .weight ? loadStep : 1, action: action,
            onValue: { binding.wrappedValue = $0 }, onAction: onAction, onDismiss: { selectedField = nil })
        return KeypadValueField(field: keypadField, keypad: activeKeypad, row: row, selected: selectedField == field, enabled: enabled,
                                onSelect: { selectedField = field })
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
        let tick = {
            if part.isCompleted || canTick {
                validationSetId = nil
                actions.onToggleExtension(index, extensionIndex)
                selectedField = nil
            } else {
                validationSetId = part.id
            }
        }
        return HStack(spacing: 8) {
            subRowMarker(isDrop ? "arrow.down.right" : "pause", enabled: rowEnabled)
            Text(previous)
                .font(.app(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText.opacity(part.isCompleted ? 0.6 : (rowEnabled ? 1 : 0.35)))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 56, alignment: .center)
                .accessibilityLabel(previous)
            if isDrop {
                let weightName = isAssisted ? LanguageManager.t("table.assistance") : LanguageManager.t(weightUnit == .lbs ? "table.weightLbs" : "table.weightKg")
                subRowField(weightBinding, field: Field(id: part.id, weight: true), kind: .weight,
                            label: "\(label), \(weightName)", title: "\(label) · \(weightName)", enabled: inputEnabled, row: set,
                            action: .next, onAction: { selectedField = Field(id: part.id, weight: false) })
            } else {
                // Rest-pause keeps the main part's load.
                Text(displayedWeight(set.weightInput, set.weightKg))
                    .font(.app(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .accessibilityLabel("\(label), \(displayedWeight(set.weightInput, set.weightKg)) \(weightUnit.label)")
            }
            subRowField(repsBinding, field: Field(id: part.id, weight: false), kind: .reps,
                        label: "\(label), \(LanguageManager.t("table.actualReps"))", title: "\(label) · \(LanguageManager.t("table.actualReps"))",
                        enabled: inputEnabled, row: set, action: part.isCompleted ? .done : .log,
                        onAction: { if part.isCompleted { selectedField = nil } else { tick() } })
            Button(action: tick) {
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
            subRowField(binding, field: field, kind: .partials, label: label, title: label, enabled: inputEnabled, row: set,
                        action: .done, onAction: { selectedField = nil })
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

    // MARK: Effort

    /// One line under a finished working set: how many good reps were left. Tapping the chosen value clears it.
    private func effortLine(set: ExerciseSetLog, index: Int, actions: EffortActions) -> some View {
        let title = Text(LanguageManager.t(actions.scale == .rir ? "effort.title.rir" : "effort.title.rpe"))
            .font(.app(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        let chips = HStack(spacing: 5) {
            ForEach(SetEffort.values, id: \.self) { value in
                let selected = set.rir == value
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    actions.onSetEffort(index, selected ? nil : value)
                } label: {
                    Text(SetEffort.chipLabel(value, scale: actions.scale))
                        .font(.app(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? AppColors.purple : AppColors.secondaryText)
                        .frame(minWidth: 40, maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? AppColors.purpleBg : AppColors.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? AppColors.purple.opacity(0.7) : AppColors.border, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SetEffort.spokenLabel(value, scale: actions.scale))
                .accessibilityValue(LanguageManager.t(selected ? "progression.effort.selected" : "progression.effort.not_selected"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(LanguageManager.t("effort.hint"))
                .accessibilityIdentifier("effort-\(set.id)-\(value)")
            }
        }
        // At 320 pt the session card leaves 244 pt: five chips of 44 pt with 5 pt gaps.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { title; chips }
            VStack(alignment: .leading, spacing: 6) { title.padding(.leading, 4); chips }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LanguageManager.t("effort.set", ["set": set.setNumber]))
        .accessibilityIdentifier("effort-line-\(set.id)")
    }

    // MARK: Scrolling

    static func groupId(_ setId: String) -> String { "set-group-" + setId }

    /// Scrolls only as far as needed for the edited set, with its room, to clear the keypad once it has appeared.
    private func reveal(_ field: Field?, _ proxy: ScrollViewProxy) {
        guard let field, let set = sets.first(where: { Self.field(field, belongsTo: $0) }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.groupId(set.id), anchor: nil) }
        }
    }
}

/// Offers to end the exercise after a ticked drop or rest-pause (docs/design/intensity-sets.md). No dismiss:
/// logging the next set removes it. The hint sits beside the button, or above it at accessibility text sizes.
private struct EndHereRow: View {
    let set: ExerciseSetLog
    let index: Int
    let count: Int
    let actions: IntensityActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let hint = LanguageManager.t(IntensitySets.technique(of: set) == .restPause ? "intensity.endHint.restPause" : "intensity.endHint.drop")
        let label = LanguageManager.shared.plural("intensity.endHere", count)
        let layout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Text(hint)
                .font(.app(size: 12))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: dynamicTypeSize >= .xxLarge ? nil : .infinity, alignment: .leading)
            Button { actions.onEndExercise(index) } label: {
                Text(label)
                    .font(.app(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(AppColors.purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 48)
                    .frame(maxWidth: dynamicTypeSize >= .xxLarge ? nil : 156)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(LanguageManager.t("intensity.endHereA11y"))
            .accessibilityIdentifier("end-here-button")
        }
        .padding(.leading, 14)
        .padding(.trailing, dynamicTypeSize >= .xxLarge ? 14 : 6)
        .padding(.vertical, dynamicTypeSize >= .xxLarge ? 10 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("end-here-\(set.id)")
    }
}

/// What the session table needs to log reps in reserve on completed working sets.
public struct EffortActions {
    public let scale: SetEffort.Scale
    /// The set index and its new value; nil clears it.
    public let onSetEffort: (Int, Int?) -> Void

    public init(scale: SetEffort.Scale, onSetEffort: @escaping (Int, Int?) -> Void) {
        self.scale = scale
        self.onSetEffort = onSetEffort
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
    /// End here: removes the unticked working sets after a set finished with a drop or rest-pause.
    public let onEndExercise: (Int) -> Void
}
