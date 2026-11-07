import Foundation

/// Training blocks against the app's programs, history and muscle catalog (docs/training-blocks.md).
/// The rules themselves live in `TrainingBlockRules`; Android `TrainingBlocks` matches.
enum TrainingBlocks {
    /// Reason codes a week may show.
    static let reasons = ["still_sore", "too_much", "performance", "recovered", "low_pump", "focus",
                          "top_of_range", "bottom_of_range", "no_exercise"]
    static let maxExerciseSets = 10

    static func key(_ workout: Workout, _ exercise: Exercise) -> String { "\(workout.id)/\(exercise.id)" }

    static func isWeekKey(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-W\d{2}$"#, options: .regularExpression) != nil,
              let week = Int(value.suffix(2)) else { return false }
        return (1...53).contains(week)
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    /// The ISO week key's Monday, or nil when it is not a week key.
    static func monday(_ weekKey: String) -> Date? {
        guard isWeekKey(weekKey), let year = Int(weekKey.prefix(4)), let week = Int(weekKey.suffix(2)) else { return nil }
        return isoCalendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year))
    }

    static func weekKey(_ date: Date) -> String { PersonalRecordTracker.isoWeekKey(date) }

    /// Week 1 is the block's first week; nil before it starts. Values above the length mean it has ended.
    static func weekIndex(_ block: TrainingBlock, weekKey: String) -> Int? {
        guard let start = monday(block.startWeek), let now = monday(weekKey),
              let days = isoCalendar.dateComponents([.day], from: start, to: now).day else { return nil }
        let weeks = Int((Double(days) / 7).rounded())
        return weeks < 0 ? nil : weeks + 1
    }

    /// The block week a workout of `programId` started now belongs to, or nil outside the block.
    static func activeWeek(_ block: TrainingBlock?, programId: String, weekKey: String) -> Int? {
        guard let block, block.programId == programId, let week = weekIndex(block, weekKey: weekKey),
              (1...block.length).contains(week), week <= block.weeks.count else { return nil }
        return week
    }

    static func isFinished(_ block: TrainingBlock, weekKey: String) -> Bool { (weekIndex(block, weekKey: weekKey) ?? 0) > block.length }

    /// Primary and secondary muscles from the reviewed catalog; empty when the exercise is unmapped.
    static func muscles(_ exercise: Exercise, catalog: ExerciseMuscleCatalog? = .shared) -> (primary: [String], secondary: [String]) {
        guard let id = ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name),
              let profile = catalog?.profile(id) else { return ([], []) }
        var primary: [String] = []
        for muscle in profile.primary where !primary.contains(muscle) { primary.append(muscle) }
        var secondary: [String] = []
        for muscle in profile.secondary where !primary.contains(muscle) && !secondary.contains(muscle) { secondary.append(muscle) }
        return (primary, secondary)
    }

    private static func programSets(_ exercise: Exercise) -> Int { WorkoutSessionUtils.initialSetCount(exercise: exercise) }

    private static func ruleExercises(_ program: Program, catalog: ExerciseMuscleCatalog?, sets: [String: Int]? = nil,
                                      base: [String: Int]? = nil,
                                      flags: (String) -> (jointHigh: Int, highThisWeek: Bool, fell: Bool) = { _ in (0, false, false) })
        -> [TrainingBlockRules.Exercise] {
        program.workouts.flatMap { workout in
            workout.exercises.map { exercise in
                let key = key(workout, exercise)
                let muscles = muscles(exercise, catalog: catalog)
                let flag = flags(key)
                return TrainingBlockRules.Exercise(key: key, sets: sets?[key] ?? programSets(exercise), primary: muscles.primary,
                                                   secondary: muscles.secondary, baseSets: base?[key] ?? programSets(exercise),
                                                   jointHigh: flag.jointHigh, highThisWeek: flag.highThisWeek, performanceFell: flag.fell)
            }
        }
    }

    /// Muscles that adjust in this program: the ones the setup offers as focus.
    static func focusChoices(_ program: Program, catalog: ExerciseMuscleCatalog? = .shared) -> [String] {
        TrainingBlockRules.participants(ruleExercises(program, catalog: catalog))
    }

    /// Lifts a strength block can test: Rep Lab's reference barbell squats, bench presses, deadlifts and overhead
    /// presses, without the rows. Other barbell work is trained for reps, not tested for a single.
    static let testLifts = BodyTrends.referenceLifts.subtracting(["barbell-row", "barbell-pendlay-row"])

    /// The program's test lifts a strength block can choose, as (key, exercise).
    static func liftChoices(_ program: Program) -> [(key: String, exercise: Exercise)] {
        program.workouts.flatMap { workout in
            workout.exercises.filter { exercise in
                ExerciseCatalog.resolveCanonicalId(stableId: exercise.exerciseId, name: exercise.name).map(testLifts.contains) == true
            }.map { (key(workout, $0), $0) }
        }
    }

    /// Whether the setup suggests next week: none of the program's workouts is still ahead this week (scheduled
    /// `today` or later, an ISO weekday, and not in `completed`, this week's `programId:workoutId` keys).
    static func suggestsNextWeek(_ program: Program, completed: [String], today: Int) -> Bool {
        let done = Set(completed)
        return !program.workouts.contains { !$0.exercises.isEmpty && $0.day >= today && !done.contains("\(program.id):\($0.id)") }
    }

    /// A strength block: every week known at the start (docs/training-blocks.md#strength-blocks).
    static func startStrength(_ program: Program, length: Int, lifts: [String], startWeek: String,
                              id: String = UUID().uuidString) -> TrainingBlock? {
        let choices = Set(liftChoices(program).map(\.key))
        var chosen: [String] = []
        for lift in lifts where choices.contains(lift) && !chosen.contains(lift) && chosen.count < TrainingBlockRules.maxLifts { chosen.append(lift) }
        guard TrainingBlockRules.strengthLengths.contains(length), isWeekKey(startWeek), !chosen.isEmpty else { return nil }
        let exercises = program.workouts.flatMap { workout in workout.exercises.map { (key: key(workout, $0), sets: programSets($0)) } }
        return TrainingBlock(id: id, programId: program.id, startWeek: startWeek, length: length,
                             weeks: (1...length).map { week in
                                 TrainingBlockWeek(sets: TrainingBlockRules.strengthSets(exercises, lifts: Set(chosen), length: length, week: week),
                                                   reviewed: true)
                             }, kind: TrainingBlockRules.strength, lifts: chosen)
    }

    static func start(_ program: Program, length: Int, focus: [String], startWeek: String,
                      catalog: ExerciseMuscleCatalog? = .shared, id: String = UUID().uuidString) -> TrainingBlock? {
        guard TrainingBlockRules.lengths.contains(length), isWeekKey(startWeek) else { return nil }
        var chosen: [String] = []
        for muscle in focus where !chosen.contains(muscle) && chosen.count < TrainingBlockRules.maxFocus { chosen.append(muscle) }
        let week = TrainingBlockRules.firstWeek(ruleExercises(program, catalog: catalog), focus: chosen)
        return TrainingBlock(id: id, programId: program.id, startWeek: startWeek, length: length, focus: chosen,
                             weeks: [TrainingBlockWeek(sets: week.sets, changes: week.changes, reviewed: true)], additions: week.additions)
    }

    /// Each block week's logs of each program exercise, oldest first.
    private static func blockLogs(_ block: TrainingBlock, program: Program, history: [WorkoutSessionRecord])
        -> [Int: [String: [SessionExerciseLog]]] {
        let workouts = Dictionary(program.workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let records = history.filter { $0.blockId == block.id && $0.programId == program.id && $0.blockWeek != nil }
            .sorted { (PersonalRecordTracker.trainingDate($0) ?? .distantPast) < (PersonalRecordTracker.trainingDate($1) ?? .distantPast) }
        var result: [Int: [String: [SessionExerciseLog]]] = [:]
        for record in records {
            guard let workout = workouts[record.workoutId], let week = record.blockWeek else { continue }
            for (exercise, log) in zip(workout.exercises, WorkoutSessionUtils.historyLogs(workout: workout, record: record)) {
                guard let log, !log.sets.isEmpty else { continue }
                result[week, default: [:]][key(workout, exercise), default: []].append(log)
            }
        }
        return result
    }

    private static func workingSets(_ log: SessionExerciseLog) -> [(Double, Int)] {
        log.sets.filter { !$0.isWarmup && $0.weightKg != nil && $0.reps != nil }
            .sorted { $0.setNumber < $1.setNumber }
            .map { ($0.weightKg!, $0.reps!) }
    }

    /// Fills the weeks that have begun, each from the previous week's answers and logs. Ended blocks stop at the deload.
    static func advance(_ block: TrainingBlock, program: Program, history: [WorkoutSessionRecord], weekKey: String,
                        catalog: ExerciseMuscleCatalog? = .shared) -> TrainingBlock {
        // A strength block's weeks are all known when it starts.
        guard program.id == block.programId, !block.weeks.isEmpty, !block.isStrength,
              let current = weekIndex(block, weekKey: weekKey) else { return block }
        let target = min(current, block.length)
        guard block.weeks.count < target else { return block }
        let logs = blockLogs(block, program: program, history: history)
        let feedbackByWeek = Dictionary(grouping: history.filter { $0.blockId == block.id && $0.blockWeek != nil }, by: { $0.blockWeek! })
        var result = block
        while result.weeks.count < target {
            let n = result.weeks.count + 1
            let previous = result.weeks[result.weeks.count - 1]
            if n == block.length {
                let sets = Dictionary(ruleExercises(program, catalog: catalog, sets: previous.sets).map { ($0.key, $0.sets) },
                                      uniquingKeysWith: { first, _ in first })
                result.weeks.append(TrainingBlockWeek(sets: TrainingBlockRules.deloadWeek(sets)))
            } else {
                let last = logs[n - 1] ?? [:]
                let before = logs[n - 2] ?? [:]
                let exercises = ruleExercises(program, catalog: catalog, sets: previous.sets, base: result.weeks[0].sets) { key in
                    let highs = (1..<n).reduce(0) { total, week in
                        total + (logs[week]?[key] ?? []).filter { $0.jointStress == JointStress.high.rawValue }.count
                    }
                    let highThisWeek = (last[key] ?? []).contains { $0.jointStress == JointStress.high.rawValue }
                    var fell = false
                    if let current = last[key]?.last, let earlier = before[key]?.last {
                        fell = TrainingBlockRules.performanceFell(previous: workingSets(earlier), current: workingSets(current))
                    }
                    return (highs, highThisWeek, fell)
                }
                var feedback: [String: [MuscleFeedback]] = [:]
                for record in feedbackByWeek[n - 1] ?? [] {
                    for (muscle, answers) in record.muscleFeedback ?? [:] { feedback[muscle, default: []].append(answers) }
                }
                let week = TrainingBlockRules.nextWeek(exercises, feedback: feedback, additions: result.additions)
                result.weeks.append(TrainingBlockWeek(sets: week.sets, changes: week.changes))
                result.additions = week.additions
            }
        }
        return result
    }

    /// The workout as block week `week` prescribes it: each exercise at that week's sets.
    static func sessionWorkout(_ block: TrainingBlock, week: Int, workout: Workout) -> Workout {
        guard block.weeks.indices.contains(week - 1) else { return workout }
        let sets = block.weeks[week - 1].sets
        let plan = block.isStrength ? TrainingBlockRules.strengthWeek(length: block.length, week: week) : nil
        let lifts = Set(block.lifts ?? [])
        var copy = workout
        copy.exercises = workout.exercises.map { exercise in
            var exercise = exercise
            let key = key(workout, exercise)
            if let plan, lifts.contains(key) {
                // A lift's top set and back-offs share one rep count; the test is three singles.
                exercise.sets = plan.liftSets
                exercise.reps = RepTarget(min: plan.liftReps, max: plan.liftReps)
            } else if let count = sets[key] {
                exercise.sets = count
            }
            return exercise
        }
        return copy
    }

    /// The strength week a block lift follows in this session, or nil when `exercise` is not a block lift.
    static func strengthLift(_ block: TrainingBlock?, week: Int?, workout: Workout, exercise: Exercise) -> TrainingBlockRules.StrengthWeek? {
        guard let block, let week, block.isStrength, (block.lifts ?? []).contains(key(workout, exercise)) else { return nil }
        return TrainingBlockRules.strengthWeek(length: block.length, week: week)
    }

    /// Days of history an estimated 1RM may come from.
    private static let estimateDays: Double = 42

    /// The best Brzycki estimate (1–10 reps) from `exercise`'s working sets in that workout's sessions in the last 42 days.
    static func estimatedOneRepMaxKg(workout: Workout, exercise: Exercise, history: [WorkoutSessionRecord], now: Date = Date(),
                                     excludeSessionId: String? = nil) -> Double? {
        guard let index = workout.exercises.firstIndex(where: { $0.id == exercise.id }) else { return nil }
        let since = now.addingTimeInterval(-estimateDays * 86_400)
        return history.filter { $0.workoutId == workout.id && $0.id != excludeSessionId
                && (PersonalRecordTracker.trainingDate($0) ?? .distantPast) >= since }
            .compactMap { record -> SessionExerciseLog? in
                let logs = WorkoutSessionUtils.historyLogs(workout: workout, record: record)
                return logs.indices.contains(index) ? logs[index] : nil
            }
            .flatMap(workingSets)
            .map { FormLabEngine.calculateEstimated1RM(weightKg: $0.0, reps: $0.1, formula: .brzycki) }
            .filter { $0 > 0 }.max()
    }

    struct LiftProgress: Equatable {
        var exerciseName: String
        var byWeek: [Double?]
        var testKg: Double?
    }

    /// Each strength lift's best estimate by block week and the heaviest single in the test week.
    static func liftProgress(_ block: TrainingBlock, program: Program, history: [WorkoutSessionRecord]) -> [LiftProgress] {
        let logs = blockLogs(block, program: program, history: history)
        let names = Dictionary(liftChoices(program).map { ($0.key, $0.exercise) }, uniquingKeysWith: { first, _ in first })
        return (block.lifts ?? []).compactMap { lift in
            guard let exercise = names[lift] else { return nil }
            let byWeek: [Double?] = (1..<block.length).map { week in
                (logs[week]?[lift] ?? []).flatMap(workingSets)
                    .map { FormLabEngine.calculateEstimated1RM(weightKg: $0.0, reps: $0.1, formula: .brzycki) }
                    .filter { $0 > 0 }.max()
            }
            let test = (logs[block.length]?[lift] ?? []).flatMap(workingSets).filter { $0.0 > 0 && $0.1 >= 1 }.map(\.0).max()
            return LiftProgress(exerciseName: exercise.name, byWeek: byWeek, testKg: test)
        }
    }

    /// Muscles asked about soreness before, and pump and workload after, each exercise index of a block workout.
    struct FeedbackPlan: Equatable {
        var sorenessBefore: [Int: [String]]
        var pumpAfter: [Int: [String]]
    }

    static func feedbackPlan(_ workout: Workout, catalog: ExerciseMuscleCatalog? = .shared) -> FeedbackPlan {
        let primaries = workout.exercises.map { muscles($0, catalog: catalog).primary }
        var before: [Int: [String]] = [:]
        var after: [Int: [String]] = [:]
        for muscle in TrainingBlockRules.muscles {
            let indices = primaries.indices.filter { primaries[$0].contains(muscle) }
            guard let first = indices.first, let last = indices.last else { continue }
            before[first, default: []].append(muscle)
            after[last, default: []].append(muscle)
        }
        return FeedbackPlan(sorenessBefore: before, pumpAfter: after)
    }

    /// Sets the lifter's own counts for a week and marks it reviewed.
    static func edit(_ block: TrainingBlock, week: Int, sets: [String: Int]) -> TrainingBlock {
        guard block.weeks.indices.contains(week - 1) else { return block }
        var updated = block
        var current = block.weeks[week - 1]
        for (key, count) in sets.sorted(by: { $0.key < $1.key })
        where current.sets[key] != nil && (1...maxExerciseSets).contains(count) && current.sets[key] != count {
            current.sets[key] = count
            if !current.edited.contains(key) { current.edited.append(key) }
        }
        current.reviewed = true
        updated.weeks[week - 1] = current
        return updated
    }

    static func markReviewed(_ block: TrainingBlock, week: Int) -> TrainingBlock {
        guard block.weeks.indices.contains(week - 1) else { return block }
        var updated = block
        updated.weeks[week - 1].reviewed = true
        return updated
    }

    /// Weekly sets per adjusting muscle for each computed week, in muscle order.
    static func setsByWeek(_ block: TrainingBlock, program: Program, catalog: ExerciseMuscleCatalog? = .shared) -> [(muscle: String, weeks: [Double])] {
        let weeks = block.weeks.map { week in (ruleExercises(program, catalog: catalog, sets: week.sets), week.sets) }
        return TrainingBlockRules.participants(ruleExercises(program, catalog: catalog)).map { muscle in
            (muscle, weeks.map { exercises, sets in TrainingBlockRules.weeklySets(exercises, sets: sets, muscle: muscle) })
        }
    }

    struct StrengthChange: Equatable {
        var exerciseName: String
        var fromKg: Double
        var toKg: Double
    }

    /// Best estimated 1RM (sets of 1–10 reps, as Rep Lab) on each workout's first exercise, first accumulation week against the last.
    static func strengthChanges(_ block: TrainingBlock, program: Program, history: [WorkoutSessionRecord]) -> [StrengthChange] {
        let logs = blockLogs(block, program: program, history: history)
        func best(_ week: Int, _ key: String) -> Double? {
            (logs[week]?[key] ?? []).flatMap(workingSets)
                .map { FormLabEngine.calculateEstimated1RM(weightKg: $0.0, reps: $0.1, formula: .brzycki) }
                .filter { $0 > 0 }.max()
        }
        var seen = Set<String>()
        return program.workouts.compactMap { workout in
            guard let exercise = workout.exercises.first else { return nil }
            let key = key(workout, exercise)
            guard let from = best(1, key), let to = best(block.length - 1, key), seen.insert(exercise.name).inserted else { return nil }
            return StrengthChange(exerciseName: exercise.name, fromKg: from, toKg: to)
        }
    }

    /// A stored block, or nil when it cannot belong to one of `programs`.
    static func sanitize(_ raw: TrainingBlock?, programs: [Program]) -> TrainingBlock? {
        let strength = raw?.kind == TrainingBlockRules.strength
        guard let raw, !raw.id.isEmpty, raw.id.count <= 100, TrainingBlockRules.lengths(strength: strength).contains(raw.length),
              isWeekKey(raw.startWeek), programs.contains(where: { $0.id == raw.programId }) else { return nil }
        var lifts: [String] = []
        for lift in raw.lifts ?? [] where lift.count <= 210 && !lifts.contains(lift) && lifts.count < TrainingBlockRules.maxLifts { lifts.append(lift) }
        guard !strength || !lifts.isEmpty else { return nil }
        let weeks = raw.weeks.prefix(raw.length).map { week in
            TrainingBlockWeek(
                sets: week.sets.filter { $0.key.count <= 210 && (1...maxExerciseSets).contains($0.value) },
                changes: week.changes.filter { TrainingBlockRules.muscles.contains($0.muscle) && $0.from.isFinite && $0.to.isFinite }
                    .map { change in
                        var change = change
                        change.reasons = change.reasons.filter(reasons.contains)
                        return change
                    },
                edited: week.edited.filter { $0.count <= 210 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } },
                reviewed: week.reviewed)
        }
        guard !weeks.isEmpty else { return nil }
        var focus: [String] = []
        for muscle in raw.focus where TrainingBlockRules.muscles.contains(muscle) && !focus.contains(muscle) && focus.count < TrainingBlockRules.maxFocus {
            focus.append(muscle)
        }
        return TrainingBlock(id: raw.id, programId: raw.programId, startWeek: raw.startWeek, length: raw.length, focus: focus,
                             weeks: Array(weeks), additions: Array(raw.additions.filter { $0.count <= 210 }.prefix(200)),
                             kind: strength ? TrainingBlockRules.strength : nil, lifts: strength ? lifts : nil)
    }
}
