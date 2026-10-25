import ActivityKit
import Foundation
import UIKit

struct RestLiveActivitySnapshot: Equatable {
    var sessionId: String
    var content: RestActivityAttributes.ContentState

    static func from(_ draft: ActiveSessionDraft?, now: Int64) -> Self? {
        guard let draft, let rest = draft.restTimer, rest.secondsRemaining(nowEpochMillis: now) > 0 else { return nil }
        let running = rest.isRunning && !draft.isPaused && rest.endsAtEpochMillis != nil
        let deadline = running ? rest.endsAtEpochMillis.map { Date(timeIntervalSince1970: Double($0) / 1000) } : nil
        let name = ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: rest.exerciseName)
        return Self(sessionId: draft.id, content: .init(exerciseName: name, deadline: deadline,
            remainingSeconds: running ? rest.totalSeconds : rest.secondsRemaining(nowEpochMillis: now), isRunning: running,
            timerLabel: LanguageManager.t("rest.title"), pausedLabel: LanguageManager.t("rest.paused")))
    }
}

/// Serializes asynchronous ActivityKit updates so a canceled or replaced rest cannot reappear.
@MainActor final class RestLiveActivityCoordinator {
    static let shared = RestLiveActivityCoordinator()
    private let enabled: Bool
    private var lastDraft: ActiveSessionDraft?
    private var desired: RestLiveActivitySnapshot?
    private var revision = 0
    private var lastRequest: RestLiveActivitySnapshot?
    private(set) var processing = false
    private(set) var lastError: String?
    private var foregroundObserver: NSObjectProtocol?

    init(enabled: Bool = NSClassFromString("XCTestCase") == nil) {
        self.enabled = enabled
        if enabled {
            foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; self.sync(self.lastDraft) }
            }
        }
    }
    deinit { if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) } }

    func sync(_ draft: ActiveSessionDraft?) {
        lastDraft = draft
        desired = .from(draft, now: Int64(Date().timeIntervalSince1970 * 1000))
        revision += 1
        guard enabled, !processing else { return }
        processing = true
        Task { await drain() }
    }
    private func drain() async {
        while true {
            let version = revision
            await apply(desired)
            if version == revision { processing = false; return }
        }
    }
    private func apply(_ snapshot: RestLiveActivitySnapshot?) async {
        let activities = Activity<RestActivityAttributes>.activities
        guard let snapshot else {
            lastRequest = nil
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let current = activities.first { $0.attributes.sessionId == snapshot.sessionId && ($0.activityState == .active || $0.activityState == .stale) }
        for activity in activities where activity.id != current?.id { await activity.end(nil, dismissalPolicy: .immediate) }
        let content = ActivityContent(state: snapshot.content, staleDate: snapshot.content.deadline)
        if let current {
            lastRequest = snapshot
            if current.content.state != snapshot.content { await current.update(content) }
        } else if snapshot != lastRequest && UIApplication.shared.applicationState == .active && ActivityAuthorizationInfo().areActivitiesEnabled {
            lastRequest = snapshot
            // Local-only: there is no token, push service, network call, or separate timer.
            lastError = nil
            do { _ = try Activity.request(attributes: RestActivityAttributes(sessionId: snapshot.sessionId), content: content, pushType: nil) }
            catch { lastError = String(describing: error) }
        }
    }
}
