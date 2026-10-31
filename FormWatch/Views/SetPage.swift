import SwiftUI
import WatchKit

/// The open set of one exercise: the crown edits the selected load or reps, Done logs it on the iPhone.
struct SetPage: View {
    @ObservedObject var store: WatchStore
    let session: WatchSnapshot.Session
    let exercise: WatchSnapshot.Exercise

    @State private var baseLoad: Double = 0
    /// Crown steps from `baseLoad`, so the load moves by whole steps without snapping to a grid.
    @State private var loadSteps: Double = 0
    @State private var reps: Double = 0
    @State private var initialReps: Double = 0
    @State private var editingSetId: String?
    @FocusState private var focus: Field?
    private enum Field { case load, reps }

    private var open: WatchSnapshot.SetRow? { exercise.sets.first { !$0.isCompleted } }
    private var maxLoad: Double { session.unit == "lbs" ? 3000 : 1500 }
    private var load: Double { min(maxLoad, max(0, baseLoad + loadSteps * exercise.loadStep)) }
    private var touched: Bool { loadSteps != 0 || reps != initialReps }
    private var canComplete: Bool { (load > 0 || exercise.allowsZeroLoad) && reps >= 1 }
    private var title: String { [exercise.label, exercise.name].compactMap { $0 }.joined(separator: " · ") }

    var body: some View {
        Group {
            if let open {
                editor(open)
            } else {
                finished
            }
        }
        .onAppear { reset(force: true) }
        .onChange(of: open) { _, _ in reset(force: false) }
        .toolbar {
            if let last = exercise.sets.last(where: \.isCompleted) {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        store.send(.undoSet, exercise: exercise.id, set: last.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(WatchColors.text)
                    }
                    // A quiet secondary action; the app-wide accent tint would hide the glyph in its own fill.
                    .tint(WatchColors.surfaceRaised)
                    .accessibilityLabel(store.t("watch.undo", ["number": last.number]))
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

    private func editor(_ set: WatchSnapshot.SetRow) -> some View {
        let workingCount = exercise.sets.filter { !$0.isWarmup }.count
        return VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(WatchColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack {
                    Text(set.isWarmup ? store.t("watch.warmup") : store.t("watch.set", ["number": set.number, "count": workingCount]))
                        .font(.caption2)
                        .foregroundStyle(WatchColors.purple)
                    Spacer(minLength: 4)
                    HeartRateLabel(store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                tile(.load, value: WatchStrings.load(load, language: store.language), caption: loadCaption)
                    .digitalCrownRotation($loadSteps, from: -(baseLoad / exercise.loadStep).rounded(.down),
                                          through: ((maxLoad - baseLoad) / exercise.loadStep).rounded(.down), by: 1,
                                          sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                tile(.reps, value: "\(Int(reps))", caption: store.t("watch.reps"))
                    .digitalCrownRotation($reps, from: 0, through: 999, by: 1,
                                          sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            }

            if set.hasParts {
                Text(store.t("watch.parts"))
                    .font(.system(size: 11))
                    .foregroundStyle(WatchColors.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Button {
                WKInterfaceDevice.current().play(.success)
                store.send(.completeSet, exercise: exercise.id, set: set.id, load: load, reps: Int(reps))
            } label: {
                Text(store.t("watch.done"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(WatchColors.background)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canComplete ? WatchColors.accent : WatchColors.muted.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canComplete)
        }
    }

    private var loadCaption: String {
        let unit = session.unit == "lbs" ? "lbs" : "kg"
        if exercise.isAssisted { return "\(unit) \(store.t("watch.assistance"))" }
        if exercise.isBodyweight { return "\(unit) \(store.t("watch.added"))" }
        return unit
    }

    private func tile(_ field: Field, value: String, caption: String) -> some View {
        let selected = focus == field
        return VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WatchColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(WatchColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? WatchColors.surfaceRaised : WatchColors.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(selected ? WatchColors.accent : WatchColors.border, lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .focusable(true)
        .focusEffectDisabled()
        .focused($focus, equals: field)
        .onTapGesture { focus = field }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Every set of this exercise is logged: offer the iPhone's next exercise, or say the workout is ready to save.
    private var finished: some View {
        let next = session.nextIndex.flatMap { session.exercises.indices.contains($0) ? session.exercises[$0] : nil }
        return ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(WatchColors.accent)
                    .accessibilityHidden(true)
                Text(store.t(session.allLogged ? "watch.allLogged.title" : "watch.exercise.done"))
                    .font(.headline)
                    .foregroundStyle(WatchColors.text)
                    .multilineTextAlignment(.center)
                if session.allLogged {
                    Text(store.t("watch.allLogged.body"))
                        .font(.footnote)
                        .foregroundStyle(WatchColors.secondaryText)
                        .multilineTextAlignment(.center)
                } else if let next {
                    Button {
                        WKInterfaceDevice.current().play(.click)
                        store.send(.selectExercise, exercise: next.id)
                    } label: {
                        VStack(spacing: 2) {
                            Text(store.t("watch.next")).font(.system(.footnote, weight: .semibold)).foregroundStyle(WatchColors.background)
                            Text([next.label, next.name].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(WatchColors.background.opacity(0.8))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WatchColors.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Starts the editor from the set's own values, else the previous set's, as the iPhone prefills.
    /// A set the user is already adjusting keeps the crown values when an unrelated snapshot arrives.
    private func reset(force: Bool) {
        guard let preview = exercise.openSet else { editingSetId = nil; return }
        let open = preview.set
        guard force || open.id != editingSetId || !touched else { return }
        baseLoad = preview.load ?? 0
        loadSteps = 0
        reps = Double(preview.reps ?? 0)
        initialReps = reps
        editingSetId = open.id
        if focus == nil { focus = .load }
    }
}
