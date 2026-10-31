import Foundation

/// The iPhone ↔ Apple Watch contract (docs/apple-watch.md). FormApp and FormWatch both compile this file,
/// so it uses Foundation only. The iPhone owns the workout; the watch shows snapshots and sends commands.
enum WatchSync {
    /// Raised only for an incompatible change; added optional fields keep the version.
    static let protocolVersion = 1
    /// WatchConnectivity dictionary keys. Values are JSON `Data`.
    static let snapshotKey = "snapshot"
    static let commandKey = "command"

    static func encoded<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    static func decoded<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        (value as? Data).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    static func nowMillis(_ date: Date = Date()) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
}

struct WatchSnapshot: Codable, Equatable {
    enum Access: String, Codable { case premium, locked }

    var version = WatchSync.protocolVersion
    /// iPhone time in milliseconds when built; the watch ignores an older snapshot.
    var revision: Int64
    /// The language the iPhone app resolved, so its in-app choice applies on the watch.
    var language: String
    var access: Access
    /// Nil without an active workout, and always nil while locked.
    var session: Session?
    /// The iPhone setting that records each workout as an Apple Health workout on the watch.
    var recordsWorkouts: Bool? = nil
    /// The iPhone's last workout that ended, so the watch saves or discards its Health workout to match.
    var finished: Finished? = nil

    struct Finished: Codable, Equatable {
        var sessionId: String
        /// Saved to history (completed or unfinished); false when discarded.
        var saved: Bool
        var endedAt: Int64
    }

    struct Session: Codable, Equatable {
        var id: String
        var title: String
        /// `WeightUnit` raw value ("kg" or "lbs"); every load in the session uses it.
        var unit: String
        /// Every exercise with its sets, so the watch can change exercise while the iPhone is out of reach.
        var exercises: [Exercise]
        var currentIndex: Int
        /// Where the iPhone's Next button goes, superset partner first; nil on the last exercise.
        var nextIndex: Int?
        var rest: Rest?
        /// Every working set is done; finishing and saving stay on the iPhone.
        var allLogged: Bool
    }

    struct Exercise: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        /// Superset position such as "A1".
        var label: String?
        var sets: [SetRow]
        /// Display-unit load change for one crown step.
        var loadStep: Double
        var allowsZeroLoad: Bool
        /// The load is added to bodyweight.
        var isBodyweight: Bool
        /// The load is machine assistance.
        var isAssisted: Bool
    }

    struct SetRow: Codable, Equatable, Identifiable {
        var id: String
        var number: Int
        var isWarmup: Bool
        /// Entered load in the session unit; nil while the field is empty.
        var load: Double?
        /// Entered reps; nil while the field is empty.
        var reps: Int?
        /// What an empty reps field suggests: the coach's target, then the prescription's lower bound.
        var suggestedReps: Int?
        var isCompleted: Bool
        /// Drops, rest-pause or partials, which only the iPhone edits.
        var hasParts: Bool
        /// Seconds of rest that completing this set starts; nil when it starts none.
        var restAfter: Int?
    }

    struct Rest: Codable, Equatable {
        /// The set whose completion started the rest; rest commands must name it.
        var setId: String?
        var exerciseName: String
        var totalSeconds: Int
        var endsAt: Int64?
        var pausedRemaining: Int
        var isRunning: Bool

        func secondsRemaining(now: Int64) -> Int {
            guard isRunning else { return max(0, pausedRemaining) }
            guard let endsAt else { return 0 }
            return max(0, Int((endsAt - now + 999) / 1000))
        }
    }
}

struct WatchCommand: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case completeSet, undoSet, selectExercise
        case pauseRest, resumeRest, addRest, skipRest
        /// Asks for the current snapshot.
        case refresh
    }

    var id = UUID().uuidString
    var kind: Kind
    var sessionId: String?
    var exerciseId: String?
    /// The set to change, or for rest commands the set that started the rest.
    var setId: String?
    /// Display-unit load and its unit, so a unit change on the iPhone cannot reinterpret it.
    var load: Double?
    var unit: String?
    var reps: Int?
    var seconds: Int?
    var sentAt: Int64 = WatchSync.nowMillis()

    /// Rest deadlines and refreshes are meaningless later, so only set changes are queued while unreachable.
    var isQueueable: Bool {
        switch kind {
        case .completeSet, .undoSet, .selectExercise: return true
        case .pauseRest, .resumeRest, .addRest, .skipRest, .refresh: return false
        }
    }
}

/// The watch's Apple Health workout, as the planner sees it.
struct RunningWorkout: Equatable {
    /// The iPhone workout it records; nil while a workout started from the iPhone waits for its first snapshot.
    var sessionId: String?
    var startedAt: Int64
}

/// One change to the watch's Apple Health workout (docs/apple-watch.md, phase 2). The watch applies one step,
/// then asks again, so a workout that ends and another that starts take two steps.
enum WatchWorkoutStep: Equatable {
    case start(sessionId: String)
    /// Ties a workout the iPhone started before any snapshot arrived to that snapshot's workout.
    case adopt(sessionId: String)
    /// Saves the Health workout when the iPhone saved its workout, and discards it otherwise.
    case finish(save: Bool, endedAt: Int64?)
}

extension WatchSnapshot {
    /// - Parameter skipped: workouts the watch could not record, for example without Health access; never retried.
    func workoutStep(running: RunningWorkout?, skipped: Set<String>) -> WatchWorkoutStep? {
        if let running {
            if let finished, finished.sessionId == running.sessionId || (running.sessionId == nil && finished.endedAt >= running.startedAt) {
                return .finish(save: finished.saved, endedAt: finished.endedAt)
            }
            guard let id = running.sessionId else { return session.map { .adopt(sessionId: $0.id) } }
            if access == .premium, session?.id == id { return nil }
            // Its workout ended without word from the iPhone (cleared data or Premium ended): write nothing.
            return .finish(save: false, endedAt: nil)
        }
        guard access == .premium, recordsWorkouts == true, let session, finished?.sessionId != session.id,
              !skipped.contains(session.id) else { return nil }
        return .start(sessionId: session.id)
    }
}

/// A set the watch is about to show, with the values the iPhone would prefill.
struct WatchSetPreview: Equatable {
    var exercise: WatchSnapshot.Exercise
    var set: WatchSnapshot.SetRow
    var load: Double?
    var reps: Int?
}

extension WatchSnapshot.Exercise {
    /// The open set's own values, else the previous completed set's, as the iPhone prefills; reps fall back to the target.
    var openSet: WatchSetPreview? {
        guard let index = sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let set = sets[index]
        let previous = sets[..<index].last { $0.isCompleted }
        return WatchSetPreview(exercise: self, set: set, load: set.load ?? previous?.load,
                               reps: set.reps ?? set.suggestedReps ?? previous?.reps)
    }
}

extension WatchSnapshot.Session {
    /// What the workout continues with after a rest, shown while resting: the superset partner first, as the iPhone's
    /// Next button goes, then this exercise, then the next one. Nil when every set is logged.
    var upNext: WatchSetPreview? {
        guard exercises.indices.contains(currentIndex) else { return nil }
        let current = exercises[currentIndex]
        let next = nextIndex.flatMap { exercises.indices.contains($0) ? exercises[$0] : nil }
        let group = { (label: String?) in label.map { String($0.prefix { !$0.isNumber }) } }
        let partner = next.flatMap { current.label != nil && group($0.label) == group(current.label) ? $0 : nil }
        return [partner, current, next].compactMap { $0 }.lazy.compactMap(\.openSet).first
    }
}
