import SwiftUI
import Foundation

struct RestActivityContent: View {
    let state: RestActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.isRunning ? state.timerLabel : state.pausedLabel).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.exerciseName).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            RestActivityTime(state: state).font(.system(.title2, design: .rounded).monospacedDigit()).fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.75).frame(width: 90, alignment: .trailing).layoutPriority(1)
                .accessibilityIdentifier("rest-activity-time")
        }
    }
}
struct RestActivityTime: View {
    let state: RestActivityAttributes.ContentState
    var body: some View {
        if state.isRunning, let deadline = state.deadline {
            Text(timerInterval: Date(timeIntervalSince1970: 0)...deadline, countsDown: true).monospacedDigit()
        } else {
            Text(String(format: "%d:%02d", max(0, state.remainingSeconds) / 60, max(0, state.remainingSeconds) % 60)).monospacedDigit()
        }
    }
}
