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
    /// The matched program with its workouts already moved onto the scheduled days.
    public let program: Program
    public let explanationKey: String
    public let scheduledWeekdays: [Int]
}

/// Shared Android/iOS onboarding rules. The contract and its rationale live in
/// gym/docs/programs/onboarding-recommendation.md; FormAppTests runs its shared fixtures.
public enum OnboardingRecommender {

    /// Plans whose every session trains the whole body; they need a rest day between sessions.
    private static let fullBodyProgramIds: Set<String> = ["full-body-classic", "machine-foundation", "athletic-performance"]

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
            return ProgramRecommendation(
                targetProgramId: fallback.id,
                program: fallback,
                explanationKey: "onboarding.reason.default",
                scheduledWeekdays: chosenWeekdays(preferences)
            )
        }

        let targetId = targetProgramId(preferences)
        let matched = programs.first(where: { $0.id == targetId }) ?? firstProgram
        let scheduled = schedule(matched, preferences: preferences)

        return ProgramRecommendation(
            targetProgramId: matched.id,
            program: scheduled,
            explanationKey: explanationKey(programId: matched.id),
            scheduledWeekdays: scheduled.workouts.map(\.day).sorted()
        )
    }

    /// Ticked weekdays (Monday = 1), or the frequency answer's defaults when none are ticked.
    public static func chosenWeekdays(_ preferences: OnboardingPreferences) -> [Int] {
        let ticked = Array(Set(preferences.selectedDays.filter { (1...7).contains($0) })).sorted()
        return ticked.isEmpty ? preferences.frequency.defaultWeekdays : ticked
    }

    public static func targetProgramId(_ preferences: OnboardingPreferences) -> String {
        let tickedDays = Set(preferences.selectedDays.filter { (1...7).contains($0) }).count
        let daysPerWeek = tickedDays == 0 ? preferences.frequency.rawValue : min(max(tickedDays, 3), 6)
        let experience = preferences.experience
        switch preferences.equipment {
        case .dumbbellsHome:
            return "home-forge-dumbbells"
        case .machinesOnly:
            return "machine-foundation"
        case .commercialGym:
            if daysPerWeek == 3 {
                return experience == .advanced ? "athletic-performance" : "full-body-classic"
            }
            if experience == .beginner { return "upper-lower-balanced" }
            if preferences.goal == .strength { return "powerbuilding-strength" }
            if daysPerWeek == 4 { return "upper-lower-balanced" }
            if daysPerWeek == 6 && experience == .advanced { return "classic-ppl" }
            return "aesthetic-hypertrophy"
        }
    }

    public static func explanationKey(programId: String) -> String {
        switch programId {
        case "home-forge-dumbbells": return "onboarding.reason.homeForge"
        case "machine-foundation": return "onboarding.reason.machineFoundation"
        case "classic-ppl": return "onboarding.reason.classicPpl"
        case "aesthetic-hypertrophy": return "onboarding.reason.aestheticHypertrophy"
        case "powerbuilding-strength": return "onboarding.reason.powerbuildingStrength"
        case "upper-lower-balanced": return "onboarding.reason.upperLower"
        case "athletic-performance": return "onboarding.reason.athleticPerformance"
        case "full-body-classic": return "onboarding.reason.fullBodyClassic"
        default: return "onboarding.reason.default"
        }
    }

    /// Moves the program's workouts, in weekly order, onto distinct days chosen by `scheduledDays`.
    public static func schedule(_ program: Program, preferences: OnboardingPreferences) -> Program {
        let ordered = program.workouts.enumerated()
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map(\.element)
        guard let days = scheduledDays(
            programDays: ordered.map(\.day),
            chosenDays: chosenWeekdays(preferences),
            fullBody: fullBodyProgramIds.contains(program.id)
        ) else { return program }
        var scheduled = program
        scheduled.workouts = zip(ordered, days).map { workout, day in
            var moved = workout
            moved.day = day
            return moved
        }
        return scheduled
    }

    /// Picks one distinct weekday per workout. The first rule that separates two candidate day
    /// sets decides: full-body plans avoid back-to-back days (Sunday to Monday included), then the
    /// most chosen days, the shortest run of consecutive days, the most of the program's own days,
    /// and finally the earliest days. Returns nil when the workouts cannot each get a weekday.
    static func scheduledDays(programDays: [Int], chosenDays: [Int], fullBody: Bool) -> [Int]? {
        let count = programDays.count
        guard count > 0, count <= 7 else { return nil }
        let chosen = Set(chosenDays)
        let own = Set(programDays)
        var best: [Int]?
        var bestScore: [Int] = []
        // Candidates arrive in lexicographic order, so keeping the first best prefers earlier days.
        for days in weekdayCombinations(count) {
            let score = [
                fullBody && !hasBackToBackDays(days) ? 1 : 0,
                days.filter { chosen.contains($0) }.count,
                -longestConsecutiveRun(days),
                days.filter { own.contains($0) }.count
            ]
            if best == nil || bestScore.lexicographicallyPrecedes(score) {
                best = days
                bestScore = score
            }
        }
        return best
    }

    private static func weekdayCombinations(_ count: Int) -> [[Int]] {
        var result: [[Int]] = []
        func build(_ first: Int, _ days: [Int]) {
            if days.count == count {
                result.append(days)
                return
            }
            guard first <= 7 else { return }
            for day in first...7 { build(day + 1, days + [day]) }
        }
        build(1, [])
        return result
    }

    private static func nextWeekday(_ day: Int) -> Int { day == 7 ? 1 : day + 1 }

    private static func hasBackToBackDays(_ days: [Int]) -> Bool {
        days.contains { days.contains(nextWeekday($0)) }
    }

    private static func longestConsecutiveRun(_ days: [Int]) -> Int {
        if days.count == 7 { return 7 }
        let set = Set(days)
        return days.filter { !set.contains($0 == 1 ? 7 : $0 - 1) }.map { start in
            var length = 1
            var day = nextWeekday(start)
            while set.contains(day) {
                length += 1
                day = nextWeekday(day)
            }
            return length
        }.max() ?? 0
    }
}
