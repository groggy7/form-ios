import SwiftUI

public enum ProgressionAction: String, CaseIterable, Identifiable {
    case increaseLoad = "increase_load"
    case addReps = "add_reps"
    case holdLoad = "hold_load"
    case deload = "deload"
    case firstSession = "first_session"
    case insufficientData = "insufficient_data"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .increaseLoad: return "progression.action.increase_load"
        case .addReps: return "progression.action.add_reps"
        case .holdLoad: return "progression.action.hold_load"
        case .deload: return "progression.action.deload"
        case .firstSession: return "progression.action.first_session"
        case .insufficientData: return "progression.action.insufficient_data"
        }
    }

    public var color: Color {
        if !ThemeManager.shared.currentTheme.isDark {
            switch self {
            case .increaseLoad: return AppColors.historyStatPrGreen
            case .addReps: return AppColors.historyStatCyan
            case .holdLoad: return AppColors.warmupAmber
            case .deload: return AppColors.purple
            case .firstSession, .insufficientData: return AppColors.muted
            }
        }
        switch self {
        case .increaseLoad: return Color(hex: 0x20D791)
        case .addReps: return Color(hex: 0x12D8D2)
        case .holdLoad: return Color(hex: 0xFEB447)
        case .deload: return Color(hex: 0xB18AFF)
        case .firstSession, .insufficientData: return Color(hex: 0x8F999F)
        }
    }

    public var badgeBgColor: Color {
        if !ThemeManager.shared.currentTheme.isDark {
            switch self {
            case .increaseLoad: return AppColors.completedSurface
            case .addReps: return Color(hex: 0xE3EBED)
            case .holdLoad: return AppColors.warmupAmberBg
            case .deload: return AppColors.purpleBg
            case .firstSession, .insufficientData: return AppColors.surfaceRaised
            }
        }
        switch self {
        case .increaseLoad: return Color(hex: 0x142D29)
        case .addReps: return Color(hex: 0x0C292B)
        case .holdLoad: return Color(hex: 0x2C1E14)
        case .deload: return Color(hex: 0x28203D)
        case .firstSession, .insufficientData: return Color(hex: 0x1D2227)
        }
    }
}

public struct ProgressionSetTarget: Equatable {
    public let weightKg: Double?
    public let reps: Int

    public init(weightKg: Double?, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }

    private var validWeightKg: Double? {
        guard let weightKg, weightKg.isFinite, weightKg >= 0 else { return nil }
        return weightKg
    }

    public func weightInput(unit: WeightUnit, fallback: String) -> String {
        validWeightKg.map(unit.formatExactWeight) ?? fallback
    }

    /// Apply stores the canonical target load itself; the input text only represents it, so no rounding reaches the log.
    /// Reps stay the user's: the target is a placeholder hint, so a target is never recorded as performance by default.
    public func applied(to set: ExerciseSetLog, unit: WeightUnit) -> ExerciseSetLog {
        var applied = set
        applied.weightInput = weightInput(unit: unit, fallback: set.weightInput)
        applied.weightKg = validWeightKg ?? set.weightKg
        applied.targetReps = reps
        applied.inputTouched = true
        return applied
    }
}

/// The user's optional report after an exercise's working sets; logs alone cannot show effort.
public enum ProgressionEffort: String, CaseIterable {
    case easy, right, hard

    public var labelKey: String { "progression.effort.\(rawValue)" }
}

/// The smallest load increases the user's equipment supports, as display values in each unit.
/// Bars use a pair of the smallest plate in that unit's inventory, counted from the selected bar.
public struct ProgressionLoadSteps: Equatable {
    public static let defaultDumbbellKg = 2.0
    public static let defaultDumbbellLbs = 5.0
    public static let defaultMachineKg = 5.0
    public static let defaultMachineLbs = 10.0
    public static let dumbbellKgOptions = [1.0, 2.0, 2.5]
    public static let dumbbellLbsOptions = [2.5, 5.0]
    public static let machineKgOptions = [2.5, 5.0]
    public static let machineLbsOptions = [5.0, 10.0]

    public let dumbbellKg: Double
    public let dumbbellLbs: Double
    public let machineKg: Double
    public let machineLbs: Double
    public let smallestPlateKg: Double
    public let smallestPlateLbs: Double
    public let barType: BarType

    public init(dumbbellKg: Double = defaultDumbbellKg, dumbbellLbs: Double = defaultDumbbellLbs,
                machineKg: Double = defaultMachineKg, machineLbs: Double = defaultMachineLbs, smallestPlateKg: Double = 1.25,
                smallestPlateLbs: Double = 2.5, barType: BarType = .olympic20) {
        self.dumbbellKg = dumbbellKg
        self.dumbbellLbs = dumbbellLbs
        self.machineKg = machineKg
        self.machineLbs = machineLbs
        self.smallestPlateKg = smallestPlateKg
        self.smallestPlateLbs = smallestPlateLbs
        self.barType = barType
    }

