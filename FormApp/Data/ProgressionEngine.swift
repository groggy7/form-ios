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
        /// `padded` repeats the last set's main part for the sets the session lacks: sets added to the plan since, or,
        /// when `endedWith` is set, sets the lifter removed after finishing on that drop or rest-pause.
        case full(sets: [SessionSetLog], padded: Bool, logged: Int, endedWith: SetTechnique? = nil)
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

    /// Loads on the step's grid are `origin` plus whole steps; a bar's grid starts at the bar.
    private struct LoadStep { let display: Double; let relativeLimit: Bool; var origin: Double = 0 }

    /// The smallest supported increase in `unit`, or nil when the app must not invent one.
    private static func loadStep(_ exercise: Exercise, loadsKg: [Double], unit: WeightUnit, steps: ProgressionLoadSteps) -> LoadStep? {
        if WorkoutSessionUtils.isAssisted(exercise) { return nil }
        // Body mass is unknown, so weighted bodyweight variants step their added load without a relative limit.
        if WorkoutSessionUtils.usesBodyweightResistance(exercise) {
            return !loadsKg.isEmpty && loadsKg.allSatisfy({ $0 > 0 }) ? LoadStep(display: steps.bodyweight(unit), relativeLimit: false) : nil
        }
        switch EquipmentCatalog.shared.categoryId(canonicalId(exercise)) {
        case "bar": return steps.bar(unit).map { LoadStep(display: $0, relativeLimit: true, origin: steps.barOrigin(unit)) }
        case "dumbbell": return LoadStep(display: steps.dumbbell(unit), relativeLimit: true)
        case "machine": return LoadStep(display: steps.machine(unit), relativeLimit: true)
        default: return nil // Bodyweight, kettlebells, plates, bands and unknown equipment have no inferred step.
        }
    }

    private static func snapped(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }

    /// The first load on the step's grid at least half a step above the logged load, in display units.
    private static func nextOnGrid(_ display: Double, step: LoadStep) -> Double {
        snapped(step.origin + ((display - step.origin + step.display / 2) / step.display - epsilon).rounded(.up) * step.display)
    }

    /// The next loadable weight for the free logbook's comparison, or nil without a supported step.
    public static func nextLoadKg(exercise: Exercise, weightKg: Double, unit: WeightUnit, steps: ProgressionLoadSteps = ProgressionLoadSteps()) -> Double? {
        guard weightKg.isFinite, weightKg > 0, let step = loadStep(exercise, loadsKg: [weightKg], unit: unit, steps: steps) else { return nil }
        return unit.toCanonicalKg(nextOnGrid(unit.toDisplay(weightKg), step: step))
    }

    /// The mid-workout adjustment (docs/adaptive-training.md#b2-mid-workout-adjustment): after the first working set
    /// is ticked with reps in reserve, and before any other working set is, a set at or above the rep ceiling with more
    /// reps left than `window` allows offers the next load step (with the coach's 10% / 25% rules), and a set below the
    /// minimum with none left offers one step down. Straight sets only: every remaining working row must be untouched,
    /// without a load, or at the first set's load. Android `ProgressionEngine.loadAdjustment` matches.
    public static func loadAdjustment(exercise: Exercise, sets: [ExerciseSetLog], unit: WeightUnit,
                                      steps: ProgressionLoadSteps = ProgressionLoadSteps(),
                                      window: ClosedRange<Int> = SetEffort.targetWindow) -> LoadAdjustment? {
        guard let range = parseRepRange(exercise: exercise) else { return nil }
        let working = sets.enumerated().filter { !$0.element.isWarmup }
        guard let firstRow = working.first else { return nil }
        let first = firstRow.element
        let rest = working.dropFirst()
        guard first.isCompleted, !rest.isEmpty, !rest.contains(where: { $0.element.isCompleted }),
              let rir = first.rir, SetEffort.rirRange.contains(rir),
              let reps = first.completedReps, (1...999).contains(reps),
              let loggedKg = first.weightKg, loggedKg.isFinite, loggedKg > 0 else { return nil }
        let easier = reps >= range.max && rir > window.upperBound
        let harder = reps < range.min && rir == 0
        guard easier || harder else { return nil }

        let barbell = WorkoutSessionUtils.usesBarbellPlates(exercise)
        let currentKg = unit.loadableKg(loggedKg, barbell: barbell)
        func isOpen(_ row: ExerciseSetLog) -> Bool {
            if row.inputTouched != true || (row.weightInput.trimmingCharacters(in: .whitespaces).isEmpty && row.weightKg == nil) { return true }
            guard let kg = row.weightKg else { return false }
            return abs(unit.loadableKg(kg, barbell: barbell) - currentKg) < 1e-6
        }
        guard rest.allSatisfy({ isOpen($0.element) }),
              let step = loadStep(exercise, loadsKg: [loggedKg], unit: unit, steps: steps) else { return nil }

        let target: ProgressionSetTarget
        if easier {
            guard let next = increasePlan([SessionSetLog(setNumber: first.setNumber, weightKg: loggedKg, reps: reps)], step: step,
                                          unit: unit, barbell: barbell, repMin: range.min, repMax: range.max)?.targets.first else { return nil }
            target = next
        } else {
            // One step down on the same grid; a lighter load is always the lifter's safe choice, so no relative limit.
            let display = unit.toDisplay(currentKg)
            let lower = snapped(step.origin + ((display - step.origin - step.display / 2) / step.display + epsilon).rounded(.down) * step.display)
            guard lower > 0, lower >= step.origin - epsilon else { return nil }
            target = ProgressionSetTarget(weightKg: unit.toCanonicalKg(lower), reps: range.min)
        }
        return LoadAdjustment(direction: easier ? .easier : .harder, setIndex: firstRow.offset, setNumber: first.setNumber,
                              rir: rir, currentKg: currentKg, target: target, rows: rest.map(\.offset))
    }

    private struct IncreasePlan { let targets: [ProgressionSetTarget]; let resetReps: Bool; let deltaDisplay: Double? }

    /// Per-set next loads; nil when any set has no loadable step within the limits.
    private static func increasePlan(_ sets: [SessionSetLog], step: LoadStep?, unit: WeightUnit, barbell: Bool, repMin: Int, repMax: Int) -> IncreasePlan? {
        guard let step else { return nil }
        var targets: [ProgressionSetTarget] = []
        var deltas: [Double] = []
        var reset = false
        for set in sets {
            // Step from the load a converted set would show (225 lbs, not 220.46), so the delta reads +5.
            let display = unit.toDisplay(unit.loadableKg(set.weightKg!, barbell: barbell))
            guard display > 0 else { return nil }
            let next = nextOnGrid(display, step: step)
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
    /// A bar's grid never goes below the bar, so a set too close to the empty bar withholds the lighter week.
    private static func lighterWeek(_ sets: [SessionSetLog], step: LoadStep?, unit: WeightUnit, barbell: Bool, repMax: Int) -> [ProgressionSetTarget] {
        guard let step else { return [] }
        var targets: [ProgressionSetTarget] = []
        for set in sets {
            let target = unit.toDisplay(unit.loadableKg(set.weightKg!, barbell: barbell)) * lighterWeekShare - step.origin
            let lighter = snapped(step.origin + (target / step.display + epsilon).rounded(.down) * step.display)
            guard lighter > 0, lighter >= step.origin else { return [] }
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
            // Or a drop or rest-pause finished the exercise and the later rows were removed (End here).
            let endedWith = working.last.flatMap { last in
                !earlierPlan && session.targetSets == working.count && IntensitySets.usesTechnique(last) ? last.setTechnique : nil
            }
            guard earlierPlan || endedWith != nil else { return .partial(logged: working.count) }
            guard working.allSatisfy(valid), let lastSet = working.last else { return .invalid }
            let padding = (working.count + 1...expectedSets).map { number in
                SessionSetLog(setNumber: lastSet.setNumber + number - working.count, weightKg: lastSet.weightKg, reps: lastSet.reps, isWarmup: false)
            }
            return .full(sets: working + padding, padded: true, logged: working.count, endedWith: endedWith)
        }
        func fullUnpadded(_ session: HistoricalSessionSets) -> [SessionSetLog]? {
            if case let .full(sets, padded, _, _) = baseline(session), !padded { return sets }
            return nil
        }
        func fullSets(_ session: HistoricalSessionSets) -> [SessionSetLog]? {
            if case let .full(sets, _, _, _) = baseline(session) { return sets }
            return nil
        }

        // Do not silently fall back to an older, easier or more complete workout.
        let workingSets: [SessionSetLog]
        let padded: Bool
        let logged: Int
        let endedWith: SetTechnique?
        switch baseline(last) {
        case let .full(sets, isPadded, count, technique): (workingSets, padded, logged, endedWith) = (sets, isPadded, count, technique)
        case let .partial(count):
            return guidance(.insufficientData, "progression.rationale.partial_log", ["logged": "\(count)", "sets": "\(expectedSets)"])
        case .ambiguous:
            return guidance(.insufficientData, "progression.rationale.ambiguous_log", ["sets": "\(expectedSets)"])
        case .invalid:
            return guidance(.insufficientData, "progression.rationale.insufficient_data", ["sets": "\(expectedSets)"])
        }
        let planArgs = ["logged": "\(logged)", "sets": "\(expectedSets)"]
        // Converted history reads, and is targeted, at its loadable weight in the current unit.
        let barbell = WorkoutSessionUtils.usesBarbellPlates(exercise)
        let loadable: (Double) -> Double = { weightUnit.loadableKg($0, barbell: barbell) }
        let lastSessionSets = workingSets.map { ProgressionSetTarget(weightKg: $0.weightKg.map(loadable), reps: $0.reps!) }
        // A plan change hides last time's techniques; a session that ended on one shows its logged sets.
        let lastTechniqueSets = padded && endedWith == nil ? [] : workingSets.filter(IntensitySets.hasDetail)
        let topWeight = workingSets.map { $0.weightKg! }.max()!
        let mixedLoads = workingSets.contains { abs($0.weightKg! - topWeight) > 0.01 }
        func comparable(_ session: HistoricalSessionSets) -> Bool {
            guard let sets = fullUnpadded(session) else { return false }
            return zip(sets, workingSets).allSatisfy { abs($0.weightKg! - $1.weightKg!) <= 0.01 }
        }
        let allHitCeiling = workingSets.allSatisfy { $0.reps! >= repMax }
        let summary = formatSessionSummary(workingSets, unit: weightUnit, barbell: barbell)

        // Repeat the logged loads with reps capped at the ceiling: no added rep or weight.
        func repeatLogged(_ rationaleKey: String) -> ExerciseProgressionRecommendation {
            let targets = workingSets.map { ProgressionSetTarget(weightKg: $0.weightKg.map(loadable), reps: min($0.reps!, repMax)) }
            let uniformWeight = Set(targets.map { $0.weightKg }).count == 1 ? targets.first?.weightKg : nil
            return ExerciseProgressionRecommendation(
                exerciseId: exerciseId,
                exerciseName: exercise.name,
                action: .holdLoad,
                suggestedWeightKg: uniformWeight,
                suggestedWeightDisplay: formatWeight(uniformWeight ?? topWeight, unit: weightUnit, barbell: barbell),
                suggestedRepsMin: targets.map { $0.reps }.min() ?? repMin,
                suggestedRepsMax: targets.map { $0.reps }.max() ?? repMax,
                weightDeltaDisplay: nil,
                rationaleKey: rationaleKey,
                rationaleArgs: [:],
                isPlateau: false,
                consecutiveStagnantSessions: 0,
                lastSessionSummary: summary,
                setTargets: targets,
                lastSessionSets: lastSessionSets,
                lastTechniqueSets: lastTechniqueSets
            )
        }
        // After a long break the latest log no longer shows current capacity; an unreadable date is treated as old.
        if let context {
            if last.date.map({ context.now.timeIntervalSince($0) > staleBaselineDays * daySeconds }) ?? true {
                return repeatLogged("progression.rationale.stale_baseline")
            }
        }

        // On the session screen, two sessions count together only this close in time.
        func withinWindow(_ newer: HistoricalSessionSets, _ older: HistoricalSessionSets) -> Bool {
            guard context != nil else { return true }
            guard let newerDate = newer.date, let olderDate = older.date else { return false }
            return abs(newerDate.timeIntervalSince(olderDate)) <= confirmationWindowDays * daySeconds
        }

        let step = loadStep(exercise, loadsKg: workingSets.map { $0.weightKg! }, unit: weightUnit, steps: steps)
        let recent = Array(sessions.prefix(3))
        // Sessions from before a break never count toward a plateau.
        let isPlateau = !padded && recent.count == 3 && recent.allSatisfy(comparable) && !allHitCeiling &&
            zip(recent, recent.dropFirst()).allSatisfy { newer, older in
                withinWindow(newer, older) && fullUnpadded(newer)!.reduce(0) { $0 + $1.reps! } <= fullUnpadded(older)!.reduce(0) { $0 + $1.reps! }
            }
        if isPlateau {
            let variation = variationSwaps[exerciseId]
            let lighter = WorkoutSessionUtils.isAssisted(exercise) ? [] : lighterWeek(workingSets, step: step, unit: weightUnit, barbell: barbell, repMax: repMax)
            return ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: .deload,
                suggestedWeightKg: nil, suggestedWeightDisplay: "--", suggestedRepsMin: repMin, suggestedRepsMax: repMax,
                rationaleKey: "progression.rationale.plateau", rationaleArgs: ["sessions": "3"], isPlateau: true, consecutiveStagnantSessions: 3,
                suggestedVariationId: variation?.id, suggestedVariationName: variation?.name,
                lastSessionSummary: summary, setTargets: lighter, lastSessionSets: lastSessionSets, lastTechniqueSets: lastTechniqueSets)
        }

        let previousCompleted = sessions.dropFirst().lazy.compactMap(fullSets).first
        let previousTopWeight = previousCompleted?.compactMap { $0.weightKg }.filter { $0 > 0.0 }.max()
        let repeatedLoads = sessions.dropFirst().first.map(comparable) ?? false
        let hasUnverifiedJump = (previousTopWeight != nil && topWeight > previousTopWeight! * 1.35 && (topWeight - previousTopWeight!) >= 20.0) ||
            (topWeight > 500.0 && !repeatedLoads)
        // A likely typo is never offered as a target; the next full session becomes the baseline.
        if hasUnverifiedJump { return guidance(.insufficientData, "progression.rationale.unverified_jump") }

        // A second full session at the same set-by-set loads, close enough in time, confirms the ceiling.
        let confirmedTwice = allHitCeiling && !padded && sessions.dropFirst().first.map { previous in
            comparable(previous) && fullUnpadded(previous)!.allSatisfy { $0.reps! >= repMax } && withinWindow(last, previous)
        } == true
        // The user's own rating: Easy confirms after one session, Hard withholds the step. Without one, every set's
        // reps in reserve stands in for it (SetEffort.sessionEffort); a padded baseline repeats sets nobody rated.
        let rirEffort = padded || last.effort != nil ? nil : SetEffort.sessionEffort(workingSets)
        let effort = last.effort ?? rirEffort
        let ratedEasy = allHitCeiling && !padded && effort == .easy
        let ratedHard = effort == .hard
        // Room to spare on every set below the ceiling: up to two more reps instead of one.
        let repStep = rirEffort == .easy ? 2 : 1
        let confirmed = (confirmedTwice || ratedEasy) && !ratedHard
        let possibleIncrease = increasePlan(workingSets, step: step, unit: weightUnit, barbell: barbell, repMin: repMin, repMax: repMax)
        let increase = confirmed ? possibleIncrease : nil
        let canIncrease = increase != nil
        let missedFloor = workingSets.contains { $0.reps! < repMin }
        let bodyweightOnly = step == nil && workingSets.allSatisfy { $0.weightKg == 0 }
        let action: ProgressionAction = canIncrease ? .increaseLoad : (allHitCeiling || missedFloor ? .holdLoad : .addReps)
        let targets = increase?.targets ?? workingSets.map { set in
            ProgressionSetTarget(weightKg: set.weightKg.map(loadable), reps: allHitCeiling ? repMax : min(set.reps! + repStep, repMax))
        }
        let variation = allHitCeiling && (confirmedTwice || ratedEasy) && !ratedHard && bodyweightOnly ? bodyweightLadder[exerciseId] : nil
        let key: String
        if WorkoutSessionUtils.isAssisted(exercise) { key = allHitCeiling ? "progression.rationale.assistance_ceiling" : "progression.rationale.assistance_reps" }
        else if let increase {
            // Only some sets aim for the range minimum: name both groups, whichever confirmation applied.
            if increase.resetReps && Set(increase.targets.map { $0.reps }).count > 1 { key = "progression.rationale.increase_load_reset_mixed" }
            else if ratedEasy && !confirmedTwice {
                key = rirEffort != nil ? "progression.rationale.increase_load_rir" : "progression.rationale.increase_load_easy"
            }
            else if increase.resetReps { key = "progression.rationale.increase_load_reset" }
            else { key = mixedLoads ? "progression.rationale.increase_load_mixed" : "progression.rationale.increase_load" }
        }
        else if padded {
            switch endedWith {
            case .drop: key = "progression.rationale.ended_with_drop"
            case .restPause: key = "progression.rationale.ended_with_rest_pause"
            case nil: key = "progression.rationale.plan_sets_changed"
            }
        }
        else if allHitCeiling {
            if ratedHard { key = rirEffort != nil ? "progression.rationale.repeat_ceiling_rir_hard" : "progression.rationale.repeat_ceiling_hard" }
            else if confirmedTwice || ratedEasy { key = bodyweightOnly ? "progression.rationale.bodyweight_ceiling" : "progression.rationale.load_step_unavailable" }
            else { key = possibleIncrease != nil ? "progression.rationale.repeat_ceiling" : "progression.rationale.repeat_ceiling_no_step" }
        }
        else if missedFloor { key = mixedLoads ? "progression.rationale.hold_load_mixed" : "progression.rationale.hold_load" }
        else if repStep == 2 { key = "progression.rationale.add_reps_rir" }
        else { key = mixedLoads ? "progression.rationale.add_reps_mixed" : "progression.rationale.add_reps" }
        let weights = Set(targets.compactMap { $0.weightKg })
        let uniformWeight = weights.count == 1 ? weights.first : nil
        let args = ["ceiling": "\(repMax)", "floor": "\(repMin)", "targetReps": "\(targets[0].reps)"].merging(planArgs) { $1 }
        return ExerciseProgressionRecommendation(exerciseId: exerciseId, exerciseName: exercise.name, action: action,
            suggestedWeightKg: uniformWeight, suggestedWeightDisplay: formatWeight(uniformWeight ?? topWeight, unit: weightUnit, barbell: barbell),
            suggestedRepsMin: targets.map { $0.reps }.min()!, suggestedRepsMax: targets.map { $0.reps }.max()!,
            weightDeltaDisplay: increase?.deltaDisplay.map { "+\(weightUnit.formatExactWeight(weightUnit.toCanonicalKg($0))) \(weightUnit.label)" },
            rationaleKey: key, rationaleArgs: args,
            suggestedVariationId: variation?.id, suggestedVariationName: variation?.name,
            lastSessionSummary: summary, setTargets: targets, lastSessionSets: lastSessionSets, lastTechniqueSets: lastTechniqueSets)
    }

    // Input precision: the card must show the load Apply Target writes, and a converted load at its loadable weight.
    private static func formatWeight(_ kg: Double, unit: WeightUnit, barbell: Bool) -> String {
        kg <= 0.0 ? "BW" : unit.formatLoadableWeight(kg, barbell: barbell)
    }

    private static func formatSessionSummary(_ sets: [SessionSetLog], unit: WeightUnit, barbell: Bool) -> String {
        sets.map { set in
            let w = (set.weightKg != nil && set.weightKg! > 0.0) ? formatWeight(set.weightKg!, unit: unit, barbell: barbell) : "BW"
            let r = set.reps ?? 0
            return "\(w)×\(r)"
        }.joined(separator: ", ")
    }
}

extension SetEffort {
    /// Reps in reserve at which a set counts as having room to spare: the coach's Easy.
    public static let roomyRir = 3

    /// The planned reps in reserve for a working set outside a training block. The mid-workout adjustment offers a
    /// load step up only above it (docs/adaptive-training.md#b2-mid-workout-adjustment).
    public static let targetWindow = 1...3

    /// The coach's effort from a session's reps in reserve, used when the lifter gave no Easy / About right / Hard
    /// rating (docs/adaptive-training.md#b1-targets-that-use-reported-effort). Every working set needs a value: all at
    /// 3 or 4+ reads Easy, a first set at 0 reads Hard, anything else About right. Nil when any set is unrated.
    public static func sessionEffort(_ workingSets: [SessionSetLog]) -> ProgressionEffort? {
        guard !workingSets.isEmpty, workingSets.allSatisfy({ $0.rir.map(rirRange.contains) == true }) else { return nil }
        if workingSets.allSatisfy({ $0.rir! >= roomyRir }) { return .easy }
        if workingSets[0].rir == 0 { return .hard }
        return .right
    }
}
