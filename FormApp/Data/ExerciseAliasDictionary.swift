import Foundation

public enum ExerciseAliasDictionary {

    private static let staticAliases: [String: String] = [
        // Chest & Pressing
        "bench press (barbell)": "Barbell Bench Press",
        "bench press (dumbbell)": "Dumbbell Bench Press",
        "incline bench press (barbell)": "Incline Barbell Bench Press",
        "incline bench press (dumbbell)": "Incline Dumbbell Bench Press",
        "decline bench press (barbell)": "Barbell Decline Bench Press",
        "close grip bench press (barbell)": "Barbell Close Grip Bench Press",
        "overhead press (barbell)": "Barbell Seated Overhead Press",
        "shoulder press (dumbbell)": "Dumbbell Seated Shoulder Press",
        "shoulder press (barbell)": "Barbell Seated Overhead Press",
        "chest fly (dumbbell)": "Dumbbell Flat Fly",
        "chest fly (cable)": "Cable Middle Chest Fly",
        "cable crossover": "Cable Middle Chest Fly",
        "dips": "Parallel Bar Dips",
        "dips (bodyweight)": "Parallel Bar Dips",
        "dips (chest)": "Parallel Bar Dips",
        "push up": "Push-up",
        "push up (bodyweight)": "Push-up",
        "push-ups": "Push-up",

        // Back & Pulling
        "lat pulldown (cable)": "Lat Pulldown",
        "lat pulldown": "Lat Pulldown",
        "cable lat pulldown": "Lat Pulldown",
        "pull up": "Pull-up",
        "pull up (bodyweight)": "Pull-up",
        "pull-ups": "Pull-up",
        "chin up": "Chin-up",
        "chin up (bodyweight)": "Chin-up",
        "chin-ups": "Chin-up",
        "bent over row (barbell)": "Barbell Row",
        "barbell row": "Barbell Row",
        "bent over row (dumbbell)": "Dumbbell Bent Over Row",
        "seated cable row": "Cable Seated Row",
        "cable row": "Cable Seated Row",
        "face pull (cable)": "Face Pull",
        "face pull": "Face Pull",
        "t-bar row": "T-Bar Row",
        "t bar row": "T-Bar Row",
        "shrug (barbell)": "Barbell Shrug",
        "shrug (dumbbell)": "Dumbbell Shrug",

        // Legs & Lower Body
        "squat (barbell)": "Barbell Back Squat",
        "back squat (barbell)": "Barbell Back Squat",
        "front squat (barbell)": "Barbell Front Squat",
        "deadlift (barbell)": "Deadlift",
        "deadlift": "Deadlift",
        "romanian deadlift (barbell)": "Barbell Romanian Deadlift",
        "romanian deadlift (dumbbell)": "Dumbbell Romanian Deadlift",
        "sumo deadlift (barbell)": "Barbell Sumo Deadlift",
        "leg press": "Leg Press",
        "leg press (machine)": "Leg Press",
        "leg extension (machine)": "Leg Extension",
        "leg extension": "Leg Extension",
        "lying leg curl (machine)": "Lying Leg Curl",
        "leg curl (machine)": "Lying Leg Curl",
        "seated leg curl (machine)": "Seated Leg Curl",
        "calf raise (machine)": "Barbell Standing Calf Raise",
        "standing calf raise (machine)": "Barbell Standing Calf Raise",
        "standing calf raise": "Barbell Standing Calf Raise",
        "seated calf raise (machine)": "Seated Calf Raise",
        "bulgarian split squat": "Bulgarian Split Squat",
        "bulgarian split squat (dumbbell)": "Bulgarian Split Squat",
        "goblet squat": "Goblet Squat",
        "goblet squat (dumbbell)": "Goblet Squat",
        "hip thrust (barbell)": "Barbell Hip Thrust",
        "hip thrust": "Barbell Hip Thrust",

        // Arms & Shoulders
        "bicep curl (dumbbell)": "Dumbbell Bicep Curl",
        "bicep curl (barbell)": "Barbell Curl",
        "bicep curl (cable)": "Cable Curl",
        "dumbbell curl": "Dumbbell Bicep Curl",
        "barbell curl": "Barbell Curl",
        "hammer curl (dumbbell)": "Dumbbell Hammer Curl",
        "incline dumbbell curl": "Incline Dumbbell Curl",
        "preacher curl (barbell)": "Barbell Preacher Curl",
        "preacher curl (ez bar)": "EZ-Bar Preacher Curl",
        "lateral raise (dumbbell)": "Dumbbell Lateral Raise",
        "lateral raise (cable)": "Cable Lateral Raise",
        "lateral raise": "Dumbbell Lateral Raise",
        "triceps pushdown (cable)": "Cable Triceps Pushdown",
        "tricep pushdown (cable)": "Cable Triceps Pushdown",
        "cable pushdown": "Cable Triceps Pushdown",
        "skull crusher (barbell)": "Barbell Skull Crusher",
        "skullcrusher (barbell)": "Barbell Skull Crusher",
        "triceps extension (dumbbell)": "Dumbbell Overhead Triceps Extension",

        // Core
        "ab wheel rollout": "Ab Wheel Rollout",
        "hanging knee raise": "Hanging Knee Raise",
        "hanging leg raise": "Hanging Knee Raise",
        "plank": "Plank"
    ]

    private static let suffixRegex = try! NSRegularExpression(
        pattern: #"^(.*?)\s*\((barbell|dumbbell|cable|machine|bodyweight|smith machine|smith|band)\)$"#,
        options: .caseInsensitive
    )

    public static func resolve(rawName: String, canonicalNames: [String]) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawName }
        let normalized = trimmed.lowercased()

        // 1. Direct case-insensitive match
        if let direct = canonicalNames.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return direct
        }

        // 2. Static alias lookup
        if let alias = staticAliases[normalized] {
            if let matchedCanonical = canonicalNames.first(where: { $0.caseInsensitiveCompare(alias) == .orderedSame }) {
                return matchedCanonical
            }
            return alias
        }

        // 3. Heuristic matching by stripping equipment parentheticals: "Bench Press (Barbell)" -> "Barbell Bench Press"
        let range = NSRange(location: 0, length: normalized.utf16.count)
        if let match = suffixRegex.firstMatch(in: normalized, options: [], range: range),
           let r1 = Range(match.range(at: 1), in: normalized),
           let r2 = Range(match.range(at: 2), in: normalized) {
            let baseName = String(normalized[r1]).trimmingCharacters(in: .whitespaces)
            let equip = String(normalized[r2]).trimmingCharacters(in: .whitespaces).lowercased()

            let equipPrefix: String
            switch equip {
            case "barbell": equipPrefix = "barbell "
            case "dumbbell": equipPrefix = "dumbbell "
            case "cable": equipPrefix = "cable "
            case "machine": equipPrefix = "machine "
            default: equipPrefix = ""
            }

            if !equipPrefix.isEmpty {
                let candidatePrefixed = equipPrefix + baseName
                if let matchPrefixed = canonicalNames.first(where: { $0.caseInsensitiveCompare(candidatePrefixed) == .orderedSame }) {
                    return matchPrefixed
                }
            }

            if let matchBase = canonicalNames.first(where: { $0.caseInsensitiveCompare(baseName) == .orderedSame }) {
                return matchBase
            }
        }

        return trimmed
    }
}
