import SwiftUI

struct WatchRootView: View {
    @ObservedObject var store: WatchStore
    @State private var page = 0

    var body: some View {
        NavigationStack {
            if store.needsUpdate {
                MessagePage(symbol: "arrow.down.circle", title: nil, message: store.t("watch.update.body"))
            } else if store.snapshot?.access == .locked {
                MessagePage(symbol: "lock.fill", tint: WatchColors.purple, title: store.t("watch.locked.title"), message: store.t("watch.locked.body"))
            } else if let session = store.session {
                TabView(selection: $page) {
                    WorkoutPage(store: store, session: session).tag(0)
                    ExercisesPage(store: store, session: session) { page = 0 }.tag(1)
                }
                .tabViewStyle(.verticalPage)
            } else {
                MessagePage(symbol: "iphone", title: store.t("watch.waiting.title"), message: store.t("watch.waiting.body"))
            }
        }
        .tint(WatchColors.accent)
    }
}

/// The rest while one runs, otherwise the open set of the current exercise.
struct WorkoutPage: View {
    @ObservedObject var store: WatchStore
    let session: WatchSnapshot.Session

    var body: some View {
        if let rest = session.rest {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = rest.secondsRemaining(now: WatchSync.nowMillis(context.date))
                if remaining > 0 {
                    RestPage(store: store, rest: rest, remaining: remaining)
                } else {
                    setPage
                }
            }
        } else {
            setPage
        }
    }

    @ViewBuilder private var setPage: some View {
        if session.exercises.indices.contains(session.currentIndex) {
            SetPage(store: store, session: session, exercise: session.exercises[session.currentIndex])
        }
    }
}

struct MessagePage: View {
    let symbol: String
    var tint: Color = WatchColors.secondaryText
    let title: String?
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                if let title {
                    Text(title).font(.headline).foregroundStyle(WatchColors.text)
                }
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(WatchColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }
}

/// The live heart rate while a Health workout records. Neutral text color: red and coral mean warning or media.
struct HeartRateLabel: View {
    @ObservedObject private var recorder = WorkoutRecorder.shared
    let store: WatchStore

    var body: some View {
        if let bpm = recorder.heartRate {
            HStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                Text("\(bpm)").monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(WatchColors.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.t("watch.heartRate", ["bpm": bpm]))
        }
    }
}
