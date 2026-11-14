import Foundation

/// A training block wraps the active program for 4–6 calendar weeks (docs/training-blocks.md). Personal state:
/// program files never change. Android `TrainingBlock` stores the same fields.
public struct TrainingBlock: Codable, Hashable {
    public var id: String
    public var programId: String
    /// The ISO week key of week 1.
    public var startWeek: String
    public var length: Int
    /// Up to three muscles that start one set higher.
    public var focus: [String]
    /// Weeks computed so far, week 1 first.
    public var weeks: [TrainingBlockWeek]
    /// Exercise keys in the order sets were added; removals take the most recent first.
    public var additions: [String]
    /// "strength" for a block that peaks lifts for a test; nil builds muscle.
    public var kind: String?
    /// A strength block's lifts, as exercise keys.
    public var lifts: [String]?

    public var isStrength: Bool { kind == TrainingBlockRules.strength }

    public init(id: String, programId: String, startWeek: String, length: Int, focus: [String] = [],
                weeks: [TrainingBlockWeek] = [], additions: [String] = [], kind: String? = nil, lifts: [String]? = nil) {
        self.kind = kind
        self.lifts = lifts
        self.id = id
        self.programId = programId
        self.startWeek = startWeek
        self.length = length
        self.focus = focus
        self.weeks = weeks
        self.additions = additions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        programId = try container.decode(String.self, forKey: .programId)
        startWeek = try container.decode(String.self, forKey: .startWeek)
        length = try container.decode(Int.self, forKey: .length)
        focus = try container.decodeIfPresent([String].self, forKey: .focus) ?? []
        weeks = try container.decodeIfPresent([TrainingBlockWeek].self, forKey: .weeks) ?? []
        additions = try container.decodeIfPresent([String].self, forKey: .additions) ?? []
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lifts = try container.decodeIfPresent([String].self, forKey: .lifts)
    }
}

public struct TrainingBlockWeek: Codable, Hashable {
    /// Working sets by exercise key (`workoutId/exerciseId`).
    public var sets: [String: Int]
    public var changes: [BlockMuscleChange]
    /// Exercise keys whose sets the lifter set by hand.
    public var edited: [String]
    public var reviewed: Bool

    public init(sets: [String: Int] = [:], changes: [BlockMuscleChange] = [], edited: [String] = [], reviewed: Bool = false) {
        self.sets = sets
        self.changes = changes
        self.edited = edited
        self.reviewed = reviewed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sets = try container.decodeIfPresent([String: Int].self, forKey: .sets) ?? [:]
        changes = try container.decodeIfPresent([BlockMuscleChange].self, forKey: .changes) ?? []
        edited = try container.decodeIfPresent([String].self, forKey: .edited) ?? []
        reviewed = try container.decodeIfPresent(Bool.self, forKey: .reviewed) ?? false
    }
}

/// One muscle's weekly sets before and after a week's rules, with the reason codes shown to the lifter.
public struct BlockMuscleChange: Codable, Hashable {
    public var muscle: String
    public var from: Double
    public var to: Double
    public var reasons: [String]

    public init(muscle: String, from: Double, to: Double, reasons: [String] = []) {
        self.muscle = muscle
        self.from = from
        self.to = to
        self.reasons = reasons
    }
}

/// The lifter's answers for one muscle in one workout; each is optional.
public struct MuscleFeedback: Codable, Hashable {
    public var pump: String?
    public var workload: String?
    public var soreness: String?

    public init(pump: String? = nil, workload: String? = nil, soreness: String? = nil) {
        self.pump = pump
        self.workload = workload
        self.soreness = soreness
    }

    public var isEmpty: Bool { pump == nil && workload == nil && soreness == nil }

    public static let pumpCodes = ["low", "moderate", "great"]
    public static let workloadCodes = ["easy", "right", "pushed", "too_much"]
    /// From recovered earliest to still sore.
    public static let sorenessCodes = ["never", "healed_early", "just_in_time", "still_sore"]

