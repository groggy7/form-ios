import SwiftUI
import UIKit
import StoreKit

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
    @Environment(\.requestReview) private var requestReview
    @ObservedObject private var billing = StoreKitSubscriptionManager.shared
    @StateObject private var store = AppStore.shared
    @StateObject private var langManager = LanguageManager.shared
    @State private var presentedSocialShareRequest: SocialShareRequest?
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var tour = TourController.shared

    @State private var showProgramsSheet: Bool = false
    @State private var showSettingsSheet: Bool = false
    @State private var selectedRecordForDetail: WorkoutSessionRecord? = nil
    @State private var dragScrollPosition: CGFloat? = nil
    @State private var scrollSelectedTab: ViewMode?
    @State private var isPagerInitialized = false
    @State private var pagerWidth: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var isToastShowing = false
    @State private var twoPageLayout: TwoPageLayout?
    @State private var sideBarSafeInsets = EdgeInsets()

    public init() {
        _scrollSelectedTab = State(initialValue: AppStore.shared.currentView)
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        Group {
            if !store.isOnboardingCompleted {
                OnboardingView(store: store)
            } else {
                // Two pages show exercise and history details beside their list, so navigation stays available.
                let isMainNavigationAvailable = twoPageLayout != nil
                    || ((store.currentView != .library || store.selectedExerciseId == nil) && store.selectedHistoryDetailDay == nil)
                let isBottomDockVisible = isMainNavigationAvailable && !isKeyboardVisible
                let isPageSwipingEnabled = isMainNavigationAvailable && !isKeyboardVisible

                let mainTabs = AppStore.mainTabs

                // A vertical system bar (iPhone Duo) moves the dock into its side strip.
                VerticalBarEdgeReader { barEdge in
                ZStack(alignment: .bottom) {
                    AppColors.background.ignoresSafeArea()

                    ScrollViewReader { scrollProxy in
                        let dockSelection = Binding(
                            get: { store.currentView },
                            set: { destination in
                                selectPage(destination, using: scrollProxy)
                                if destination == .today {
                                    store.selectedWorkoutId = nil
                                }
                                store.navigate(to: destination)
                            }
                        )
                        // AnyLayout keeps the pager's identity, and its pages' state, when the bar edge changes.
                        let layout = barEdge.map { AnyLayout(SideDockLayout(edge: $0)) } ?? AnyLayout(VStackLayout(spacing: 0))
                        layout {
                            GeometryReader { proxy in
                                let spread = TwoPageLayout.resolve(in: proxy)
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
                                            onOpenSettings: { showSettingsSheet = true },
                                            onSelectExercise: { store.openExercise(id: $0.id) }
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
                                .environment(\.twoPageLayout, spread)
                                .onChange(of: spread, initial: true) { _, value in twoPageLayout = value }
                                .onPreferenceChange(MainTabScrollPositionKey.self) { position in
                                    guard let position else { return }
                                    // Scroll targets are measurable after the first layout.
                                    // Restore the selected tab before accepting scroll updates.
                                    if !isPagerInitialized {
                                        isPagerInitialized = true
                                        pagerWidth = proxy.size.width
                                        selectPage(store.currentView, using: scrollProxy)
                                        return
                                    }
                                    // Folding, unfolding and rotating resize the pages but keep the old offset.
                                    // Snap back to the current tab instead of reading that offset as a swipe.
                                    if proxy.size.width != pagerWidth {
                                        pagerWidth = proxy.size.width
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
                            // Beside a vertical bar the top inset is ~0; restore the header's 20pt headroom.
                            .safeAreaPadding(.top, barEdge == nil ? 0 : max(0, 10 - sideBarSafeInsets.top))

                            if let barEdge {
                                // The strip stays reserved while the dock hides, so pages never slide beneath the status bar.
                                SideDockSlot(
                                    currentView: dockSelection,
                                    dragPosition: dragScrollPosition,
                                    width: barEdge == .leading ? sideBarSafeInsets.leading : sideBarSafeInsets.trailing,
                                    isDockVisible: isBottomDockVisible
                                )
                            } else if isBottomDockVisible {
                                // Bottom Navigation Dock (hidden when viewing exercise detail or history detail)
                                BottomDock(currentView: dockSelection, dragPosition: dragScrollPosition)
                            }
                        }
                        .ignoresSafeArea(.container, edges: barEdge.map { $0 == .leading ? .leading : .trailing }
                            ?? (isMainNavigationAvailable ? .bottom : []))
                        // The fold arrives a few frames after launching or unfolding; show pages and dock only once it has.
                        .holdsUntilFold()
                        .background {
                            if barEdge != nil {
                                GeometryReader { strip in
                                    Color.clear.onChange(of: strip.safeAreaInsets, initial: true) { _, insets in
                                        sideBarSafeInsets = insets
                                    }
                                }
                            }
                        }
                    }

                    // Animated Toast Pill
                    ToastOverlay(item: store.currentToast, bottomPadding: barEdge == nil && isBottomDockVisible ? 80 : 36)
                }
                }
                .tourOverlay(.main)
                .modifier(MainTourTriggers(store: store, tour: tour))
                // Tours start only on a settled screen with nothing else asking for attention (app-tour.md §3).
                .onChange(of: mainTourIdle, initial: true) { _, idle in tour.setIdle(idle, host: .main) }
                .onChange(of: store.currentToast) { _, item in
                    guard let item else { return }
                    isToastShowing = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64((item.duration + 0.4) * 1_000_000_000))
                        if store.currentToast?.id == item.id { isToastShowing = false }
                    }
                }
                // Fullscreen Active Workout Session
                .fullScreenCover(isPresented: $store.isSessionPresented, onDismiss: {
                    // Wait for the workout cover to finish dismissing before presenting its saved sheet.
                    presentedSocialShareRequest = store.socialShareRequest
                }) {
                    if let draft = store.activeSession {
                        ActiveSessionView(store: store, draft: draft)
                    }
                }
                // Sheets
                .sheet(item: $presentedSocialShareRequest, onDismiss: { store.socialShareRequest = nil }) { request in
                    SocialCardComposer(request: request) { presentedSocialShareRequest = nil; store.socialShareRequest = nil }
                }
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
        .tracksDeviceHinge()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            // Rotating an open foldable announces a zero-height keyboard with no matching hide.
            isKeyboardVisible = !FoldState.shared.hasHinge || Self.keyboardCoversScreen(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .task {
            // Restore subscriptions on every app launch, not only when a paywall opens.
            _ = StoreKitSubscriptionManager.shared
            await ExerciseReportStore.shared.retryPendingReports()
        }
        .task(id: reviewReady) {
            guard reviewReady else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // UIKit can still be dismissing an untracked child sheet after SwiftUI clears its flag.
            while !Task.isCancelled && reviewReady {
                if ReviewPromptPresentation.hostIsIdle(), store.consumeReviewPrompt(allowed: reviewReady) {
                    ReviewPromptPresentation.request { requestReview() }
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onOpenURL { url in
            if url.scheme == "forcedrep", url.host == "workout", store.activeSession != nil {
                store.resumeActiveSession()
            }
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
                Task { await HealthWeights.shared.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            store.flushPendingState()
        }
    }

    private var reviewReady: Bool {
        ReviewPromptPresentation.nativeRequestsEnabled && scenePhase == .active && mainTourIdle && !tour.isActive && !billing.isPurchasing &&
            store.selectedExerciseId == nil && store.selectedHistoryDetailDay == nil &&
            store.reviewPromptState.canAttempt(now: Int64(Date().timeIntervalSince1970 * 1000))
    }

    private var mainTourIdle: Bool {
        let settled = dragScrollPosition.map { abs($0 - $0.rounded()) < 0.01 } ?? true
        return store.isOnboardingCompleted && !showProgramsSheet && !showSettingsSheet && selectedRecordForDetail == nil &&
            !store.isSessionPresented && store.socialShareRequest == nil && presentedSocialShareRequest == nil && !isKeyboardVisible && !isToastShowing && settled
    }

    private static func keyboardCoversScreen(_ note: Notification) -> Bool {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return true }
        guard let screen = note.object as? UIScreen else { return frame.height > 0 }
        return frame.intersection(screen.bounds).height > 0
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

/// Each tab tour starts on its own screen; Home includes its day-color explanation.
private struct MainTourTriggers: ViewModifier {
    @ObservedObject var store: AppStore
    @ObservedObject var tour: TourController

    func body(content: Content) -> some View {
        let onTab = store.selectedHistoryDetailDay == nil
        let view = store.currentView
        content
            .tourTrigger(.home, enabled: onTab && view == .today)
            .tourTrigger(.plan, enabled: onTab && view == .plan)
            .tourTrigger(.library, enabled: onTab && view == .library && store.selectedExerciseId == nil)
            .tourTrigger(.exercise, enabled: onTab && view == .library && store.selectedExerciseId != nil)
            .tourTrigger(.progress, enabled: onTab && view == .history)
    }
}
