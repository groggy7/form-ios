import Combine
import Foundation
import UIKit
import WatchConnectivity

/// Mirrors the active workout to Apple Watch and applies its commands on the main thread (docs/apple-watch.md).
/// The draft stays the only workout state; a watch command is one more `updateActiveSession` caller.
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()
    private var store: AppStore?
    private var cancellables = Set<AnyCancellable>()
    /// The last snapshot sent, without its revision, so an unchanged workout is not resent.
    private var lastSent: WatchSnapshot?

    /// Activates once per process, from launch or a background wake by the watch. Tests never activate.
    func start(store makeStore: @autoclosure () -> AppStore) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.store == nil, WCSession.isSupported(), NSClassFromString("XCTestCase") == nil else { return }
        let store = makeStore()
        self.store = store
        WCSession.default.delegate = self
        WCSession.default.activate()
        let settings = Publishers.CombineLatest4(store.$weightUnit, store.$barType, store.$availablePlatesKg, store.$availablePlatesLbs)
            .map { _ in () }
        let steps = Publishers.CombineLatest4(store.$dumbbellStepKg, store.$dumbbellStepLbs, store.$machineStepKg, store.$machineStepLbs)
            .map { _ in () }
        Publishers.CombineLatest4(store.$activeSession.map { _ in () }, settings, steps,
                                  LanguageManager.shared.$currentLanguage.combineLatest(ProAccessManager.shared.$isProSubscribed).map { _ in () })
            // Published values change in willSet; the next main-loop turn reads the settled store.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publish() }
            .store(in: &cancellables)
    }

    /// The watch companion is Premium (docs/monetization.md).
    private var isPremium: Bool { ProAccessManager.shared.isProSubscribed }

    private func snapshot() -> WatchSnapshot? {
        guard let store else { return nil }
        return WatchSnapshotBuilder.build(draft: store.activeSession, unit: store.weightUnit,
                                          language: LanguageManager.shared.currentLanguage,
                                          isPremium: isPremium,
                                          steps: store.progressionLoadSteps, now: WatchSync.nowMillis())
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
        DispatchQueue.main.async { self.publish(force: true) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch deactivates the session; the new watch needs its own snapshot.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.publish(force: true) }
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