    /// Known codes only; nil when nothing valid is left.
    public static func sanitized(_ raw: MuscleFeedback?) -> MuscleFeedback? {
        guard let raw else { return nil }
        let clean = MuscleFeedback(pump: raw.pump.flatMap { pumpCodes.contains($0) ? $0 : nil },
                                   workload: raw.workload.flatMap { workloadCodes.contains($0) ? $0 : nil },
                                   soreness: raw.soreness.flatMap { sorenessCodes.contains($0) ? $0 : nil })
        return clean.isEmpty ? nil : clean
    }
}

/// The training-block rules (docs/training-blocks.md), free of catalog and storage so the shared
/// block-fixtures.json can drive them directly. Android `TrainingBlockRules` matches.
public enum TrainingBlockRules {
    public static let lengths = 4...6
    public static let maxFocus = 3
    /// The deload week's reps in reserve: 4 means 4+.
    public static let deloadRir = 4
    /// An exercise never takes more than this many sets above its week-1 count.
    public static let maxAddedPerExercise = 2
    /// The muscles with a published reference range, in processing order.
    public static let muscles = ["chest", "front-delts", "side-delts", "rear-delts", "biceps", "triceps", "upper-back", "lats",
                                 "abs", "obliques", "quads", "hamstrings", "glutes", "calves"]
    private static let epsilon = 1e-9

    /// Answers for the adjusting muscles only, with known codes; nil when none are left.
    public static func sanitizedFeedback(_ raw: [String: MuscleFeedback]?) -> [String: MuscleFeedback]? {
        var clean: [String: MuscleFeedback] = [:]
        for (muscle, answers) in raw ?? [:] where muscles.contains(muscle) {
            if let answers = MuscleFeedback.sanitized(answers) { clean[muscle] = answers }
        }
        return clean.isEmpty ? nil : clean
    }

    // Strength blocks (docs/training-blocks.md#strength-blocks).
    public static let strength = "strength"
    public static let strengthLengths = 4...8
    public static let maxLifts = 3
    /// The test's singles as percentages of the estimated 1RM.
    public static let testPercents: [Double] = [90, 96, 101]

    public static func lengths(strength: Bool) -> ClosedRange<Int> { strength ? strengthLengths : lengths }

    /// A lift's week: a top set and back-offs, or the test's three singles.
    public struct StrengthWeek: Equatable {
        public var weeksToTest: Int
        public var topReps: Int
        public var topRir: Int
        public var backoffSets: Int
        public var backoffReps: Int
        public var backoffPercent: Double
        public var test: Bool { weeksToTest == 0 }
        public var taper: Bool { weeksToTest == 1 }
        /// The lift's working sets: one top set plus the back-offs, or three singles.
        public var liftSets: Int { test ? testPercents.count : 1 + backoffSets }
        public var liftReps: Int { test ? 1 : topReps }

        /// The row the back-off card sits under: the ticked top set, while a back-off row is open, right above the rows
        /// its Use fills. Nil keeps the card above the set rows (before the top set, and the test's singles).
        public func backoffCardRow(_ sets: [ExerciseSetLog]) -> Int? {
            guard !test, let top = sets.firstIndex(where: { !$0.isWarmup }), sets[top].isCompleted,
                  sets[(top + 1)...].contains(where: { !$0.isWarmup && !$0.isCompleted }) else { return nil }
            return top
        }

        /// Whether ticking row `index` pre-fills the next row. The top set does not: a copy of its load and reps would
        /// sit in the first back-off row, unlike the others, so every back-off row waits for the card's load and reps.
        public func prefillsAfter(_ sets: [ExerciseSetLog], index: Int) -> Bool {
            test || index != sets.firstIndex(where: { !$0.isWarmup })
        }
    }

