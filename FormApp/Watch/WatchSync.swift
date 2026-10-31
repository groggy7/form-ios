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
