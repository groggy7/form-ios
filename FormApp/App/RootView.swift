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
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var tour = TourController.shared

    @State private var showProgramsSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var selectedRecordForDetail: WorkoutSessionRecord? = nil
    @State private var dragScrollPosition: CGFloat? = nil
    @State private var scrollSelectedTab: ViewMode?
    @State private var isPagerInitialized = false
    @State private var isKeyboardVisible = false
    @State private var isToastShowing = false
    /// Tours started when the current Home visit began; tips never share a visit with a tour.
    @State private var visitTourCount = 0

    public init() {
        _scrollSelectedTab = State(initialValue: AppStore.shared.currentView)
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        Group {
            if !store.isOnboardingCompleted {
                OnboardingView(store: store)
            } else {
                let isMainNavigationAvailable = (store.currentView != .library || store.selectedExerciseId == nil) && store.selectedHistoryDetailDay == nil
                let isBottomDockVisible = isMainNavigationAvailable && !isKeyboardVisible
                let isPageSwipingEnabled = isMainNavigationAvailable && !isKeyboardVisible

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
                                    .background(MainTabScrollGate(isEnabled: isPageSwipingEnabled && !tour.isActive))
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
                                    guard isPageSwipingEnabled else { return }
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
                        .ignoresSafeArea(.container, edges: isMainNavigationAvailable ? .bottom : [])
                    }

                    // Animated Toast Pill
                    ToastOverlay(item: store.currentToast, bottomPadding: isBottomDockVisible ? 80 : 36)
                }
                .tourOverlay(.main)
                .modifier(MainTourTriggers(store: store, tour: tour, visitTourCount: visitTourCount))
                // Tours start only on a settled screen with nothing else asking for attention (app-tour.md §3).
                .onChange(of: mainTourIdle, initial: true) { _, idle in tour.setIdle(idle, host: .main) }
                .onChange(of: store.currentView) { _, _ in visitTourCount = tour.startedCount }
                .onChange(of: store.currentToast) { _, item in
                    guard let item else { return }
                    isToastShowing = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64((item.duration + 0.4) * 1_000_000_000))
                        if store.currentToast?.id == item.id { isToastShowing = false }
                    }
                }
                // Fullscreen Active Workout Session
                .fullScreenCover(isPresented: $store.isSessionPresented) {
                    if let draft = store.activeSession {
                        ActiveSessionView(store: store, draft: draft)
                    }
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
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .environment(\.locale, LanguageManager.locale)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .task {
            // Restore subscriptions on every app launch, not only when a paywall opens.
            _ = StoreKitSubscriptionManager.shared
            await ExerciseReportStore.shared.retryPendingReports()
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding keeps the workout and its rest deadline running, matching Android.
            if phase == .background {
                store.sceneDidEnterBackground()
                store.flushPendingState()
            } else if phase == .active {
                langManager.refreshDeviceLanguage()
                store.refreshForCurrentDate()
                store.checkAndArchiveStaleSession()
                store.sceneDidBecomeActive()
                Task { await ExerciseReportStore.shared.retryPendingReports() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            store.flushPendingState()
        }
    }

    private var mainTourIdle: Bool {
        let settled = dragScrollPosition.map { abs($0 - $0.rounded()) < 0.01 } ?? true
        return store.isOnboardingCompleted && !showProgramsSheet && !showSettingsSheet && selectedRecordForDetail == nil &&
            !store.isSessionPresented && !isKeyboardVisible && !isToastShowing && settled
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

/// The tab tours and the day-colour tip; each starts on its own screen only.
private struct MainTourTriggers: ViewModifier {
    @ObservedObject var store: AppStore
    @ObservedObject var tour: TourController
    let visitTourCount: Int

    func body(content: Content) -> some View {
        let onTab = store.selectedHistoryDetailDay == nil
        let view = store.currentView
        content
            .tourTrigger(.home, enabled: onTab && view == .today)
            .tourTrigger(.plan, enabled: onTab && view == .plan)
            .tourTrigger(.library, enabled: onTab && view == .library && store.selectedExerciseId == nil)
            .tourTrigger(.exercise, enabled: onTab && view == .library && store.selectedExerciseId != nil)
            .tourTrigger(.progress, enabled: onTab && view == .history)
            .tourTrigger(.dayStatus, enabled: onTab && view == .today && visitTourCount == tour.startedCount &&
                !tour.progress.shouldStart(.home) && tour.targetHasFlag("home.days", TourFlag.stripStatus))
    }
}