    public static func strengthWeek(length: Int, week: Int) -> StrengthWeek? {
        guard strengthLengths.contains(length), (1...length).contains(week) else { return nil }
        switch length - week {
        case 0: return StrengthWeek(weeksToTest: 0, topReps: 1, topRir: 0, backoffSets: 0, backoffReps: 1, backoffPercent: 0)
        case 1: return StrengthWeek(weeksToTest: 1, topReps: 2, topRir: 2, backoffSets: 2, backoffReps: 2, backoffPercent: 90)
        case 2: return StrengthWeek(weeksToTest: 2, topReps: 3, topRir: 1, backoffSets: 3, backoffReps: 3, backoffPercent: 90)
        case 3: return StrengthWeek(weeksToTest: 3, topReps: 4, topRir: 2, backoffSets: 3, backoffReps: 4, backoffPercent: 87.5)
        case let toTest: return StrengthWeek(weeksToTest: toTest, topReps: 5, topRir: 2, backoffSets: 3, backoffReps: 5, backoffPercent: 85)
        }
    }

    /// A strength week's sets: the lifts follow the schedule, other exercises halve in the taper and test weeks.
    public static func strengthSets(_ exercises: [(key: String, sets: Int)], lifts: Set<String>, length: Int, week: Int) -> [String: Int] {
        guard let plan = strengthWeek(length: length, week: week) else {
            return Dictionary(exercises.map { ($0.key, $0.sets) }, uniquingKeysWith: { first, _ in first })
        }
        return Dictionary(exercises.map { exercise -> (String, Int) in
            if lifts.contains(exercise.key) { return (exercise.key, plan.liftSets) }
            if plan.weeksToTest <= 1 { return (exercise.key, max(1, Int((Double(exercise.sets) / 2).rounded(.up)))) }
            return (exercise.key, exercise.sets)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The load a set of `reps` with `rir` left implies from an estimated 1RM: Brzycki solved for reps + RIR.
    public static func topSetTarget(e1rm: Double, reps: Int, rir: Int) -> Double { e1rm * Double(37 - reps - rir) / 36 }

    /// Reps-in-reserve targets by week; the last is the deload.
    public static func targets(length: Int) -> [Int] {
        switch length {
        case 4: return [3, 2, 1, deloadRir]
        case 5: return [3, 2, 2, 1, deloadRir]
        case 6: return [3, 3, 2, 1, 1, deloadRir]
        default: return []
        }
    }

    public static func target(length: Int, week: Int) -> Int? {
        let all = targets(length: length)
        return all.indices.contains(week - 1) ? all[week - 1] : nil
    }

    public static func isDeload(length: Int, week: Int) -> Bool { lengths.contains(length) && week == length }

    /// The mid-workout adjustment's window around a week's target. The top answer means 4 or more, so a window stops
    /// at 3 unless the target itself is 4+: in an RIR 3 week, 4+ at the rep ceiling still offers more load.
    public static func window(target: Int) -> ClosedRange<Int> {
        target >= deloadRir ? (target - 1)...target : max(target - 1, 0)...min(target + 1, deloadRir - 1)
    }

    /// One workout exercise as the rules see it, in program order.
    public struct Exercise: Equatable {
        public var key: String
        public var sets: Int
        public var primary: [String]
        public var secondary: [String]
        /// Week 1's count; additions stop two above it.
        public var baseSets: Int
        /// High joint-stress ratings in the block so far.
        public var jointHigh: Int
        public var highThisWeek: Bool
        public var performanceFell: Bool

        public init(key: String, sets: Int, primary: [String], secondary: [String] = [], baseSets: Int? = nil,
                    jointHigh: Int = 0, highThisWeek: Bool = false, performanceFell: Bool = false) {
            self.key = key
            self.sets = sets
            self.primary = primary
            self.secondary = secondary
            self.baseSets = baseSets ?? sets
            self.jointHigh = jointHigh
            self.highThisWeek = highThisWeek
            self.performanceFell = performanceFell
        }

        /// Muscles credited: fewer means a more specific exercise, usually an isolation.
        public var credited: Int { Set(primary + secondary).count }
    }

    public struct Week: Equatable {
        public var sets: [String: Int]
        public var additions: [String]
        public var changes: [BlockMuscleChange]
    }

    /// Volume Matrix credit: 1 per set for a primary muscle, 0.5 for a secondary one that is not also primary.
    public static func weeklySets(_ exercises: [Exercise], sets: [String: Int], muscle: String) -> Double {
        exercises.reduce(0) { total, exercise in
            let count = Double(sets[exercise.key] ?? exercise.sets)
            if exercise.primary.contains(muscle) { return total + count }
            if exercise.secondary.contains(muscle) { return total + count * 0.5 }
            return total
        }
    }

    /// Muscles that adjust: a published reference range and primary in at least one exercise.
    public static func participants(_ exercises: [Exercise]) -> [String] {
        muscles.filter { muscle in exercises.contains { $0.primary.contains(muscle) } }
    }

    private static func range(_ muscle: String) -> (bottom: Double, top: Double) {
        let landmark = VolumeLandmark.defaults[muscle]!
        return (Double(landmark.mev), Double(landmark.mavMax))
    }

    /// Adds one set for `muscle`; returns the exercise key, or the constraint reason that stopped it.
    private static func addOne(_ exercises: [Exercise], sets: inout [String: Int], muscle: String) -> (key: String?, stop: String?) {
        if weeklySets(exercises, sets: sets, muscle: muscle) + 1 > range(muscle).top + epsilon { return (nil, "top_of_range") }
        let candidates = exercises.enumerated().filter { _, exercise in
            exercise.primary.contains(muscle) && !exercise.highThisWeek
                && sets[exercise.key]! < exercise.baseSets + maxAddedPerExercise
        }
        guard let choice = candidates.min(by: { left, right in
            (left.element.jointHigh, left.element.credited, left.offset) < (right.element.jointHigh, right.element.credited, right.offset)
        }) else { return (nil, "no_exercise") }
        sets[choice.element.key]! += 1
        return (choice.element.key, nil)
    }

    /// Removes one set from `muscle`; returns the constraint reason that stopped it, or nil.
    private static func removeOne(_ exercises: [Exercise], sets: inout [String: Int], muscle: String, additions: inout [String]) -> String? {
        if weeklySets(exercises, sets: sets, muscle: muscle) - 1 < range(muscle).bottom - epsilon { return "bottom_of_range" }
        let byKey = Dictionary(exercises.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for index in additions.indices.reversed() {
            let key = additions[index]
            guard let exercise = byKey[key] else { continue }
            if exercise.primary.contains(muscle) && sets[key]! > 1 {
                sets[key]! -= 1
                additions.remove(at: index)
                return nil
            }
        }
        let candidates = exercises.enumerated().filter { _, exercise in exercise.primary.contains(muscle) && sets[exercise.key]! > 1 }
        guard let choice = candidates.max(by: { left, right in
            (sets[left.element.key]!, left.offset) < (sets[right.element.key]!, right.offset)
        }) else { return "no_exercise" }
        sets[choice.element.key]! -= 1
        return nil
    }

    private static func changes(_ exercises: [Exercise], start: [String: Int], sets: [String: Int],
                                reasons: [String: [String]]) -> [BlockMuscleChange] {
        participants(exercises).compactMap { muscle in
            guard let codes = reasons[muscle], !codes.isEmpty else { return nil }
            return BlockMuscleChange(muscle: muscle, from: weeklySets(exercises, sets: start, muscle: muscle),
                                     to: weeklySets(exercises, sets: sets, muscle: muscle), reasons: codes)
        }
    }

    private static func startingSets(_ exercises: [Exercise]) -> [String: Int] {
        Dictionary(exercises.map { ($0.key, $0.sets) }, uniquingKeysWith: { first, _ in first })
    }

    /// Week 1: the program's sets, then one added set for each focus muscle the program trains.
    public static func firstWeek(_ exercises: [Exercise], focus: [String]) -> Week {
        var sets = startingSets(exercises)
        let start = sets
        var additions: [String] = []
        var reasons: [String: [String]] = [:]
        let trained = participants(exercises)
        for muscle in focus.prefix(maxFocus) where trained.contains(muscle) && reasons[muscle] == nil {
            let (key, stop) = addOne(exercises, sets: &sets, muscle: muscle)
            if let key { additions.append(key) }
            reasons[muscle] = ["focus"] + (stop.map { [$0] } ?? [])
        }
        return Week(sets: sets, additions: additions, changes: changes(exercises, start: start, sets: sets, reasons: reasons))
    }

    /// One muscle's week: the most severe soreness and workload, and a low pump only when every pump answer was low.
    public struct Signal: Equatable {
        public var soreness: String
        public var workload: String
        public var pump: String
    }

    public static func signal(_ answers: [MuscleFeedback]) -> Signal {
        let soreness = answers.compactMap(\.soreness).filter(MuscleFeedback.sorenessCodes.contains)
            .max { MuscleFeedback.sorenessCodes.firstIndex(of: $0)! < MuscleFeedback.sorenessCodes.firstIndex(of: $1)! } ?? "just_in_time"
        let workload = answers.compactMap(\.workload).filter(MuscleFeedback.workloadCodes.contains)
            .max { MuscleFeedback.workloadCodes.firstIndex(of: $0)! < MuscleFeedback.workloadCodes.firstIndex(of: $1)! } ?? "right"
        let pumps = answers.compactMap(\.pump).filter(MuscleFeedback.pumpCodes.contains)
        let pump: String
        if pumps.isEmpty { pump = "moderate" } else if pumps.allSatisfy({ $0 == "low" }) { pump = "low" } else { pump = pumps.first { $0 != "low" }! }
        return Signal(soreness: soreness, workload: workload, pump: pump)
    }

    /// A following accumulation week from the previous week's sets, answers and logs.
    public static func nextWeek(_ exercises: [Exercise], feedback: [String: [MuscleFeedback]], additions: [String]) -> Week {
        var sets = startingSets(exercises)
        let start = sets
        var added = additions
        var reasons: [String: [String]] = [:]
        for muscle in participants(exercises) {
            let signal = signal(feedback[muscle] ?? [])
            let remove = (signal.soreness == "still_sore" ? 1 : 0) + (signal.workload == "too_much" ? 1 : 0)
            let fell = exercises.contains { $0.primary.contains(muscle) && $0.performanceFell }
            var codes: [String] = []
            if remove > 0 {
                if signal.soreness == "still_sore" { codes.append("still_sore") }
                if signal.workload == "too_much" { codes.append("too_much") }
                for _ in 0..<remove {
                    if let stop = removeOne(exercises, sets: &sets, muscle: muscle, additions: &added) { codes.append(stop); break }
                }
            } else if fell {
                codes.append("performance")
            } else if ["never", "healed_early"].contains(signal.soreness) && ["easy", "right"].contains(signal.workload) {
                codes.append("recovered")
                let lowPump = signal.pump == "low"
                if lowPump { codes.append("low_pump") }
                for _ in 0..<(lowPump ? 2 : 1) {
                    let (key, stop) = addOne(exercises, sets: &sets, muscle: muscle)
                    if let stop { codes.append(stop); break }
                    added.append(key!)
                }
            }
            if !codes.isEmpty { reasons[muscle] = codes }
        }
        return Week(sets: sets, additions: added, changes: changes(exercises, start: start, sets: sets, reasons: reasons))
    }

    /// The deload: half of each exercise's sets, rounded up, at least one.
    public static func deloadWeek(_ sets: [String: Int]) -> [String: Int] {
        sets.mapValues { max(1, Int((Double($0) / 2).rounded(.up))) }
    }

    /// Whether reps fell at the same loads: against the previous block week's log of the same workout exercise,
    /// the shared leading sets keep their loads and total fewer reps. Sets are (load in kg, reps).
    public static func performanceFell(previous: [(Double, Int)], current: [(Double, Int)]) -> Bool {
        let shared = min(previous.count, current.count)
        guard shared > 0 else { return false }
        let sameLoads = (0..<shared).allSatisfy { abs(previous[$0].0 - current[$0].0) < 1e-6 }
        return sameLoads && current.prefix(shared).reduce(0) { $0 + $1.1 } < previous.prefix(shared).reduce(0) { $0 + $1.1 }
    }
}

/// The optional pre-workout readiness check (docs/training-blocks.md#readiness-check): the lifter's own answers,
/// and what they chose when a lighter day was offered. Each field is optional. Android `ReadinessCheck` matches.
public struct ReadinessCheck: Codable, Hashable {
    public var sleep: String?
    public var energy: String?
    public var soreness: String?
    /// planned, fewer_sets or more_rir; nil until a lighter day is offered and answered.
    public var choice: String?

    public init(sleep: String? = nil, energy: String? = nil, soreness: String? = nil, choice: String? = nil) {
        self.sleep = sleep
        self.energy = energy
        self.soreness = soreness
        self.choice = choice
    }
}

/// Readiness rules; Android `Readiness` matches and the shared block-fixtures.json pins them.
public enum Readiness {
    public static let sleepCodes = ["poor", "ok", "good"]
    public static let energyCodes = ["low", "ok", "high"]
    public static let sorenessCodes = ["none", "some", "a_lot"]
    public static let choices = ["planned", "fewer_sets", "more_rir"]

    public static func sanitized(_ raw: ReadinessCheck?) -> ReadinessCheck? {
        guard let raw else { return nil }
        let clean = ReadinessCheck(sleep: raw.sleep.flatMap { sleepCodes.contains($0) ? $0 : nil },
                                   energy: raw.energy.flatMap { energyCodes.contains($0) ? $0 : nil },
                                   soreness: raw.soreness.flatMap { sorenessCodes.contains($0) ? $0 : nil },
                                   choice: raw.choice.flatMap { choices.contains($0) ? $0 : nil })
        return clean == ReadinessCheck() ? nil : clean
    }

    /// Poor sleep, low energy and a lot of soreness each count; skipped questions do not.
    public static func lows(_ check: ReadinessCheck?) -> Int {
        [check?.sleep == "poor", check?.energy == "low", check?.soreness == "a_lot"].filter { $0 }.count
    }

    /// Two or more low answers offer a lighter day, once.
    public static func offersLighterDay(_ check: ReadinessCheck?) -> Bool { lows(check) >= 2 && check?.choice == nil }

    /// "Train as planned" always first; a higher effort target only inside a block week that is not the deload.
    public static func options(blockTarget: Int?, deload: Bool) -> [String] {
        ["planned", "fewer_sets"] + (blockTarget != nil && !deload ? ["more_rir"] : [])
    }

    /// The block week's target after the lifter's choice; one more rep in reserve, at most 4+.
    public static func target(_ blockTarget: Int?, check: ReadinessCheck?) -> Int? {
        guard let blockTarget, check?.choice == "more_rir" else { return blockTarget }
        return min(blockTarget + 1, SetEffort.maxRir)
    }

    /// One set fewer per exercise: the last working row goes when it is unfinished and not the only one.
    public static func fewerSets(_ draft: ActiveSessionDraft) -> ActiveSessionDraft {
        var copy = draft
        for (exerciseId, rows) in draft.setsByExercise {
            let working = rows.indices.filter { !rows[$0].isWarmup }
            guard working.count > 1, let last = working.last, !rows[last].isCompleted else { continue }
            var kept = rows
            kept.remove(at: last)
            copy.setsByExercise[exerciseId] = kept
            if let index = copy.workout.exercises.firstIndex(where: { $0.id == exerciseId }) {
                copy.workout.exercises[index].sets = (copy.workout.exercises[index].sets ?? working.count) - 1
            }
        }
        return copy
    }
}
