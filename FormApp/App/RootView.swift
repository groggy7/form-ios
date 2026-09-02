import SwiftUI

public struct RootView: View {
    @StateObject private var store = AppStore.shared
    @StateObject private var langManager = LanguageManager.shared

    @State private var showProgramsSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var selectedExerciseForDetail: Exercise? = nil
    @State private var selectedRecordForDetail: WorkoutSessionRecord? = nil

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.background.ignoresSafeArea()

            // Tab content
            Group {
                switch store.currentView {
                case .today:
                    TodayView(
                        store: store,
                        onOpenPrograms: { showProgramsSheet = true },
                        onOpenSettings: { showSettingsSheet = true },
                        onSelectExercise: { selectedExerciseForDetail = $0 }
                    )
                case .plan:
                    WeeklyPlanView(
                        store: store,
                        onOpenPrograms: { showProgramsSheet = true },
                        onOpenSettings: { showSettingsSheet = true },
                        onSelectWorkout: { workoutId in
                            store.selectedWorkoutId = workoutId
                            store.currentView = .today
                        }
                    )
                case .library:
                    LibraryView(
                        store: store,
                        onOpenSettings: { showSettingsSheet = true },
                        onSelectExercise: { selectedExerciseForDetail = $0 }
                    )
                case .history:
                    HistoryView(
                        store: store,
                        onOpenSettings: { showSettingsSheet = true },
                        onSelectRecord: { selectedRecordForDetail = $0 }
                    )
                default:
                    TodayView(
                        store: store,
                        onOpenPrograms: { showProgramsSheet = true },
                        onOpenSettings: { showSettingsSheet = true },
                        onSelectExercise: { selectedExerciseForDetail = $0 }
                    )
                }
            }

            // Bottom Navigation Dock
            BottomDock(currentView: $store.currentView)

            // Animated Toast Pill
            ToastOverlay(message: store.noticeMessage)
        }
        .preferredColorScheme(.dark)
        // Fullscreen Active Workout Session
        .fullScreenCover(item: Binding<ActiveSessionDraft?>(
            get: { store.activeSession },
            set: { _ in }
        )) { draft in
            ActiveSessionView(store: store, draft: draft)
        }
        // Sheets
        .sheet(isPresented: $showProgramsSheet) {
            ProgramsView(store: store) {
                showProgramsSheet = false
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(store: store) {
                showSettingsSheet = false
            }
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            ExerciseDetailSheet(exercise: exercise) {
                selectedExerciseForDetail = nil
            }
        }
        .sheet(item: $selectedRecordForDetail) { record in
            WorkoutDetailSheet(record: record) {
                selectedRecordForDetail = nil
            }
        }
    }
}
