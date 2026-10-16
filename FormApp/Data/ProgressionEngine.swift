import Foundation

public enum ProgressionEngine {
    /// A latest log older than this is repeated before any progression.
    static let staleBaselineDays: Double = 28
    /// Two ceiling sessions confirm a load increase only this close together.
    static let confirmationWindowDays: Double = 21
    /// Load steps up to this share of the logged load keep the ceiling reps.
    static let keepRepsStepShare = 0.10
    /// Larger steps, up to this share, aim for the range minimum; beyond it the step is withheld.
    static let resetRepsStepShare = 0.25
    /// An optional lighter week uses at most this share of each logged load.
    static let lighterWeekShare = 0.90
    private static let daySeconds: Double = 86_400
    private static let epsilon = 1e-9

    /// Plateau ideas: a comparable alternative, never swapped automatically.
    public static let variationSwaps: [String: (id: String, name: String)] = [
        "barbell-bench-press": ("incline-dumbbell-press", "Incline Dumbbell Press"),
        "incline-barbell-bench-press": ("dumbbell-bench-press", "Dumbbell Bench Press"),
        "dumbbell-bench-press": ("barbell-bench-press", "Barbell Bench Press"),
        "barbell-back-squat": ("leg-press", "Leg Press"),
        "barbell-front-squat": ("goblet-squat", "Goblet Squat"),
        "conventional-barbell-deadlift": ("trap-bar-deadlift", "Trap Bar Deadlift"),
        "barbell-romanian-deadlift": ("dumbbell-romanian-deadlift", "Dumbbell Romanian Deadlift"),
        "barbell-row": ("chest-supported-dumbbell-row", "Chest-Supported Dumbbell Row"),
        "standing-barbell-overhead-press": ("dumbbell-seated-shoulder-press", "Dumbbell Seated Shoulder Press"),
        "pull-ups": ("lat-pulldown", "Lat Pulldown"),
        "lat-pulldown": ("pull-ups", "Pull-Ups"),
        "ez-bar-curl": ("incline-dumbbell-curl", "Incline Dumbbell Curl"),
        "rope-triceps-pressdown": ("overhead-cable-triceps-extension", "Overhead Cable Triceps Extension")
    ]

    /// A harder variation of the same pattern once a bodyweight rep ceiling is confirmed.
    public static let bodyweightLadder: [String: (id: String, name: String)] = [
        "incline-push-up": ("push-ups", "Push-Ups"),
        "push-ups": ("decline-push-up", "Decline Push-Up"),
        "decline-push-up": ("archer-push-up", "Archer Push-Up"),
        "pike-push-up": ("handstand-push-up", "Handstand Push-Up"),
        "bench-dip": ("chest-dip", "Chest Dip"),
        "chest-dip": ("ring-dip", "Ring Dip"),
        "scapular-pull-up": ("pull-ups", "Pull-Ups"),
        "pull-ups": ("weighted-pull-ups", "Weighted Pull-Ups"),
        "reverse-crunch": ("hanging-knee-raise", "Hanging Knee Raise"),
        "hanging-knee-raise": ("hanging-leg-raise", "Hanging Leg Raise"),
        "hanging-leg-raise": ("hanging-toes-to-bar", "Hanging Toes-to-Bar"),
        "bodyweight-squat": ("bulgarian-split-squat", "Bulgarian Split Squat"),
        "heel-elevated-bodyweight-squat": ("bulgarian-split-squat", "Bulgarian Split Squat"),
        "bodyweight-rear-lunge": ("bulgarian-split-squat", "Bulgarian Split Squat"),
        "side-lunge": ("cossack-squat", "Cossack Squat"),
        "bodyweight-frog-hip-thrust": ("single-leg-hip-thrust", "Single-Leg Hip Thrust"),
        "bodyweight-standing-calf-raise": ("single-leg-calf-raise", "Single-Leg Calf Raise")
    ]

