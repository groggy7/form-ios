import SwiftUI
import UIKit

private struct MainTabScrollPositionKey: PreferenceKey {
    static var defaultValue: CGFloat? { nil }

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

// SwiftUI's scrollDisabled propagates to nested scroll views. Lock only the
// native pager so exercise/history details keep their own scrolling gestures.
private struct MainTabScrollGate: UIViewRepresentable {
    var isEnabled: Bool

    func makeUIView(context: Context) -> GateView {
        let view = GateView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: GateView, context: Context) {
        uiView.isPagingEnabled = isEnabled
        uiView.updatePager()
    }

    static func dismantleUIView(_ uiView: GateView, coordinator: ()) {
        uiView.isPagingEnabled = true
        uiView.updatePager()
    }

    final class GateView: UIView {
        var isPagingEnabled = true

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updatePager()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updatePager()
        }

        func updatePager() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    scrollView.isScrollEnabled = isPagingEnabled
                    return
                }
                ancestor = view.superview
            }
        }
    }
}

public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = AppStore.shared
    @StateObject private var langManager = LanguageManager.shared

    @State private var showProgramsSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var selectedRecordForDetail: WorkoutSessionRecord? = nil
    @State private var dragScrollPosition: CGFloat? = nil
    @State private var scrollSelectedTab: ViewMode?
    @State private var isPagerInitialized = false

    public init() {
        _scrollSelectedTab = State(initialValue: AppStore.shared.currentView)
    }

    public var body: some View {
        Group {
            if !store.isOnboardingCompleted {
                OnboardingView(store: store)
            } else {
                let isBottomDockVisible = (store.currentView != .library || store.selectedExerciseId == nil) && store.selectedHistoryDetailDay == nil

                let mainTabs = AppStore.mainTabs

                ZStack(alignment: .bottom) {
                    AppColors.background.ignoresSafeArea()

                    ScrollViewReader { scrollProxy in
                        VStack(spacing: 0) {
                            GeometryReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 0) {
                                        TodayView(
                                            store: store,
                                            onOpenPrograms: { showProgramsSheet = true },
                                            onOpenSettings: { showSettingsSheet = true },
                                            onSelectExercise: { store.openExercise(id: $0.id) }
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(ViewMode.today)
                                        .accessibilityHidden(store.currentView != .today)

                                        WeeklyPlanView(
                                            store: store,
                                            onOpenToday: { store.navigate(to: .today) },
                                            onOpenPrograms: { showProgramsSheet = true },
                                            onOpenSettings: { showSettingsSheet = true }
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(ViewMode.plan)
                                        .accessibilityHidden(store.currentView != .plan)

                                        LibraryView(
                                            store: store,
                                            onSelectExercise: { store.selectExerciseInLibrary(id: $0.id) },
                                            onOpenSettings: { showSettingsSheet = true }
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(ViewMode.library)
                                        .accessibilityHidden(store.currentView != .library)

                                        HistoryView(
                                            store: store,
                                            onOpenSettings: { showSettingsSheet = true },
                                            onSelectRecord: { selectedRecordForDetail = $0 }
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .id(ViewMode.history)
                                        .accessibilityHidden(store.currentView != .history)
                                    }
                                    .scrollTargetLayout()
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear.preference(
                                                key: MainTabScrollPositionKey.self,
                                                value: proxy.size.width > 0
                                                    ? -geometry.frame(in: .named("mainTabPager")).minX / proxy.size.width
                                                    : nil
                                            )
                                        }
                                    }
                                    .background(MainTabScrollGate(isEnabled: isBottomDockVisible))
                                }
                                .coordinateSpace(name: "mainTabPager")
                                .scrollTargetBehavior(.paging)
                                .onPreferenceChange(MainTabScrollPositionKey.self) { position in
                                    guard let position else { return }
                                    // Scroll targets are measurable after the first layout.
                                    // Restore the selected tab before accepting scroll updates.
                                    if !isPagerInitialized {
                                        isPagerInitialized = true
                                        selectPage(store.currentView, using: scrollProxy)
                                        return
                                    }
                                    let clamped = max(0, min(CGFloat(mainTabs.count - 1), position))
                                    dragScrollPosition = clamped
                                    guard isBottomDockVisible else { return }
                                    let destination = mainTabs[Int(clamped.rounded())]
                                    // Record the scroll origin before publishing navigation.
                                    // Its onChange must not snap an unfinished drag to a page.
                                    scrollSelectedTab = destination
                                    if destination != store.currentView {
                                        if destination == .today {
                                            store.selectedWorkoutId = nil
                                        }
                                        store.navigate(to: destination)
                                    }
                                }
                                .onDisappear { isPagerInitialized = false }
                                .onChange(of: store.currentView) { _, destination in
                                    guard destination != scrollSelectedTab else { return }
                                    selectPage(destination, using: scrollProxy)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                            // Bottom Navigation Dock (hidden when viewing exercise detail or history detail)
                            if isBottomDockVisible {
                                BottomDock(
                                    currentView: Binding(
                                        get: { store.currentView },
                                        set: { destination in
                                            selectPage(destination, using: scrollProxy)
                                            if destination == .today {
                                                store.selectedWorkoutId = nil
                                            }
                                            store.navigate(to: destination)
                                        }
                                    ),
                                    dragPosition: dragScrollPosition
                                )
                            }
                        }
                        .ignoresSafeArea(.container, edges: isBottomDockVisible ? .bottom : [])
                    }

                    // Animated Toast Pill
                    ToastOverlay(item: store.currentToast, bottomPadding: isBottomDockVisible ? 80 : 36)
                }
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
                .sheet(item: $selectedRecordForDetail) { record in
                    WorkoutDetailSheet(record: record, onDismiss: {
                        selectedRecordForDetail = nil
                    }, weightUnit: store.weightUnit)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Restore subscriptions on every app launch, not only when a paywall opens.
            _ = StoreKitSubscriptionManager.shared
            await ExerciseReportStore.shared.retryPendingReports()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshForCurrentDate()
                store.checkAndArchiveStaleSession()
                Task { await ExerciseReportStore.shared.retryPendingReports() }
            }
        }
    }

    private func selectPage(_ destination: ViewMode, using proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollSelectedTab = destination
            proxy.scrollTo(destination, anchor: .leading)
            dragScrollPosition = AppStore.mainTabs.firstIndex(of: destination).map(CGFloat.init)
        }
    }
}
