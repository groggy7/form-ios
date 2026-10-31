import Foundation
import WatchConnectivity
import WatchKit

/// The watch's copy of the iPhone workout, its optimistic changes and the commands it sends (docs/apple-watch.md).
/// The iPhone owns the workout: a newer iPhone snapshot always replaces what the watch guessed.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()
    private static let cacheKey = "watch_snapshot_v1"

    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var isReachable = false
    /// The iPhone speaks a newer contract than this watch build understands.
    @Published private(set) var needsUpdate = false
    /// The latest command sent with `sendMessage` and still waiting for its reply.
    private var awaitingReply: String?
    /// A pushed snapshot built before this command reached the iPhone would undo its optimistic change.
    private var lastCommandAt: Int64 = 0
    private var restEndTimer: Timer?

    override init() {
        super.init()
        snapshot = WatchSync.decoded(WatchSnapshot.self, from: UserDefaults.standard.data(forKey: Self.cacheKey))
        scheduleRestEnd()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var session: WatchSnapshot.Session? { snapshot?.access == .premium ? snapshot?.session : nil }
    var language: String { snapshot?.language ?? Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en" }

    func t(_ key: String, _ params: [String: Any] = [:]) -> String {
        WatchStrings.t(key, language: language, params)
    }

    // MARK: Commands

    func send(_ kind: WatchCommand.Kind, exercise: String? = nil, set: String? = nil, load: Double? = nil, reps: Int? = nil, seconds: Int? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        let current = session
        // Only a refresh makes sense without a workout.
        guard current != nil || kind == .refresh else { return }
        let command = WatchCommand(kind: kind, sessionId: current?.id, exerciseId: exercise, setId: set,
                                   load: load, unit: load == nil ? nil : current?.unit, reps: reps, seconds: seconds)
        lastCommandAt = command.sentAt
        if let current { update(current.applying(command, now: command.sentAt)) }
        let wc = WCSession.default
        guard wc.activationState == .activated, let data = WatchSync.encoded(command) else { return }
        let message: [String: Any] = [WatchSync.commandKey: data]
        if wc.isReachable {
            awaitingReply = command.id
            wc.sendMessage(message, replyHandler: { [weak self] reply in
                let snapshot = WatchSync.decoded(WatchSnapshot.self, from: reply[WatchSync.snapshotKey])
                DispatchQueue.main.async { self?.receive(snapshot, replyTo: command.id) }
            }, errorHandler: { [weak self] _ in
                // Commands are idempotent, so queueing one the iPhone may already have applied is safe.
                if command.isQueueable { wc.transferUserInfo(message) }
                DispatchQueue.main.async { if self?.awaitingReply == command.id { self?.awaitingReply = nil } }
            })
        } else if command.isQueueable {
            wc.transferUserInfo(message)
        }
    }

    private func update(_ session: WatchSnapshot.Session) {
        guard var next = snapshot else { return }
        next.session = session
        set(next)
    }

    // MARK: Snapshots

    private func receive(_ incoming: WatchSnapshot?, replyTo: String? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let incoming else { return }
        guard incoming.version <= WatchSync.protocolVersion else { needsUpdate = true; return }
        needsUpdate = false
        if let replyTo {
            guard replyTo == awaitingReply else { return }
            awaitingReply = nil
        } else {
            guard awaitingReply == nil, incoming.revision >= lastCommandAt, incoming.revision >= (snapshot?.revision ?? 0) else { return }
        }
        set(incoming)
        // Only the iPhone's own snapshots move the Health workout; a cached or guessed one never starts it.
        WorkoutRecorder.shared.update(for: incoming)
    }

    private func set(_ next: WatchSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        UserDefaults.standard.set(WatchSync.encoded(next), forKey: Self.cacheKey)
        scheduleRestEnd()
    }

    /// A rest that ends while the app is in front, or while it records a Health workout, taps the wrist;
    /// otherwise the iPhone's notification is the alert.
    private func scheduleRestEnd() {
        restEndTimer?.invalidate()
        guard let rest = session?.rest, rest.isRunning, let end = rest.endsAt, end > WatchSync.nowMillis() else { return }
        let timer = Timer(fire: Date(timeIntervalSince1970: Double(end) / 1000), interval: 0, repeats: false) { [weak self] _ in
            guard let self, var current = self.session, current.rest == rest else { return }
            // A timer that fires late, as the app returns, does not tap for a rest that ended long ago.
            if WatchSync.nowMillis() - end < 3000,
               WKApplication.shared().applicationState == .active || WorkoutRecorder.shared.isRecording {
                WKInterfaceDevice.current().play(.notification)
            }
            current.rest = nil
            self.update(current)
        }
        RunLoop.main.add(timer, forMode: .common)
        restEndTimer = timer
    }

    // MARK: WCSessionDelegate (called on a background queue)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = WatchSync.decoded(WatchSnapshot.self, from: session.receivedApplicationContext[WatchSync.snapshotKey])
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
            self.receive(context)
            if reachable { self.send(.refresh) }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
            if reachable { self.send(.refresh) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snapshot = WatchSync.decoded(WatchSnapshot.self, from: applicationContext[WatchSync.snapshotKey])
        DispatchQueue.main.async { self.receive(snapshot) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let snapshot = WatchSync.decoded(WatchSnapshot.self, from: message[WatchSync.snapshotKey])
        DispatchQueue.main.async { self.receive(snapshot) }
    }
}

/// The watch's guess at what the iPhone will do with a command, shown until the iPhone's answer arrives.
extension WatchSnapshot.Session {
    func applying(_ command: WatchCommand, now: Int64) -> Self {
        var copy = self
        switch command.kind {
        case .completeSet, .undoSet:
            guard let e = exercises.firstIndex(where: { $0.id == command.exerciseId }),
                  let s = exercises[e].sets.firstIndex(where: { $0.id == command.setId }) else { return self }
            let completing = command.kind == .completeSet
            copy.exercises[e].sets[s].isCompleted = completing
            if completing {
                copy.exercises[e].sets[s].load = command.load ?? exercises[e].sets[s].load
                copy.exercises[e].sets[s].reps = command.reps ?? exercises[e].sets[s].reps
                if let seconds = exercises[e].sets[s].restAfter, seconds > 0 {
                    copy.rest = WatchSnapshot.Rest(setId: command.setId, exerciseName: exercises[e].name, totalSeconds: seconds,
                                     endsAt: now + Int64(seconds) * 1000, pausedRemaining: 0, isRunning: true)
                }
            } else if rest?.setId == command.setId {
                copy.rest = nil
            }
            copy.allLogged = copy.exercises.allSatisfy { exercise in
                let working = exercise.sets.filter { !$0.isWarmup }
                return !(working.isEmpty ? exercise.sets : working).contains { !$0.isCompleted }
            }
        case .selectExercise:
            guard let index = exercises.firstIndex(where: { $0.id == command.exerciseId }) else { return self }
            copy.currentIndex = index
            copy.nextIndex = index + 1 < exercises.count ? index + 1 : nil
        case .pauseRest, .resumeRest, .addRest, .skipRest:
            guard var rest else { return self }
            let remaining = rest.secondsRemaining(now: now)
            switch command.kind {
            case .pauseRest:
                rest.isRunning = false
                rest.endsAt = nil
                rest.pausedRemaining = remaining
            case .resumeRest:
                rest.isRunning = remaining > 0
                rest.endsAt = remaining > 0 ? now + Int64(remaining) * 1000 : nil
            case .addRest:
                let added = max(0, remaining + (command.seconds ?? 30))
                rest.totalSeconds = max(rest.totalSeconds, added)
                rest.pausedRemaining = added
                rest.endsAt = rest.isRunning ? now + Int64(added) * 1000 : nil
            default:
                copy.rest = nil
                return copy
            }
            copy.rest = rest
        case .refresh:
            break
        }
        return copy
    }
}
