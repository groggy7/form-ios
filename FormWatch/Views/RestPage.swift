import SwiftUI
import WatchKit

/// The iPhone's rest, counted down from its deadline. Controls need the iPhone, since a rest is not queued; undoing
/// the set that started it does not, and also ends the rest. Up next names the set to load the bar for.
struct RestPage: View {
    @ObservedObject var store: WatchStore
    let session: WatchSnapshot.Session
    let rest: WatchSnapshot.Rest
    let remaining: Int

    /// The completed set whose rest this is, so a mistaken Done can be undone without skipping the rest first.
    private var origin: (exercise: WatchSnapshot.Exercise, set: WatchSnapshot.SetRow)? {
        for exercise in session.exercises {
            if let set = exercise.sets.first(where: { $0.id == rest.setId && $0.isCompleted }) { return (exercise, set) }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(store.t(rest.isRunning ? "watch.rest" : "watch.rest.paused"))
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(WatchColors.restAccent)
                HeartRateLabel(store: store)
            }
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
            upNext
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
            // The disabled controls say why instead of ignoring taps.
            if !store.isReachable {
                Text(store.t("watch.offline"))
                    .font(.system(size: 11))
                    .foregroundStyle(WatchColors.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .toolbar {
            if let origin {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        store.send(.undoSet, exercise: origin.exercise.id, set: origin.set.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(WatchColors.text)
                    }
                    .tint(WatchColors.surfaceRaised)
                    .accessibilityLabel(store.t("watch.undo", ["number": origin.set.number]))
                }
            }
            if !store.isReachable {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "iphone.slash")
                        .foregroundStyle(WatchColors.muted)
                        .accessibilityLabel(store.t("watch.offline"))
                }
            }
        }
    }

    /// The set the workout continues with, and the values the set editor will show for it.
    @ViewBuilder private var upNext: some View {
        if let next = session.upNext {
            let unit = session.unit == "lbs" ? "lbs" : "kg"
            let values = [next.load.map { "\(WatchStrings.load($0, language: store.language)) \(unit)" }, next.reps.map { "× \($0)" }]
                .compactMap { $0 }.joined(separator: " ")
            let label = next.set.isWarmup ? store.t("watch.warmup")
                : store.t("watch.set", ["number": next.set.number, "count": next.exercise.sets.filter { !$0.isWarmup }.count])
            VStack(spacing: 0) {
                Text("\(store.t("watch.upNext")): \([next.exercise.label, next.exercise.name].compactMap { $0 }.joined(separator: " · "))")
                    .foregroundStyle(WatchColors.secondaryText)
                Text([label, values].filter { !$0.isEmpty }.joined(separator: " · "))
                    .monospacedDigit()
                    .foregroundStyle(WatchColors.muted)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        } else {
            Text(rest.exerciseName)
                .font(.caption2)
                .foregroundStyle(WatchColors.secondaryText)
                .lineLimit(1)
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
