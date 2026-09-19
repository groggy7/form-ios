import SwiftUI

public enum ProgressionAction: String, CaseIterable, Identifiable {
    case increaseLoad = "increase_load"
    case addReps = "add_reps"
    case holdLoad = "hold_load"
    case deload = "deload"
    case firstSession = "first_session"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .increaseLoad: return "progression.action.increase_load"
        case .addReps: return "progression.action.add_reps"
        case .holdLoad: return "progression.action.hold_load"
        case .deload: return "progression.action.deload"
        case .firstSession: return "progression.action.first_session"
        }
    }

    public var color: Color {
        switch self {
        case .increaseLoad: return Color(hex: 0x20D791)
        case .addReps: return Color(hex: 0x12D8D2)
        case .holdLoad: return Color(hex: 0xFEB447)
        case .deload: return Color(hex: 0xB18AFF)
        case .firstSession: return Color(hex: 0x8F999F)
        }
    }

    public var badgeBgColor: Color {
        switch self {
        case .increaseLoad: return Color(hex: 0x142D29)
        case .addReps: return Color(hex: 0x0C292B)
        case .holdLoad: return Color(hex: 0x2C1E14)
        case .deload: return Color(hex: 0x28203D)
        case .firstSession: return Color(hex: 0x1D2227)
        }
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
        lastSessionSummary: String? = nil
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
    }
}

public struct MesocycleDeloadRecommendation: Equatable {
    public let isRecommended: Bool
    public let consecutiveWeeksTrained: Int
    public let stagnantExercisesCount: Int
    public let headlineKey: String
    public let explanationKey: String

    public init(
        isRecommended: Bool,
        consecutiveWeeksTrained: Int,
        stagnantExercisesCount: Int,
        headlineKey: String,
        explanationKey: String
    ) {
        self.isRecommended = isRecommended
        self.consecutiveWeeksTrained = consecutiveWeeksTrained
        self.stagnantExercisesCount = stagnantExercisesCount
        self.headlineKey = headlineKey
        self.explanationKey = explanationKey
    }
}