    private static let prescriptionRepsRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:\d+\s*[×x]\s*)?(\d+)(?:\s*[-–—]\s*(\d+))?\s*(?:reps?)?(?:\s*/\s*(?:side|leg|arm))?\s*$"#,
        options: .caseInsensitive
    )

    public static func parseRepRange(exercise: Exercise) -> (min: Int, max: Int)? {
        if let reps = exercise.reps {
            if reps.toFailure { return nil }
            guard let minR = reps.min ?? reps.max else { return nil }
            let maxR = reps.max ?? minR
            guard (1...999).contains(minR), (1...999).contains(maxR) else { return nil }
            return (min(minR, maxR), max(minR, maxR))
        }
        let presc = exercise.prescription
        let nsPresc = presc as NSString
        let fullRange = NSRange(location: 0, length: nsPresc.length)

        guard let match = prescriptionRepsRegex?.firstMatch(in: presc, range: fullRange),
              match.range(at: 1).location != NSNotFound,
              let minVal = Int(nsPresc.substring(with: match.range(at: 1))) else { return nil }
        let maxVal: Int
        if match.range(at: 2).location == NSNotFound {
            maxVal = minVal
        } else {
            guard let parsedMax = Int(nsPresc.substring(with: match.range(at: 2))) else { return nil }
            maxVal = parsedMax
        }
        guard (1...999).contains(minVal), (1...999).contains(maxVal) else { return nil }
        return (min(minVal, maxVal), max(minVal, maxVal))
    }

    private struct HistoricalSessionSets {
        let sets: [SessionSetLog]
        let targetSets: Int?
        let ambiguous: Bool
        let date: Date?
        /// Working sets in the prescription saved with that session, when it names this exercise once.
        let prescribedSets: Int?
        let effort: ProgressionEffort?
        var workingSets: [SessionSetLog] { sets.filter { !$0.isWarmup }.sorted { $0.setNumber < $1.setNumber } }
    }

    /// The baseline a session provides for a plan of `expected` working sets.
    private enum Baseline {
        /// `padded` repeats the last set for sets added to the plan since that session.
        case full(sets: [SessionSetLog], padded: Bool, logged: Int)
        case partial(logged: Int)
        case ambiguous
        case invalid
    }

    private static func findHistoricalSessions(exercise: Exercise, history: [WorkoutSessionRecord]) -> [HistoricalSessionSets] {
        var seen = Set<String>()
        // Parsed time, newest first; an unreadable timestamp sorts after readable ones, then by its text.
        let ordered = history.filter { seen.insert($0.id).inserted }
            .map { record -> (WorkoutSessionRecord, String, Date?) in
                let timestamp = record.completedAt.isEmpty ? record.startedAt : record.completedAt
                return (record, timestamp, WorkoutCalendar.parseIsoTimestamp(timestamp))
            }
            .enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (lhs.element, rhs.element)
                switch (l.2, r.2) {
                case let (left?, right?) where left != right: return left > right
                case (.some, .none): return true
                case (.none, .some): return false
                default: return l.1 != r.1 ? l.1 > r.1 : lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        return ordered.compactMap { record, _, date in
            let logs = record.exerciseLogs.filter {
                ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.exerciseName)
            }
            // An exercise skipped entirely is not an occurrence. Warmups without working sets are
            // an incomplete one, so they block a recommendation instead of being passed over.
            guard logs.contains(where: { !$0.sets.isEmpty }) else { return nil }
            let prescribed = (record.workoutSnapshot?.exercises ?? []).filter {
                ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.name)
            }
            let single = logs.count == 1 ? logs[0] : nil
            return HistoricalSessionSets(sets: logs.flatMap { $0.sets }, targetSets: single?.targetSets, ambiguous: logs.count != 1, date: date,
                                         prescribedSets: prescribed.count == 1 ? WorkoutSessionUtils.initialSetCount(exercise: prescribed[0]) : nil,
                                         effort: ProgressionEffort(rawValue: single?.effort ?? ""))
        }
    }

    /// A workout day uses its own history, and another day's only when the prescription saved with
    /// that session has the same working-set count and rep range. Without a saved prescription it is not shared.
    private static func sharesTrack(_ record: WorkoutSessionRecord, exercise: Exercise, repRange: (min: Int, max: Int), expectedSets: Int,
                                    context: ProgressionContext) -> Bool {
        if record.programId == context.programId && record.workoutId == context.workoutId { return true }
        let prescribed = (record.workoutSnapshot?.exercises ?? []).filter {
            ExerciseCatalog.sameExercise(leftId: exercise.exerciseId, leftName: exercise.name, rightId: $0.exerciseId, rightName: $0.name)
        }
        guard prescribed.count == 1, let range = parseRepRange(exercise: prescribed[0]) else { return false }
        return range == repRange && WorkoutSessionUtils.initialSetCount(exercise: prescribed[0]) == expectedSets
    }

    private static func canonicalId(_ exercise: Exercise) -> String {
        ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name) ?? ExerciseCatalog.key(exercise.name)
    }

    private struct LoadStep { let display: Double; let relativeLimit: Bool }

    /// The smallest supported increase in `unit`, or nil when the app must not invent one.
    private static func loadStep(_ exercise: Exercise, loadsKg: [Double], unit: WeightUnit, steps: ProgressionLoadSteps) -> LoadStep? {
        if WorkoutSessionUtils.isAssisted(exercise) { return nil }
        // Body mass is unknown, so weighted bodyweight variants step their added load without a relative limit.
        if WorkoutSessionUtils.usesBodyweightResistance(exercise) {
            return !loadsKg.isEmpty && loadsKg.allSatisfy({ $0 > 0 }) ? LoadStep(display: steps.bodyweight(unit), relativeLimit: false) : nil
        }
        let step: Double?
        switch EquipmentCatalog.shared.categoryId(canonicalId(exercise)) {
        case "bar": step = steps.bar(unit)
        case "dumbbell": step = steps.dumbbell(unit)
        case "machine": step = steps.machine(unit)
        default: step = nil // Bodyweight, kettlebells, plates, bands and unknown equipment have no inferred step.
        }
        return step.map { LoadStep(display: $0, relativeLimit: true) }
    }

    private static func snapped(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

    /// The first multiple of the step at least half a step above the logged load, in display units.
    private static func nextOnGrid(_ display: Double, step: Double) -> Double {
        snapped(((display + step / 2) / step - epsilon).rounded(.up) * step)
    }

    /// The next loadable weight for the free logbook's comparison, or nil without a supported step.
    public static func nextLoadKg(exercise: Exercise, weightKg: Double, unit: WeightUnit, steps: ProgressionLoadSteps = ProgressionLoadSteps()) -> Double? {
        guard weightKg.isFinite, weightKg > 0, let step = loadStep(exercise, loadsKg: [weightKg], unit: unit, steps: steps) else { return nil }
        return unit.toCanonicalKg(nextOnGrid(unit.toDisplay(weightKg), step: step.display))
    }

    private struct IncreasePlan { let targets: [ProgressionSetTarget]; let resetReps: Bool; let deltaDisplay: Double? }

    /// Per-set next loads; nil when any set has no loadable step within the limits.
    private static func increasePlan(_ sets: [SessionSetLog], step: LoadStep?, unit: WeightUnit, repMin: Int, repMax: Int) -> IncreasePlan? {
        guard let step else { return nil }
        var targets: [ProgressionSetTarget] = []
        var deltas: [Double] = []
        var reset = false
        for set in sets {
            let display = unit.toDisplay(set.weightKg!)
            guard display > 0 else { return nil }
            let next = nextOnGrid(display, step: step.display)
            guard next <= WorkoutSessionUtils.maxAllowedWeight(unit: unit) else { return nil }
            let share = (next - display) / display
            let reps: Int
            if !step.relativeLimit || share <= keepRepsStepShare + epsilon { reps = repMax }
            else if share <= resetRepsStepShare + epsilon && repMin < repMax { reps = repMin; reset = true }
            else { return nil }
            targets.append(ProgressionSetTarget(weightKg: unit.toCanonicalKg(next), reps: reps))
            deltas.append(next - display)
        }
        let delta = deltas.first.flatMap { first in deltas.allSatisfy({ abs($0 - first) < 1e-6 }) ? first : nil }
        return IncreasePlan(targets: targets, resetReps: reset, deltaDisplay: delta)
    }

    /// About 90% of each load on the same step grid, for the same reps; empty when that is not loadable.
    private static func lighterWeek(_ sets: [SessionSetLog], step: LoadStep?, unit: WeightUnit, repMax: Int) -> [ProgressionSetTarget] {
        guard let step else { return [] }
        var targets: [ProgressionSetTarget] = []
        for set in sets {
            let lighter = snapped((unit.toDisplay(set.weightKg!) * lighterWeekShare / step.display + epsilon).rounded(.down) * step.display)
            guard lighter > 0 else { return [] }
            targets.append(ProgressionSetTarget(weightKg: unit.toCanonicalKg(lighter), reps: min(set.reps!, repMax)))
        }
        return targets
    }

    /// `activeSessionId` excludes a resumed session's own saved record: it is today's work, not the baseline.
    /// The session screen passes `context`; it scopes history to the workout day and applies the recency
    /// rules. Without it (analysis and legacy tests) every matching log is one track with no age limit.
    public static func computeProgression(
        exercise: Exercise,
        history: [WorkoutSessionRecord],
        weightUnit: WeightUnit = .kg,
        activeSessionId: String? = nil,
        context: ProgressionContext? = nil,
        steps: ProgressionLoadSteps = ProgressionLoadSteps()
    ) -> ExerciseProgressionRecommendation? {
        guard let (repMin, repMax) = parseRepRange(exercise: exercise) else { return nil }
        // Equipment uses the same identity as history matching, so name-only catalog exercises keep their step.
        let exerciseId = canonicalId(exercise)
        let expectedSets = WorkoutSessionUtils.initialSetCount(exercise: exercise)
        let sessions = findHistoricalSessions(exercise: exercise, history: history.filter { record in
            record.id != activeSessionId && (context.map { sharesTrack(record, exercise: exercise, repRange: (repMin, repMax), expectedSets: expectedSets, context: $0) } ?? true)
        })

        func guidance(_ action: ProgressionAction, _ key: String, _ args: [String: String] = [:]) -> ExerciseProgressionRecommendation {
            ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: action,
                suggestedWeightKg: nil, suggestedWeightDisplay: "--", suggestedRepsMin: repMin, suggestedRepsMax: repMax,
                rationaleKey: key, rationaleArgs: args)
        }
        guard let last = sessions.first else {
            return guidance(.firstSession, "progression.rationale.first_session", ["reps": repMin == repMax ? "\(repMin)" : "\(repMin)–\(repMax)"])
        }
        func valid(_ set: SessionSetLog) -> Bool {
            guard let reps = set.reps, let weight = set.weightKg else { return false }
            return (1...999).contains(reps) && weight.isFinite && weight >= 0 && weightUnit.toDisplay(weight) <= WorkoutSessionUtils.maxAllowedWeight(unit: weightUnit) &&
                (WorkoutSessionUtils.allowsZeroWeight(exercise) || weight > 0)
        }
        func baseline(_ session: HistoricalSessionSets) -> Baseline {
            if session.ambiguous { return .ambiguous }
            let working = session.workingSets
            guard Set(working.map { $0.setNumber }).count == working.count else { return .invalid }
            if working.count >= expectedSets {
                // Extra sets beyond the plan are ignored rather than invalidating the log.
                let used = Array(working.prefix(expectedSets))
                return used.allSatisfy(valid) ? .full(sets: used, padded: false, logged: working.count) : .invalid
            }
            // A full session of a smaller earlier plan: its saved prescription had exactly these sets, all completed.
            let earlierPlan = !working.isEmpty && session.prescribedSets == working.count &&
                (session.targetSets == nil || session.targetSets == working.count)
            guard earlierPlan else { return .partial(logged: working.count) }
            guard working.allSatisfy(valid), let lastSet = working.last else { return .invalid }
            let padding = (working.count + 1...expectedSets).map { number in
                SessionSetLog(setNumber: lastSet.setNumber + number - working.count, weightKg: lastSet.weightKg, reps: lastSet.reps, isWarmup: false)
            }
            return .full(sets: working + padding, padded: true, logged: working.count)
        }
        func fullUnpadded(_ session: HistoricalSessionSets) -> [SessionSetLog]? {
            if case let .full(sets, padded, _) = baseline(session), !padded { return sets }
            return nil
        }
        func fullSets(_ session: HistoricalSessionSets) -> [SessionSetLog]? {
            if case let .full(sets, _, _) = baseline(session) { return sets }
            return nil
        }

        // Do not silently fall back to an older, easier or more complete workout.
        let workingSets: [SessionSetLog]
        let padded: Bool
        let logged: Int
        switch baseline(last) {
        case let .full(sets, isPadded, count): (workingSets, padded, logged) = (sets, isPadded, count)
        case let .partial(count):
            return guidance(.insufficientData, "progression.rationale.partial_log", ["logged": "\(count)", "sets": "\(expectedSets)"])
        case .ambiguous:
            return guidance(.insufficientData, "progression.rationale.ambiguous_log", ["sets": "\(expectedSets)"])
        case .invalid:
            return guidance(.insufficientData, "progression.rationale.insufficient_data", ["sets": "\(expectedSets)"])
        }
        let planArgs = ["logged": "\(logged)", "sets": "\(expectedSets)"]
        let lastSessionSets = workingSets.map { ProgressionSetTarget(weightKg: $0.weightKg, reps: $0.reps!) }
        let topWeight = workingSets.map { $0.weightKg! }.max()!
        let mixedLoads = workingSets.contains { abs($0.weightKg! - topWeight) > 0.01 }
        func comparable(_ session: HistoricalSessionSets) -> Bool {
            guard let sets = fullUnpadded(session) else { return false }
            return zip(sets, workingSets).allSatisfy { abs($0.weightKg! - $1.weightKg!) <= 0.01 }
        }
        let allHitCeiling = workingSets.allSatisfy { $0.reps! >= repMax }
        let summary = formatSessionSummary(workingSets, unit: weightUnit)

        // Repeat the logged loads with reps capped at the ceiling: no added rep or weight.
        func repeatLogged(_ rationaleKey: String) -> ExerciseProgressionRecommendation {
            let targets = workingSets.map { ProgressionSetTarget(weightKg: $0.weightKg, reps: min($0.reps!, repMax)) }
            let uniformWeight = Set(targets.map { $0.weightKg }).count == 1 ? targets.first?.weightKg : nil
            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .holdLoad,
                suggestedWeightKg: uniformWeight,
                suggestedWeightDisplay: formatWeight(uniformWeight ?? topWeight, unit: weightUnit),
                suggestedRepsMin: targets.map { $0.reps }.min() ?? repMin,
                suggestedRepsMax: targets.map { $0.reps }.max() ?? repMax,
                weightDeltaDisplay: nil,
                rationaleKey: rationaleKey,
                rationaleArgs: [:],
                isPlateau: false,
                consecutiveStagnantSessions: 0,
                lastSessionSummary: summary,
                setTargets: targets,
                lastSessionSets: lastSessionSets
            )
        }
        // After a long break the latest log no longer shows current capacity; an unreadable date is treated as old.
        if let context {
            if last.date.map({ context.now.timeIntervalSince($0) > staleBaselineDays * daySeconds }) ?? true {
                return repeatLogged("progression.rationale.stale_baseline")
            }
        }

        let step = loadStep(exercise, loadsKg: workingSets.map { $0.weightKg! }, unit: weightUnit, steps: steps)
        let recent = Array(sessions.prefix(3))
        let isPlateau = !padded && recent.count == 3 && recent.allSatisfy(comparable) && !allHitCeiling &&
            zip(recent, recent.dropFirst()).allSatisfy { newer, older in
                fullUnpadded(newer)!.reduce(0) { $0 + $1.reps! } <= fullUnpadded(older)!.reduce(0) { $0 + $1.reps! }
            }
        if isPlateau {
            let variation = variationSwaps[exerciseId]
            let lighter = WorkoutSessionUtils.isAssisted(exercise) ? [] : lighterWeek(workingSets, step: step, unit: weightUnit, repMax: repMax)
            return ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: .deload,
                suggestedWeightKg: nil, suggestedWeightDisplay: "--", suggestedRepsMin: repMin, suggestedRepsMax: repMax,
                rationaleKey: "progression.rationale.plateau", rationaleArgs: ["sessions": "3"], isPlateau: true, consecutiveStagnantSessions: 3,
                suggestedVariationId: variation?.id, suggestedVariationName: variation?.name,
                lastSessionSummary: summary, setTargets: lighter, lastSessionSets: lastSessionSets)
        }

        let previousCompleted = sessions.dropFirst().lazy.compactMap(fullSets).first
        let previousTopWeight = previousCompleted?.compactMap { $0.weightKg }.filter { $0 > 0.0 }.max()
        let repeatedLoads = sessions.dropFirst().first.map(comparable) ?? false
        let hasUnverifiedJump = (previousTopWeight != nil && topWeight > previousTopWeight! * 1.35 && (topWeight - previousTopWeight!) >= 20.0) ||
            (topWeight > 500.0 && !repeatedLoads)
        if hasUnverifiedJump { return repeatLogged("progression.rationale.unverified_jump") }

        // A second full session at the same set-by-set loads, close enough in time, confirms the ceiling.
        func withinConfirmationWindow(_ previous: HistoricalSessionSets) -> Bool {
            guard context != nil else { return true }
            guard let latest = last.date, let earlier = previous.date else { return false }
            return abs(latest.timeIntervalSince(earlier)) <= confirmationWindowDays * daySeconds
        }
        let confirmedTwice = allHitCeiling && !padded && sessions.dropFirst().first.map { previous in
            comparable(previous) && fullUnpadded(previous)!.allSatisfy { $0.reps! >= repMax } && withinConfirmationWindow(previous)
        } == true
        // The user's own rating: Easy confirms after one session, Hard withholds the step.
        let ratedEasy = allHitCeiling && !padded && last.effort == .easy
        let ratedHard = last.effort == .hard
        let confirmed = (confirmedTwice || ratedEasy) && !ratedHard
        let possibleIncrease = increasePlan(workingSets, step: step, unit: weightUnit, repMin: repMin, repMax: repMax)
        let increase = confirmed ? possibleIncrease : nil
        let canIncrease = increase != nil
        let missedFloor = workingSets.contains { $0.reps! < repMin }
        let bodyweightOnly = step == nil && workingSets.allSatisfy { $0.weightKg == 0 }
        let action: ProgressionAction = canIncrease ? .increaseLoad : (allHitCeiling || missedFloor ? .holdLoad : .addReps)
        let targets = increase?.targets ?? workingSets.map { set in
            ProgressionSetTarget(weightKg: set.weightKg, reps: allHitCeiling ? repMax : min(set.reps! + 1, repMax))
        }
        let variation = allHitCeiling && (confirmedTwice || ratedEasy) && !ratedHard && bodyweightOnly ? bodyweightLadder[exerciseId] : nil
        let key: String
        if WorkoutSessionUtils.isAssisted(exercise) { key = allHitCeiling ? "progression.rationale.assistance_ceiling" : "progression.rationale.assistance_reps" }
        else if let increase {
            if ratedEasy && !confirmedTwice { key = "progression.rationale.increase_load_easy" }
            else if increase.resetReps { key = "progression.rationale.increase_load_reset" }
            else { key = mixedLoads ? "progression.rationale.increase_load_mixed" : "progression.rationale.increase_load" }
        }
        else if padded { key = "progression.rationale.plan_sets_changed" }
        else if allHitCeiling {
            if ratedHard { key = "progression.rationale.repeat_ceiling_hard" }
            else if confirmedTwice || ratedEasy { key = bodyweightOnly ? "progression.rationale.bodyweight_ceiling" : "progression.rationale.load_step_unavailable" }
            else { key = possibleIncrease != nil ? "progression.rationale.repeat_ceiling" : "progression.rationale.repeat_ceiling_no_step" }
        }
        else if missedFloor { key = mixedLoads ? "progression.rationale.hold_load_mixed" : "progression.rationale.hold_load" }
        else { key = mixedLoads ? "progression.rationale.add_reps_mixed" : "progression.rationale.add_reps" }
        let weights = Set(targets.compactMap { $0.weightKg })
        let uniformWeight = weights.count == 1 ? weights.first : nil
        let args = ["ceiling": "\(repMax)", "floor": "\(repMin)", "targetReps": "\(targets[0].reps)"].merging(planArgs) { $1 }
        return ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: action,
            suggestedWeightKg: uniformWeight, suggestedWeightDisplay: formatWeight(uniformWeight ?? topWeight, unit: weightUnit),
            suggestedRepsMin: targets.map { $0.reps }.min()!, suggestedRepsMax: targets.map { $0.reps }.max()!,
            weightDeltaDisplay: increase?.deltaDisplay.map { "+\(weightUnit.formatExactWeight(weightUnit.toCanonicalKg($0))) \(weightUnit.label)" },
            rationaleKey: key, rationaleArgs: args,
            suggestedVariationId: variation?.id, suggestedVariationName: variation?.name,
            lastSessionSummary: summary, setTargets: targets, lastSessionSets: lastSessionSets)
    }

    // Exact input precision: the card must show the load Apply Target writes.
    private static func formatWeight(_ kg: Double, unit: WeightUnit) -> String {
        kg <= 0.0 ? "BW" : unit.formatExactWeight(kg)
    }

    private static func formatSessionSummary(_ sets: [SessionSetLog], unit: WeightUnit) -> String {
        sets.map { set in
            let w = (set.weightKg != nil && set.weightKg! > 0.0) ? formatWeight(set.weightKg!, unit: unit) : "BW"
            let r = set.reps ?? 0
            return "\(w)×\(r)"
        }.joined(separator: ", ")
    }
}
