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

public enum OnboardingFrequency: Int, Codable, CaseIterable {
    case days2 = 2
    case days3 = 3
    case days4 = 4
    case days5 = 5
    case days6 = 6

    public var defaultWeekdays: [Int] {
        switch self {
        case .days2: return [1, 4]             // Mon, Thu
        case .days3: return [1, 3, 5]          // Mon, Wed, Fri
        case .days4: return [1, 2, 4, 5]       // Mon, Tue, Thu, Fri
        case .days5: return [1, 2, 4, 5, 6]    // Mon, Tue, Thu, Fri, Sat
        case .days6: return [1, 2, 3, 4, 5, 6] // Mon–Sat
        }
    }
}
