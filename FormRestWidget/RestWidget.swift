import ActivityKit
import SwiftUI
import WidgetKit

@main struct ForcedRepRestWidgets: WidgetBundle {
    var body: some Widget { RestActivityWidget() }
}

struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestActivityContent(state: context.state).padding(16)
                .widgetURL(URL(string: "forcedrep://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) { RestActivityContent(state: context.state) }
            } compactLeading: {
                Image(systemName: "timer").accessibilityLabel(context.state.exerciseName)
            } compactTrailing: {
                RestActivityTime(state: context.state).font(.system(.caption, design: .monospaced)).frame(width: 48)
            } minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.fill")
            }.widgetURL(URL(string: "forcedrep://workout"))
        }
    }
}
