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

            VStack(spacing: 0) {
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
                            onOpenToday: { store.currentView = .today },
                            onOpenPrograms: { showProgramsSheet = true },
                            onOpenSettings: { showSettingsSheet = true }
                        )
                    case .library:
                        LibraryView(
                            store: store,
                            onSelectExercise: { selectedExerciseForDetail = $0 },
                            onOpenSettings: { showSettingsSheet = true }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Navigation Dock
                BottomDock(currentView: $store.currentView)
            }

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
