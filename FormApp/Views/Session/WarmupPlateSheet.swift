import SwiftUI

public enum WarmupPlateTab: Int, CaseIterable {
    case warmupRamp = 0
    case plateLoader = 1
}

public struct WarmupPlateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let exerciseName: String
    let initialWorkingWeightKg: Double
    let initialBarType: BarType
    let initialPlatesKg: [Double]
    let unit: WeightUnit
    let initialTab: WarmupPlateTab

    var onInsertWarmupSets: ([ExerciseSetLog]) -> Void
    var onSaveBarType: (BarType) -> Void
    var onSavePlates: ([Double]) -> Void

    @State private var activeTab: WarmupPlateTab
    @State private var selectedBarType: BarType
    @State private var availablePlates: [Double]
    @State private var workingWeightInput: Double
    @State private var plateTargetInput: Double

    public init(
        exerciseName: String,
        initialWorkingWeightKg: Double,
        initialBarType: BarType,
        initialPlatesKg: [Double],
        unit: WeightUnit = .kg,
        initialTab: WarmupPlateTab = .warmupRamp,
        onInsertWarmupSets: @escaping ([ExerciseSetLog]) -> Void,
        onSaveBarType: @escaping (BarType) -> Void,
        onSavePlates: @escaping ([Double]) -> Void
    ) {
        self.exerciseName = exerciseName
        self.initialWorkingWeightKg = initialWorkingWeightKg
        self.initialBarType = initialBarType
        self.initialPlatesKg = initialPlatesKg
        self.unit = unit
        self.initialTab = initialTab
        self.onInsertWarmupSets = onInsertWarmupSets
        self.onSaveBarType = onSaveBarType
        self.onSavePlates = onSavePlates

        let barWeight = initialBarType.weight(unit: unit)
        let defaultWeight = initialWorkingWeightKg > 0.0
            ? (unit == .lbs ? unit.toDisplay(initialWorkingWeightKg) : initialWorkingWeightKg)
            : (barWeight * 2.0)

        _activeTab = State(initialValue: initialTab)
        _selectedBarType = State(initialValue: initialBarType)
        _availablePlates = State(initialValue: initialPlatesKg)
        _workingWeightInput = State(initialValue: defaultWeight)
        _plateTargetInput = State(initialValue: defaultWeight)
    }

    private var ramp: WarmupRamp {
        let workingKg = unit == .lbs ? unit.toCanonicalKg(workingWeightInput) : workingWeightInput
        let barKg = selectedBarType.weightKg
        return WarmupPlateEngine.generateWarmupRamp(
            workingWeightKg: workingKg,
            barWeightKg: barKg,
            availablePlatesKg: availablePlates,
            unit: unit
        )
    }

    private var plateResult: PlateCalculationResult {
        let targetKg = unit == .lbs ? unit.toCanonicalKg(plateTargetInput) : plateTargetInput
        let barKg = selectedBarType.weightKg
        return WarmupPlateEngine.calculatePlates(
            targetWeight: targetKg,
            barWeight: barKg,
            availablePlates: availablePlates,
            unit: unit
        )
    }

    public var body: some View {
        NavigationView {
            ZStack {
                AppColors.background.ignoresSafeArea()

                VStack(spacing: 14) {
                    // Custom Header
                    HStack {
                        HStack(spacing: 8) {
                            ProBadge()
                            Text(LanguageManager.t("warmup.modal_title"))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppColors.text)
                        }

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                                .frame(width: 32, height: 32)
                                .background(AppColors.surfaceRaised)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Tab Switcher Pill
                    HStack(spacing: 0) {
                        tabButton(
                            title: LanguageManager.t("warmup.tab_warmup"),
                            systemImage: "flame.fill",
                            isSelected: activeTab == .warmupRamp,
                            action: { activeTab = .warmupRamp }
                        )

                        tabButton(
                            title: LanguageManager.t("warmup.tab_plates"),
                            systemImage: "square.stack.3d.up.fill",
                            isSelected: activeTab == .plateLoader,
                            action: { activeTab = .plateLoader }
                        )
                    }
                    .padding(3)
                    .background(AppColors.surface)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)

                    // Bar Type Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BarType.allCases, id: \.self) { bType in
                                let isSel = bType == selectedBarType
                                let label = "\(Int(bType.weight(unit: unit))) \(unit.label) \(LanguageManager.t(bType.titleKey))"

                                Button(action: {
                                    selectedBarType = bType
                                    onSaveBarType(bType)
                                }) {
                                    Text(label)
                                        .font(.system(size: 11, weight: isSel ? .bold : .regular))
                                        .foregroundColor(isSel ? AppColors.accent : AppColors.secondaryText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(isSel ? AppColors.positiveBg : AppColors.surface)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(isSel ? AppColors.accent : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Content Area
                    ScrollView {
                        VStack(spacing: 14) {
                            if activeTab == .warmupRamp {
                                warmupRampContent
                            } else {
                                plateLoaderContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .accessibilityIdentifier("warmup-plate-sheet")
    }

    private func tabButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(isSelected ? AppColors.positiveBg : Color.clear)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Warmup Ramp Content
    private var warmupRampContent: some View {
        VStack(spacing: 14) {
            // Target Weight Stepper
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("warmup.working_load_label"))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                    Text("\(WarmupPlateEngine.formatPlateWeight(workingWeightInput)) \(unit.label)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppColors.text)
                }

                Spacer()

                HStack(spacing: 6) {
                    let step = unit == .lbs ? 5.0 : 2.5
                    quickStepButton("-\(WarmupPlateEngine.formatPlateWeight(step * 2))") {
                        workingWeightInput = max(ramp.barWeightKg, workingWeightInput - step * 2)
                    }
                    quickStepButton("-\(WarmupPlateEngine.formatPlateWeight(step))") {
                        workingWeightInput = max(ramp.barWeightKg, workingWeightInput - step)
                    }
                    quickStepButton("+\(WarmupPlateEngine.formatPlateWeight(step))") {
                        workingWeightInput = min(500.0, workingWeightInput + step)
                    }
                    quickStepButton("+\(WarmupPlateEngine.formatPlateWeight(step * 2))") {
                        workingWeightInput = min(500.0, workingWeightInput + step * 2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )

            // Sequence Title
            Text(LanguageManager.t("warmup.sequence_title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Steps List
            VStack(spacing: 8) {
                ForEach(ramp.steps) { step in
                    HStack {
                        HStack(spacing: 10) {
                            // Badge W1, W2 etc.
                            Text("W\(step.setNumber)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(step.isPotentiation ? AppColors.purple : AppColors.warmupAmber)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(step.isPotentiation ? AppColors.purpleBg : AppColors.warmupAmberBg)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke((step.isPotentiation ? AppColors.purple : AppColors.warmupAmber).opacity(0.5), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(WarmupPlateEngine.formatPlateWeight(step.weightKg)) \(unit.label) × \(step.reps)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                Text(LanguageManager.t(step.labelKey))
                                    .font(.system(size: 11))
                                    .foregroundColor(step.isPotentiation ? AppColors.purple : AppColors.secondaryText)
                            }
                        }

                        Spacer()

                        // Plates Preview (clean stacked lines)
                        VStack(alignment: .trailing, spacing: 1) {
                            if let res = step.platesResult, !res.platesPerSide.isEmpty {
                                ForEach(res.platesPerSide, id: \.weight) { p in
                                    Text("\(p.count)×\(WarmupPlateEngine.formatPlateWeight(p.weight))\u{00A0}\(unit.label)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(step.isPotentiation ? AppColors.purple.opacity(0.9) : AppColors.muted)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(LanguageManager.t("warmup.empty_bar"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(AppColors.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(step.isPotentiation ? Color(hex: 0x1E192B) : AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(step.isPotentiation ? AppColors.purple.opacity(0.5) : AppColors.border, lineWidth: 1)
                            )
                    )
                }
            }

            // Insert Sets CTA Button
            Button(action: {
                let generatedSets = ramp.steps.enumerated().map { idx, step in
                    let formattedWeight = WarmupPlateEngine.formatPlateWeight(step.weightKg)
                    return ExerciseSetLog(
                        id: UUID().uuidString,
                        setNumber: idx + 1,
                        weightInput: formattedWeight,
                        repsInput: "\(step.reps)",
                        weightKg: step.weightKg,
                        completedReps: step.reps,
                        isCompleted: false,
                        inputTouched: true,
                        isWarmup: true
                    )
                }
                onInsertWarmupSets(generatedSets)
                dismiss()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text(LanguageManager.t("warmup.insert_sets_cta", ["count": ramp.steps.count]))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(AppColors.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColors.accent)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // MARK: - Plate Loader Content
    private var plateLoaderContent: some View {
        VStack(spacing: 14) {
            // Target Barbell Weight Stepper
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("warmup.target_barbell_weight"))
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.muted)
                    Text("\(WarmupPlateEngine.formatPlateWeight(plateTargetInput)) \(unit.label)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(AppColors.text)
                }

                Spacer()

                HStack(spacing: 6) {
                    let step = unit == .lbs ? 5.0 : 2.5
                    quickStepButton("-\(WarmupPlateEngine.formatPlateWeight(step * 2))") {
                        plateTargetInput = max(plateResult.barWeight, plateTargetInput - step * 2)
                    }
                    quickStepButton("-\(WarmupPlateEngine.formatPlateWeight(step))") {
                        plateTargetInput = max(plateResult.barWeight, plateTargetInput - step)
                    }
                    quickStepButton("+\(WarmupPlateEngine.formatPlateWeight(step))") {
                        plateTargetInput = min(500.0, plateTargetInput + step)
                    }
                    quickStepButton("+\(WarmupPlateEngine.formatPlateWeight(step * 2))") {
                        plateTargetInput = min(500.0, plateTargetInput + step * 2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            )

            // Barbell Visualizer
            BarbellPlateVisualizerView(result: plateResult, unit: unit)

            // Gym Plate Inventory Configuration
            VStack(alignment: .leading, spacing: 8) {
                Text(LanguageManager.t("warmup.available_plates_inventory"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)

                let defaultPlates = WarmupPlateEngine.defaultPlates(unit: unit)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(defaultPlates, id: \.self) { pWeight in
                            let isAvail = availablePlates.contains(pWeight)
                            let pColor = BarbellPlateColors.colorFor(weight: pWeight)

                            Button(action: {
                                if availablePlates.contains(pWeight) {
                                    if availablePlates.count > 1 {
                                        availablePlates.removeAll { $0 == pWeight }
                                    }
                                } else {
                                    availablePlates.append(pWeight)
                                    availablePlates.sort(by: >)
                                }
                                onSavePlates(availablePlates)
                            }) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(isAvail ? pColor : AppColors.muted.opacity(0.3))
                                        .frame(width: 7, height: 7)

                                    Text("\(WarmupPlateEngine.formatPlateWeight(pWeight))\(unit.label)")
                                        .font(.system(size: 12, weight: isAvail ? .bold : .regular))
                                        .foregroundColor(isAvail ? AppColors.text : AppColors.muted.opacity(0.4))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(isAvail ? AppColors.surfaceRaised : AppColors.surface.opacity(0.4))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isAvail ? pColor.opacity(0.6) : AppColors.border.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func quickStepButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 40, height: 34)
                .background(AppColors.surfaceRaised)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
