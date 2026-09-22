import Foundation

public enum OnboardingGoal: String, Codable, CaseIterable {
    case bulk
    case cut
    case strength
    case maintain
}

public enum OnboardingExperience: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced
}

public enum OnboardingEquipment: String, Codable, CaseIterable {
    case commercialGym = "commercial_gym"
    case machinesOnly = "machines_only"
    case dumbbellsHome = "dumbbells_home"
}

public enum OnboardingFrequency: Int, Codable, CaseIterable {
    case days3 = 3
    case days4 = 4
    case days5 = 5
    case days6 = 6

    public var defaultWeekdays: [Int] {
        switch self {
        case .days3: return [1, 3, 5]          // Mon, Wed, Fri
        case .days4: return [1, 2, 4, 5]       // Mon, Tue, Thu, Fri
        case .days5: return [1, 2, 4, 5, 6]    // Mon, Tue, Thu, Fri, Sat
        case .days6: return [1, 2, 3, 4, 5, 6] // Mon–Sat
        }
    }
}

public struct OnboardingPreferences: Codable {
    public var goal: OnboardingGoal
    public var experience: OnboardingExperience
    public var equipment: OnboardingEquipment
    public var frequency: OnboardingFrequency
    public var selectedDays: [Int]

    public init(
        goal: OnboardingGoal = .bulk,
        experience: OnboardingExperience = .intermediate,
        equipment: OnboardingEquipment = .commercialGym,
        frequency: OnboardingFrequency = .days4,
        selectedDays: [Int] = []
    ) {
        self.goal = goal
        self.experience = experience
        self.equipment = equipment
        self.frequency = frequency
        self.selectedDays = selectedDays
    }
}

public struct ProgramRecommendation {
    public let targetProgramId: String
    public let program: Program
    public let explanationKey: String
    public let scheduledWeekdays: [Int]
}

public enum OnboardingRecommender {

    public static func recommendProgram(
        preferences: OnboardingPreferences,
        availablePrograms: [Program]
    ) -> ProgramRecommendation {
        let programs = availablePrograms.isEmpty ? AppStore.loadBundledStarterPrograms() : availablePrograms
        guard let firstProgram = programs.first else {
            let fallback = Program(
                id: "full-body-classic",
                name: "Full Body Classic",
                description: "Full body workout routine",
                guidelines: [],
                workouts: []
            )
            let scheduledWeekdays = preferences.selectedDays.isEmpty ? preferences.frequency.defaultWeekdays : preferences.selectedDays.sorted()
            return ProgramRecommendation(
                targetProgramId: fallback.id,
                program: fallback,
                explanationKey: "onboarding.reason.default",
                scheduledWeekdays: scheduledWeekdays
            )
        }

        let targetProgramId: String
        switch preferences.equipment {
        case .dumbbellsHome:
            targetProgramId = "home-forge-dumbbells"
        case .machinesOnly:
            targetProgramId = "machine-foundation"
        case .commercialGym:
            switch preferences.frequency {
            case .days6:
                targetProgramId = "classic-ppl"
            case .days5:
                targetProgramId = "aesthetic-hypertrophy"
            case .days4:
                targetProgramId = (preferences.goal == .strength) ? "powerbuilding-strength" : "upper-lower-balanced"
            case .days3:
                targetProgramId = (preferences.goal == .cut) ? "athletic-performance" : "full-body-classic"
            }
        }

        let explanationKey: String
        switch targetProgramId {
        case "home-forge-dumbbells": explanationKey = "onboarding.reason.homeForge"
        case "machine-foundation": explanationKey = "onboarding.reason.machineFoundation"
        case "classic-ppl": explanationKey = "onboarding.reason.classicPpl"
        case "aesthetic-hypertrophy": explanationKey = "onboarding.reason.aestheticHypertrophy"
        case "powerbuilding-strength": explanationKey = "onboarding.reason.powerbuildingStrength"
        case "upper-lower-balanced": explanationKey = "onboarding.reason.upperLower"
        case "athletic-performance": explanationKey = "onboarding.reason.athleticPerformance"
        case "full-body-classic": explanationKey = "onboarding.reason.fullBodyClassic"
        default: explanationKey = "onboarding.reason.default"
        }

        let matched = programs.first(where: { $0.id == targetProgramId }) ?? firstProgram

        let scheduledWeekdays = preferences.selectedDays.isEmpty ? preferences.frequency.defaultWeekdays : preferences.selectedDays.sorted()

        return ProgramRecommendation(
            targetProgramId: matched.id,
            program: matched,
            explanationKey: explanationKey,
            scheduledWeekdays: scheduledWeekdays
        )
    }
}
