import Foundation

public enum BarType: String, CaseIterable, Codable, Identifiable {
    case olympic20 = "olympic_20"
    case womens15 = "womens_15"
    case technique10 = "technique_10"
    case trapBar25 = "trap_bar_25"

    public var id: String { rawValue }
    public var key: String { rawValue }

    public var titleKey: String {
        switch self {
        case .olympic20: return "bar.olympic_20"
        case .womens15: return "bar.womens_15"
        case .technique10: return "bar.technique_10"
        case .trapBar25: return "bar.trap_bar_25"
        }
    }

    public var weightKg: Double {
        switch self {
        case .olympic20: return 20.0
        case .womens15: return 15.0
        case .technique10: return 10.0
        case .trapBar25: return 25.0
        }
    }

    public var weightLbs: Double {
        switch self {
        case .olympic20: return 45.0
        case .womens15: return 35.0
        case .technique10: return 25.0
        case .trapBar25: return 55.0
        }
    }

    public func weight(unit: WeightUnit) -> Double {
        return unit == .lbs ? weightLbs : weightKg
    }

    public static func fromKey(_ key: String?) -> BarType {
        guard let key = key else { return .olympic20 }
        return BarType(rawValue: key) ?? .olympic20
    }
}

public struct PlateCount: Identifiable, Hashable {
    public var id: String { "\(weight)-\(count)" }
    public var weight: Double
    public var count: Int

    public var totalWeight: Double {
        return weight * Double(count)
    }

    public init(weight: Double, count: Int) {
        self.weight = weight
        self.count = count
    }
}

public struct PlateCalculationResult: Hashable {
    public var targetWeight: Double
    public var barWeight: Double
    public var weightPerSide: Double
    public var platesPerSide: [PlateCount]
    public var totalPlatesWeight: Double
    public var totalAchievedWeight: Double
    public var remainderPerSide: Double
    public var isExactMatch: Bool
    public var displayText: String

    public init(
        targetWeight: Double,
        barWeight: Double,
        weightPerSide: Double,
        platesPerSide: [PlateCount],
        totalPlatesWeight: Double,
        totalAchievedWeight: Double,
        remainderPerSide: Double,
        isExactMatch: Bool,
        displayText: String
    ) {
        self.targetWeight = targetWeight
        self.barWeight = barWeight
        self.weightPerSide = weightPerSide
        self.platesPerSide = platesPerSide
        self.totalPlatesWeight = totalPlatesWeight
        self.totalAchievedWeight = totalAchievedWeight
        self.remainderPerSide = remainderPerSide
        self.isExactMatch = isExactMatch
        self.displayText = displayText
    }
}

public struct WarmupStep: Identifiable, Hashable {
    public var id: Int { setNumber }
    public var setNumber: Int
    public var weightKg: Double
    public var reps: Int
    public var percentage: Int
    public var labelKey: String
    public var isPotentiation: Bool
    public var platesResult: PlateCalculationResult?

    public init(
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        percentage: Int,
        labelKey: String,
        isPotentiation: Bool = false,
        platesResult: PlateCalculationResult? = nil
    ) {
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.percentage = percentage
        self.labelKey = labelKey
        self.isPotentiation = isPotentiation
        self.platesResult = platesResult
    }
}

public struct WarmupRamp: Hashable {
    public var workingWeightKg: Double
    public var barWeightKg: Double
    public var steps: [WarmupStep]

    public init(workingWeightKg: Double, barWeightKg: Double, steps: [WarmupStep]) {
        self.workingWeightKg = workingWeightKg
        self.barWeightKg = barWeightKg
        self.steps = steps
    }
}
