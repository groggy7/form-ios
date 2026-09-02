import SwiftUI

public struct WeekStripView: View {
    @ObservedObject var store: AppStore
    var onSelectWorkout: (String) -> Void

    public init(store: AppStore, onSelectWorkout: @escaping (String) -> Void) {
        self.store = store
        self.onSelectWorkout = onSelectWorkout
    }

    public var body: some View {
        let calendar = store.weekCalendar
        let program = store.activeProgram
        let completed = store.state.completed
        let unfinished = store.unfinishedWorkoutKeys()

        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let dayNumber = calendar.numbers.indices.contains(index) ? calendar.numbers[index] : index + 1
                let dayName = LanguageManager.workoutDays.indices.contains(index)
                    ? String(LanguageManager.workoutDays[index].prefix(3)).uppercased()
                    : ""
                let workout = program?.workouts.first { $0.day == index + 1 }
                let isToday = index == calendar.today
                let isSelected = workout?.id == store.selectedWorkoutId
                let isCompleted = workout.map { "\(program?.id ?? ""):\($0.id)" }.map { completed.contains($0) } ?? false
                let isUnfinished = workout.map { "\(program?.id ?? ""):\($0.id)" }.map { unfinished.contains($0) } ?? false

                Button(action: {
                    if let w = workout {
                        onSelectWorkout(w.id)
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(dayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isToday ? AppColors.accent : (isUnfinished ? AppColors.unfinishedText : AppColors.muted))

                        Text("\(dayNumber)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(isSelected && isToday ? AppColors.todaySelectionText : AppColors.text)

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AppColors.positive)
                        } else if isUnfinished {
                            Circle()
                                .fill(AppColors.unfinishedBorder)
                                .frame(width: 5, height: 5)
                        } else if workout != nil {
                            Circle()
                                .fill(AppColors.muted.opacity(0.4))
                                .frame(width: 4, height: 4)
                        } else {
                            Spacer().frame(height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected && isToday ? AppColors.todayIvory : (isSelected ? AppColors.surfaceRaised : AppColors.surface))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isToday ? AppColors.accent : (isSelected ? AppColors.accent.opacity(0.4) : AppColors.border),
                                        lineWidth: isToday ? 2 : 1
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}
