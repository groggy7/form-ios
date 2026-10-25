import ActivityKit
import Foundation

/// Shared by the app and its widget extension; all time comes from the workout's rest state.
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var deadline: Date?
        var remainingSeconds: Int
        var isRunning: Bool
        var timerLabel: String
        var pausedLabel: String
    }
    var sessionId: String
}
