import SwiftUI
import WatchKit

/// The iPhone's rest, counted down from its deadline. Controls need the iPhone, since a rest is not queued.
struct RestPage: View {
    @ObservedObject var store: WatchStore
    let rest: WatchSnapshot.Rest
    let remaining: Int

    var body: some View {
        VStack(spacing: 6) {
            Text(store.t(rest.isRunning ? "watch.rest" : "watch.rest.paused"))
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(WatchColors.restAccent)
            ZStack {
                Circle().stroke(WatchColors.restTrack, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: Double(remaining) / Double(max(1, rest.totalSeconds)))
                    .stroke(WatchColors.restAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(WatchStrings.clock(remaining))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WatchColors.text)
            }
            .padding(4)
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                Text(rest.exerciseName)
                    .font(.caption2)
                    .foregroundStyle(WatchColors.secondaryText)
                    .lineLimit(1)
                HeartRateLabel(store: store)
            }
            HStack(spacing: 6) {
                control(label: store.t(rest.isRunning ? "watch.rest.pause" : "watch.rest.resume")) {
                    Image(systemName: rest.isRunning ? "pause.fill" : "play.fill")
                } action: {
                    store.send(rest.isRunning ? .pauseRest : .resumeRest, set: rest.setId)
                }
                control(label: store.t("watch.rest.add")) {
                    Text("+30s")
                } action: {
                    store.send(.addRest, set: rest.setId, seconds: 30)
                }
                control(label: store.t("watch.rest.skip")) {
                    Text(store.t("watch.rest.skip")).lineLimit(1).minimumScaleFactor(0.6)
                } action: {
                    store.send(.skipRest, set: rest.setId)
                }
            }
            .disabled(!store.isReachable)
            .opacity(store.isReachable ? 1 : 0.5)
        }
        .toolbar {
            if !store.isReachable {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(WatchColors.muted)
                        .accessibilityLabel(store.t("watch.offline"))
                }
            }
        }
    }

    private func control<Label: View>(label: String, @ViewBuilder content: () -> Label, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            content()
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(WatchColors.restAccent)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WatchColors.restSurface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WatchColors.restBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
