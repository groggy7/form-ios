import Foundation
import UserNotifications

/// Identifies one running rest by its session and deadline, matching Android's `RestAlarmKey`.
public struct RestAlertKey: Hashable {
    public let sessionId: String
    public let endsAtEpochMillis: Int64

    public static func from(_ draft: ActiveSessionDraft?) -> RestAlertKey? {
        guard let draft, let rest = draft.restTimer, rest.isRunning, let end = rest.endsAtEpochMillis else { return nil }
        return RestAlertKey(sessionId: draft.id, endsAtEpochMillis: end)
    }
}

/// Schedules the local notification that announces a rest ending while Forced Rep is
/// backgrounded, locked or no longer running. A visible workout plays its own chime instead.
final class RestAlertScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestAlertScheduler()
    static let requestIdentifier = "forcedrep.rest-complete"
    static let soundName = UNNotificationSoundName("form_rest_complete.wav")

    private struct Plan: Equatable {
        let key: RestAlertKey
        let soundEnabled: Bool
    }

    /// Read from the notification delegate; the open workout handles its own rest completion.
    var isWorkoutVisible = false
    private var plan: Plan?
    // Tests drive AppStore without touching the simulator's notification settings.
    private let isEnabled = NSClassFromString("XCTestCase") == nil

    /// Runs before launch finishes so the delegate sees notifications from the start.
    func install() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func update(for draft: ActiveSessionDraft?, soundEnabled: Bool) {
        let next = RestAlertKey.from(draft).map { Plan(key: $0, soundEnabled: soundEnabled) }
        guard next != plan else { return }
        plan = next
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
        guard let next, let exerciseName = draft?.restTimer?.exerciseName else { return }
        // Asks on the first rest rather than at launch; declining never blocks a workout.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                // The rest may have been skipped or replaced while the permission prompt was open.
                guard self.plan == next, let request = Self.request(for: next.key, exerciseName: exerciseName,
                    soundEnabled: next.soundEnabled, nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000)) else { return }
                center.add(request)
            }
        }
    }

    /// Removes an already-shown rest alert once the user is back in the app.
    func clearDelivered() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
    }

    static func request(for key: RestAlertKey, exerciseName: String, soundEnabled: Bool,
                        nowEpochMillis: Int64) -> UNNotificationRequest? {
        let interval = TimeInterval(key.endsAtEpochMillis - nowEpochMillis) / 1000
        guard interval > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = LanguageManager.t("notification.restComplete")
        content.body = ContentLocalizer.shared.exerciseName(exerciseId: nil, fallback: exerciseName)
        // iOS has no vibration-only local notification, so muted rests post a silent alert.
        content.sound = soundEnabled ? UNNotificationSound(named: soundName) : nil
        return UNNotificationRequest(identifier: requestIdentifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isRest = notification.request.identifier == Self.requestIdentifier
        completionHandler(isRest && isWorkoutVisible ? [] : [.banner, .list, .sound])
    }
}
