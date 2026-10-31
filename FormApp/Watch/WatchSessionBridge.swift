import Combine
import Foundation
import HealthKit
import UIKit
import WatchConnectivity

/// Mirrors the active workout to Apple Watch and applies its commands on the main thread (docs/apple-watch.md).
/// The draft stays the only workout state; a watch command is one more `updateActiveSession` caller.
final class WatchSessionBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()
    private static let finishedKey = "watch_last_finished_v1"
    /// A paired watch has the app, so Settings can offer its options.
    @Published private(set) var isWatchAppInstalled = false
    private var store: AppStore?
    private var cancellables = Set<AnyCancellable>()
    private let healthStore = HKHealthStore()
    /// The last snapshot sent, without its revision, so an unchanged workout is not resent.
    private var lastSent: WatchSnapshot?
    /// The workout seen last, with its history record when it began, to tell a save from a discard.
    private var trackedSessionId: String?
    private var recordAtStart: WorkoutSessionRecord?
    private var isTracking = false
    /// Kept across launches, so a watch that hears late still ends its Health workout the same way.
    private var finished: WatchSnapshot.Finished? {
        get { WatchSync.decoded(WatchSnapshot.Finished.self, from: UserDefaults.standard.data(forKey: Self.finishedKey)) }
        set { UserDefaults.standard.set(newValue.flatMap(WatchSync.encoded), forKey: Self.finishedKey) }
    }

    /// Activates once per process, from launch or a background wake by the watch. Tests never activate.
    func start(store makeStore: @autoclosure () -> AppStore) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.store == nil, WCSession.isSupported(), NSClassFromString("XCTestCase") == nil else { return }
        let store = makeStore()
        self.store = store
        WCSession.default.delegate = self
        WCSession.default.activate()
        let changes: [AnyPublisher<Void, Never>] = [
            store.liveSession.$draft.map { _ in () }.eraseToAnyPublisher(),
            store.$weightUnit.map { _ in () }.eraseToAnyPublisher(),
            store.$barType.map { _ in () }.eraseToAnyPublisher(),
            store.$availablePlatesKg.map { _ in () }.eraseToAnyPublisher(),
            store.$availablePlatesLbs.map { _ in () }.eraseToAnyPublisher(),
            store.$dumbbellStepKg.map { _ in () }.eraseToAnyPublisher(),
            store.$dumbbellStepLbs.map { _ in () }.eraseToAnyPublisher(),
            store.$machineStepKg.map { _ in () }.eraseToAnyPublisher(),
            store.$machineStepLbs.map { _ in () }.eraseToAnyPublisher(),
            store.$recordWatchWorkouts.map { _ in () }.eraseToAnyPublisher(),
            LanguageManager.shared.$currentLanguage.map { _ in () }.eraseToAnyPublisher(),
            ProAccessManager.shared.$isProSubscribed.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes)
            // Published values change in willSet; the next main-loop turn reads the settled store.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.trackSession()
                self?.publish()
            }
            .store(in: &cancellables)
    }

    /// Notes how the last workout ended, and starts the watch app for a new one.
    private func trackSession() {
        guard let store else { return }
        let id = store.activeSession?.id
        guard !isTracking || id != trackedSessionId else { return }
        if isTracking, let ended = trackedSessionId {
            finished = WatchSnapshotBuilder.finished(sessionId: ended, recordAtStart: recordAtStart,
                                                     history: store.state.history, now: WatchSync.nowMillis())
        }
        trackedSessionId = id
        recordAtStart = id.flatMap { id in store.state.history.first { $0.id == id } }
        // The draft restored at launch is not a new workout; the watch already follows it or chose not to.
        if isTracking, let id {
            // A workout resumed from History first drops its finished marker, so the watch records this bout too.
            let marker = finished
            if WatchSnapshotBuilder.stillFinished(marker, openedId: id) != marker { finished = nil }
            startWatchWorkout()
        }
        isTracking = true
    }

    /// Opens the watch app into a strength workout, where it records the workout in Apple Health.
    private func startWatchWorkout() {
        guard let store, store.recordWatchWorkouts, isPremium, HKHealthStore.isHealthDataAvailable() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        healthStore.startWatchApp(with: configuration) { _, error in
            if let error { print("Starting the watch workout failed: \(error)") }
        }
    }

    /// The watch companion is Premium (docs/monetization.md).
    private var isPremium: Bool { ProAccessManager.shared.isProSubscribed }

    private func snapshot() -> WatchSnapshot? {
        guard let store else { return nil }
        return WatchSnapshotBuilder.build(draft: store.activeSession, unit: store.weightUnit,
                                          language: LanguageManager.shared.currentLanguage,
                                          isPremium: isPremium,
                                          steps: store.progressionLoadSteps, recordsWorkouts: store.recordWatchWorkouts,
                                          finished: finished, now: WatchSync.nowMillis())
    }

    private func publish(force: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let snapshot = snapshot(), let data = WatchSync.encoded(snapshot) else { return }
        var unversioned = snapshot
        unversioned.revision = 0
        guard force || unversioned != lastSent else { return }
        lastSent = unversioned
        do { try session.updateApplicationContext([WatchSync.snapshotKey: data]) }
        catch { print("Watch context update failed: \(error)") }
        if session.isReachable {
            session.sendMessage([WatchSync.snapshotKey: data], replyHandler: nil, errorHandler: nil)
        }
    }

    /// Applies one command and returns the resulting snapshot for the watch's reply.
    private func handle(_ command: WatchCommand?) -> Data? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let store else { return nil }
        // A command queued before Premium ended is answered with the locked snapshot instead.
        if let command, isPremium, let draft = store.activeSession,
           let updated = WatchCommandHandler.apply(command, to: draft, unit: store.weightUnit,
                                                   prefillNextSet: store.prefillNextSet, now: WatchSync.nowMillis()) {
            store.updateActiveSession { _ in updated }
            // A background wake may be suspended right after the reply.
            if UIApplication.shared.applicationState != .active { store.flushPendingState() }
        }
        // The application context must hold the result too, for a watch that relaunches.
        publish()
        return snapshot().flatMap(WatchSync.encoded)
    }

    // MARK: WCSessionDelegate (called on a background queue)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let installed = activationState == .activated && session.isPaired && session.isWatchAppInstalled
        DispatchQueue.main.async {
            self.isWatchAppInstalled = installed
            self.publish(force: true)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch deactivates the session; the new watch needs its own snapshot.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isPaired && session.isWatchAppInstalled
        DispatchQueue.main.async {
            self.isWatchAppInstalled = installed
            self.publish(force: true)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command = WatchSync.decoded(WatchCommand.self, from: message[WatchSync.commandKey])
        DispatchQueue.main.async {
            let data = self.handle(command)
            replyHandler(data.map { [WatchSync.snapshotKey: $0] } ?? [:])
        }
    }

    /// Set commands queued while the iPhone was out of reach arrive here in order.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let command = WatchSync.decoded(WatchCommand.self, from: userInfo[WatchSync.commandKey])
        DispatchQueue.main.async { _ = self.handle(command) }
    }
}
