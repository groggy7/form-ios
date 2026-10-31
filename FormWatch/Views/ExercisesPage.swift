import SwiftUI
import WatchKit

/// Every exercise with its logged working sets; choosing one moves the iPhone's workout to it.
struct ExercisesPage: View {
    @ObservedObject var store: WatchStore
    let session: WatchSnapshot.Session
    let onSelect: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, exercise in
                    row(exercise, isCurrent: index == session.currentIndex)
                }
            } header: {
                Text(store.t("watch.exercises"))
            }
        }
    }

    private func row(_ exercise: WatchSnapshot.Exercise, isCurrent: Bool) -> some View {
        let working = exercise.sets.filter { !$0.isWarmup }
        let done = working.filter(\.isCompleted).count
        return Button {
            if !isCurrent {
                WKInterfaceDevice.current().play(.click)
                store.send(.selectExercise, exercise: exercise.id)
            }
            onSelect()
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text([exercise.label, exercise.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(WatchColors.text)
                        .lineLimit(2)
                    Text("\(done)/\(working.count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(WatchColors.secondaryText)
                }
                Spacer(minLength: 4)
                if !working.isEmpty && done == working.count {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(WatchColors.accent)
                }
            }
        }
        .listRowBackground(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isCurrent ? WatchColors.positiveBg : WatchColors.surface))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