    /// Values outside the offered options fall back to the defaults.
    public static func from(dumbbellKg: Double, dumbbellLbs: Double, machineKg: Double, machineLbs: Double, platesKg: [Double],
                            platesLbs: [Double] = [], barType: BarType = .olympic20) -> ProgressionLoadSteps {
        ProgressionLoadSteps(
            dumbbellKg: dumbbellKgOptions.contains(dumbbellKg) ? dumbbellKg : defaultDumbbellKg,
            dumbbellLbs: dumbbellLbsOptions.contains(dumbbellLbs) ? dumbbellLbs : defaultDumbbellLbs,
            machineKg: machineKgOptions.contains(machineKg) ? machineKg : defaultMachineKg,
            machineLbs: machineLbsOptions.contains(machineLbs) ? machineLbs : defaultMachineLbs,
            smallestPlateKg: platesKg.filter { $0.isFinite && $0 > 0 }.min() ?? 1.25,
            smallestPlateLbs: platesLbs.filter { $0.isFinite && $0 > 0 }.min() ?? 2.5,
            barType: barType)
    }

    public func bar(_ unit: WeightUnit) -> Double? {
        let smallest = unit == .lbs ? smallestPlateLbs : smallestPlateKg
        return smallest > 0 ? smallest * 2 : nil
    }
    /// Bar loads are the bar plus plate pairs, so the bar step's grid starts at the bar's weight.
    public func barOrigin(_ unit: WeightUnit) -> Double { barType.weight(unit: unit) }
    public func dumbbell(_ unit: WeightUnit) -> Double { unit == .lbs ? dumbbellLbs : dumbbellKg }
    public func machine(_ unit: WeightUnit) -> Double { unit == .lbs ? machineLbs : machineKg }
    public func bodyweight(_ unit: WeightUnit) -> Double { unit == .lbs ? 5 : 2.5 }
}

/// The active workout day and current time, as the session screen sees them.
public struct ProgressionContext: Equatable {
    public let programId: String
    public let workoutId: String
    public let now: Date

    public init(programId: String, workoutId: String, now: Date) {
        self.programId = programId
        self.workoutId = workoutId
        self.now = now
    }
}

public struct ProgressionLoggingProgress: Equatable {
    public let recordedSets: Int
    public let totalSets: Int
    public var remainingSets: Int { totalSets - recordedSets }

    public static func from(sets: [ExerciseSetLog]) -> ProgressionLoggingProgress {
        let workingSets = sets.filter { !$0.isWarmup }
        return ProgressionLoggingProgress(recordedSets: workingSets.filter { $0.isCompleted }.count, totalSets: workingSets.count)
    }
}

public struct ExerciseProgressionRecommendation: Equatable {
    public let exerciseId: String
    public let exerciseName: String
    public let action: ProgressionAction
    public let suggestedWeightKg: Double?
    public let suggestedWeightDisplay: String
    public let suggestedRepsMin: Int
    public let suggestedRepsMax: Int
    public let weightDeltaDisplay: String?
    public let rationaleKey: String
    public let rationaleArgs: [String: String]
    public let isPlateau: Bool
    public let consecutiveStagnantSessions: Int
    public let suggestedVariationId: String?
    public let suggestedVariationName: String?
    public let lastSessionSummary: String?
    public let setTargets: [ProgressionSetTarget]
    public let lastSessionSets: [ProgressionSetTarget]

    public init(
        exerciseId: String,
        exerciseName: String,
        action: ProgressionAction,
        suggestedWeightKg: Double?,
        suggestedWeightDisplay: String,
        suggestedRepsMin: Int,
        suggestedRepsMax: Int,
        weightDeltaDisplay: String? = nil,
        rationaleKey: String,
        rationaleArgs: [String: String] = [:],
        isPlateau: Bool = false,
        consecutiveStagnantSessions: Int = 0,
        suggestedVariationId: String? = nil,
        suggestedVariationName: String? = nil,
        lastSessionSummary: String? = nil,
        setTargets: [ProgressionSetTarget] = [],
        lastSessionSets: [ProgressionSetTarget] = []
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.action = action
        self.suggestedWeightKg = suggestedWeightKg
        self.suggestedWeightDisplay = suggestedWeightDisplay
        self.suggestedRepsMin = suggestedRepsMin
        self.suggestedRepsMax = suggestedRepsMax
        self.weightDeltaDisplay = weightDeltaDisplay
        self.rationaleKey = rationaleKey
        self.rationaleArgs = rationaleArgs
        self.isPlateau = isPlateau
        self.consecutiveStagnantSessions = consecutiveStagnantSessions
        self.suggestedVariationId = suggestedVariationId
        self.suggestedVariationName = suggestedVariationName
        self.lastSessionSummary = lastSessionSummary
        self.setTargets = setTargets
        self.lastSessionSets = lastSessionSets
    }

    /// Match working-set positions, never warmups, completed rows or added sets.
    public func applicableTargets(sets: [ExerciseSetLog]) -> [Int: ProgressionSetTarget] {
        let workingIndices = sets.indices.filter { !sets[$0].isWarmup }
        guard !setTargets.isEmpty, workingIndices.count == setTargets.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: workingIndices.enumerated().compactMap { ordinal, index in
            sets[index].isCompleted ? nil : (index, setTargets[ordinal])
        })
    }
}
