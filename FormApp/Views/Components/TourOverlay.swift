import Combine
import SwiftUI
import UIKit

// Guided tours, sample previews and one-time tips (gym/docs/design/app-tour.md). Screens mark
// targets with `tourTarget`, ask for their tour with `tourTrigger`, and each presentation that
// can show a tour (the tabs, Programs, the workout) hosts a `tourOverlay`.

/// Which presentation draws a tour; a sheet or full-screen cover has its own targets.
public enum TourHost: Hashable {
    case main, programs, workout

    static func host(for tour: TourId) -> TourHost {
        switch tour {
        case .programs: return .programs
        case .workout, .restTimer: return .workout
        default: return .main
        }
    }
}

/// Target flags that pick a step's wording or start a tip.
public enum TourFlag {
    public static let stripScrolls = "scroll"
    public static let stripStatus = "status"
    public static let heroRest = "rest"
    public static let heroViews = "views"
}

struct TourTargetAnchor {
    let anchor: Anchor<CGRect>
    let cornerRadius: CGFloat
    let flags: Set<String>
    let contentInsets: EdgeInsets
}

struct TourTargetKey: PreferenceKey {
    static var defaultValue: [String: TourTargetAnchor] { [:] }
    static func reduce(value: inout [String: TourTargetAnchor], nextValue: () -> [String: TourTargetAnchor]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct TourFrame: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
    var flags: Set<String>
}

struct TourScrollRequest: Equatable {
    let id: String
    let token: Int
}

@MainActor
public final class TourController: ObservableObject {
    public static let shared = TourController(store: AppStore.shared)

    @Published public private(set) var progress: TourProgress
    /// Set by each host when nothing else (sheet, keyboard, notice, page swipe) needs the screen.
    @Published var idleHosts: Set<TourHost> = []
    @Published public private(set) var activeTour: TourId?
    @Published private(set) var steps: [TourStep] = []
    @Published public private(set) var stepIndex = 0
    /// The step whose target is in view; nil while it is being revealed.
    @Published private(set) var shownStepIndex: Int?
    @Published public private(set) var startedCount = 0
    /// Set when the Premium step's See Premium action ends a sample preview.
    @Published public private(set) var paywallRequest: TourId?
    @Published private(set) var scrollRequest: TourScrollRequest?
    /// Registered targets and their flags per host; rects live in `frames` to avoid redraw storms.
    @Published private(set) var targetFlags: [TourHost: [String: Set<String>]] = [:]

    private var frames: [TourHost: [String: TourFrame]] = [:]
    /// Probes per target, newest last. Swapping a view (a locked teaser for the sharp sample) briefly
    /// registers both, and the outgoing probe can update after the new one appears.
    private var scrollTargets: [String: [TourScrollTarget]] = [:]
    private var origins: [TourHost: CGPoint] = [:]
    var groupViewport: CGRect?
    var groupHighlightBounds: CGRect?
    var bubbleBounds: CGRect?
    private var bounds: [TourHost: CGSize] = [:]
    private var locked = false
    private var movingBack = false
    private var scrollToken = 0
    private let store: AppStore
    private var cancellables = Set<AnyCancellable>()

    init(store: AppStore) {
        self.store = store
        progress = store.tourProgress
        store.$tourProgress.sink { [weak self] in self?.progress = $0 }.store(in: &cancellables)
    }

    public var isActive: Bool { activeTour != nil }
    public func isActive(_ id: TourId) -> Bool { activeTour == id }
    var currentStep: TourStep? { activeTour == nil ? nil : steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    public var currentStepId: String? { currentStep?.id }
    public var isOnPremiumStep: Bool { currentStep?.isPremium == true }

    public func hasTarget(_ id: String) -> Bool { targetFlags.values.contains { $0[id] != nil } }
    public func targetHasFlag(_ id: String, _ flag: String) -> Bool {
        targetFlags.values.contains { $0[id]?.contains(flag) == true }
    }

    func isIdle(_ host: TourHost) -> Bool { idleHosts.contains(host) }

    func setIdle(_ idle: Bool, host: TourHost) {
        if idle { idleHosts.insert(host) } else { idleHosts.remove(host) }
    }

    func start(_ id: TourId, locked: Bool = false) {
        guard activeTour == nil else { return }
        let known = targetFlags[TourHost.host(for: id)] ?? [:]
        // Steps whose target is absent (an empty list, a rest day) never show; sample previews
        // compose some targets only when their step switches the view.
        let available = TourCatalog.steps(id, locked: locked).filter {
            id.kind == .preview || $0.targetId == nil || known[$0.targetId!] != nil
        }
        guard !available.isEmpty else { return }
        self.locked = locked
        steps = available
        stepIndex = 0
        shownStepIndex = nil
        movingBack = false
        activeTour = id
        startedCount += 1
    }

    func next() {
        guard activeTour != nil else { return }
        if stepIndex >= steps.count - 1 { return finish() }
        resetGroupViewport()
        movingBack = false
        shownStepIndex = nil
        stepIndex += 1
    }

    func back() {
        guard activeTour != nil, stepIndex > 0 else { return }
        resetGroupViewport()
        movingBack = true
        shownStepIndex = nil
        stepIndex -= 1
    }

    func finish() { end(skipped: false) }
    func skip() { end(skipped: true) }

    /// Ends the current tour without saving it, so it starts again when next due.
    func cancel() {
        resetGroupViewport()
        activeTour = nil
        steps = []
        stepIndex = 0
        shownStepIndex = nil
    }

    func requestPremium() {
        guard let id = activeTour else { return }
        finish()
        paywallRequest = id
    }

    public func consumePaywallRequest() { paywallRequest = nil }

    private func end(skipped: Bool) {
        guard let id = activeTour else { return }
        resetGroupViewport()
        activeTour = nil
        steps = []
        stepIndex = 0
        shownStepIndex = nil
        let transform: (TourProgress) -> TourProgress = { skipped ? $0.skipped(id) : $0.finished(id) }
        // Update locally too, so no trigger sees the tour as due before the saved value returns.
        progress = transform(progress)
        store.updateTourProgress(transform)
    }

    func update(frames newFrames: [String: TourFrame], bounds size: CGSize, origin: CGPoint, host: TourHost) {
        origins[host] = origin
        frames[host] = newFrames
        bounds[host] = size
        let flags = newFrames.mapValues(\.flags)
        if targetFlags[host] != flags { targetFlags[host] = flags }
    }

    func frame(_ id: String?, host: TourHost) -> TourFrame? {
        guard let id else { return nil }
        return frames[host]?[id]
    }

    /// Scrolls the current step's target into view, or drops the step if it cannot be shown.
    func revealCurrentStep(host: TourHost, bubbleHeight: CGFloat) async {
        guard let step = currentStep else { return }
        guard let targetId = step.targetId else {
            shownStepIndex = stepIndex
            return
        }
        // A step may first switch the view (Rep Lab) or swap the blurred teaser for sharp content.
        // The new copy reports its frame before its probe joins the window, so wait for both.
        var waited = 0
        while (frames[host]?[targetId] == nil || scrollTarget(targetId) == nil) && waited < 12 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waited += 1
        }
        guard currentStep?.id == step.id else { return }
        if isOffscreen(targetId, host: host) {
            scrollToken += 1
            scrollRequest = TourScrollRequest(id: targetId, token: scrollToken)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard currentStep?.id == step.id else { return }
        }
        if let frame = frames[host]?[targetId], let scroll = scrollTarget(targetId) {
            let safe = TourOverlay.safeRect(size: bounds[host] ?? .zero)
            let viewport = scrollViewport(targetId, host: host).intersection(safe)
            let desiredTop = max(viewport.minY + 6, safe.minY + bubbleHeight + 18)
            let first = step.highlightsRows ? groupRows(targetId, host: host).first?.1 : frame
            if let first, step.highlightsRows || first.rect.height <= viewport.maxY - 6 - desiredTop {
                scroll.scroll(by: first.rect.minY - desiredTop)
                try? await Task.sleep(nanoseconds: 80_000_000)
                if step.highlightsRows, let placed = groupRows(targetId, host: host).first?.1,
                   abs(placed.rect.minY - desiredTop) > 1 {
                    // Native scrolling can settle after the anchors used by the first pass.
                    scroll.scroll(by: placed.rect.minY - desiredTop)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                if !step.highlightsRows, let placed = frames[host]?[targetId], placed.rect.minY < desiredTop - 1 {
                    scroll.scroll(by: placed.rect.minY - viewport.minY - 6)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        }
        guard !Task.isCancelled, currentStep?.id == step.id else { return }
        if let frame = frames[host]?[targetId], visibleRect(frame.rect, host: host).height > 1 {
            shownStepIndex = stepIndex
            return
        }
        var remaining = steps
        remaining.remove(at: stepIndex)
        if remaining.isEmpty { return finish() }
        if movingBack && stepIndex > 0 {
            stepIndex -= 1
        } else if stepIndex > remaining.count - 1 {
            steps = remaining
            return finish()
        }
        steps = remaining
    }

    private func resetGroupViewport() { groupViewport = nil; groupHighlightBounds = nil }

    func attachScrollTarget(_ id: String, view: UIView) {
        var targets = scrollTargets[id] ?? []
        guard targets.last?.view !== view else { return }
        targets.removeAll { $0.view == nil || $0.view === view }
        targets.append(TourScrollTarget(view: view))
        scrollTargets[id] = targets
    }

    func detachScrollTarget(_ id: String, view: UIView) {
        guard var targets = scrollTargets[id] else { return }
        targets.removeAll { $0.view == nil || $0.view === view }
        scrollTargets[id] = targets.isEmpty ? nil : targets
    }

    /// The newest probe still on screen, so removing an outgoing copy never drops the live one.
    private func scrollTarget(_ id: String) -> TourScrollTarget? {
        scrollTargets[id]?.last { $0.view?.window != nil }
    }

    /// The scroll view that moves `id`, if it has one.
    func scrollView(for id: String) -> UIScrollView? { scrollTarget(id)?.scrollView }

    func scrollViewport(_ id: String, host: TourHost) -> CGRect {
        guard let scroll = scrollView(for: id) else {
            return TourOverlay.safeRect(size: bounds[host] ?? .zero)
        }
        let rect = scroll.convert(scroll.bounds, to: nil)
        let origin = origins[host] ?? .zero
        return rect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    func groupRows(_ id: String, host: TourHost) -> [(String, TourFrame)] {
        (frames[host] ?? [:]).filter { $0.key.hasPrefix("\(id).row.") }
            .sorted { (Int($0.key.components(separatedBy: ".").last ?? "") ?? 0)
                < (Int($1.key.components(separatedBy: ".").last ?? "") ?? 0) }
            .map { ($0.key, $0.value) }
    }


    private func isOffscreen(_ id: String, host: TourHost) -> Bool {
        guard let frame = frames[host]?[id] else { return true }
        let visible = visibleRect(frame.rect, host: host)
        return visible.height < min(frame.rect.height, 120) * 0.9
    }

    private func visibleRect(_ rect: CGRect, host: TourHost) -> CGRect {
        guard let size = bounds[host] else { return rect }
        let insets = TourOverlay.windowSafeInsets
        let screen = CGRect(x: 0, y: insets.top, width: size.width, height: max(0, size.height - insets.top - insets.bottom))
        return rect.intersection(screen)
    }
}

extension View {
    /// Registers this view as a tour target. Flags let a step choose its wording, such as a day
    /// strip that scrolls or a workout card showing a rest day.
    func tourTarget(_ id: String, cornerRadius: CGFloat = 16, flags: Set<String> = [],
                    contentInsets: EdgeInsets = EdgeInsets()) -> some View {
        self
            .background(TourScrollProbe(id: id))
            .id(id)
            .transformAnchorPreference(key: TourTargetKey.self, value: .bounds) { anchors, anchor in
                anchors[id] = TourTargetAnchor(anchor: anchor, cornerRadius: cornerRadius,
                    flags: flags, contentInsets: contentInsets)
            }
    }

    /// Registers a target only when `id` is set, such as the first row of a list.
    @ViewBuilder
    func tourTargetIf(_ id: String?, cornerRadius: CGFloat = 16, contentInsets: EdgeInsets = EdgeInsets()) -> some View {
        if let id { tourTarget(id, cornerRadius: cornerRadius, contentInsets: contentInsets) } else { self }
    }

    /// Starts `id` once `enabled` has held for a moment while its host is idle and the tour is due.
    func tourTrigger(_ id: TourId, enabled: Bool, locked: Bool = false, featureUnlocked: Bool = false) -> some View {
        modifier(TourTriggerModifier(id: id, enabled: enabled, locked: locked, featureUnlocked: featureUnlocked))
    }

    /// Lets the active step scroll this scroll view to its target.
    func tourScrollable(_ proxy: ScrollViewProxy) -> some View {
        modifier(TourScrollModifier(proxy: proxy))
    }

    /// Draws the tours that belong to `host` above this view.
    func tourOverlay(_ host: TourHost) -> some View {
        modifier(TourOverlayModifier(host: host))
    }
}

private struct TourTriggerModifier: ViewModifier {
    @ObservedObject private var tour = TourController.shared
    let id: TourId
    let enabled: Bool
    let locked: Bool
    let featureUnlocked: Bool

    func body(content: Content) -> some View {
        let ready = enabled && tour.isIdle(TourHost.host(for: id)) && !tour.isActive &&
            tour.progress.shouldStart(id, featureUnlocked: featureUnlocked)
        content.task(id: ready) {
            guard ready else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            // Re-check: a view that is not on screen may miss the update that cancels this task.
            guard !Task.isCancelled, tour.isIdle(TourHost.host(for: id)),
                  tour.progress.shouldStart(id, featureUnlocked: featureUnlocked) else { return }
            tour.start(id, locked: locked)
        }
    }
}

private struct TourScrollModifier: ViewModifier {
    @ObservedObject private var tour = TourController.shared
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, tour.currentStep?.highlightsRows == true ? TourOverlay.windowSafeInsets.bottom + 38 : 0,
                            for: .scrollContent)
            .onChange(of: tour.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(request.id, anchor: .center) }
            }
    }
}

private struct TourOverlayModifier: ViewModifier {
    @ObservedObject private var tour = TourController.shared
    let host: TourHost

    func body(content: Content) -> some View {
        let showing = tour.activeTour.map { TourHost.host(for: $0) == host } ?? false
        content
            .accessibilityHidden(showing)
            .overlayPreferenceValue(TourTargetKey.self) { anchors in
                GeometryReader { proxy in
                    let frames = anchors.mapValues {
                        let rect = proxy[$0.anchor]
                        let inset = $0.contentInsets
                        return TourFrame(rect: CGRect(x: rect.minX + inset.leading, y: rect.minY + inset.top,
                            width: max(0, rect.width - inset.leading - inset.trailing),
                            height: max(0, rect.height - inset.top - inset.bottom)),
                            cornerRadius: $0.cornerRadius, flags: $0.flags)
                    }
                    TourOverlay(host: host, frames: frames, size: proxy.size, origin: proxy.frame(in: .global).origin,
                                fold: TwoPageLayout.verticalFold(in: proxy))
                }
                .ignoresSafeArea()
            }
    }
}

struct TourOverlay: View {
    @ObservedObject private var tour = TourController.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var skipSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    let host: TourHost
    let frames: [String: TourFrame]
    let size: CGSize
    let origin: CGPoint
    /// An open foldable's fold in overlay coordinates; the bubble stays on one page.
    var fold: CGRect? = nil
    @State private var naturalBubbleHeight: CGFloat = 0
    @State private var bubbleHeight: CGFloat = 0
    @State private var measuredBubbleStep: String?
    @State private var bubbleOpacity: Double = 0

    static var windowSafeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? .zero
    }

    static func safeRect(size: CGSize) -> CGRect {
        let insets = windowSafeInsets
        // Side insets are zero on portrait iPhones; the iPhone Duo's vertical bar adds one.
        return CGRect(x: insets.left + 16, y: insets.top + 16, width: max(0, size.width - insets.left - insets.right - 32),
            height: max(0, size.height - insets.top - insets.bottom - 32))
    }

    var body: some View {
        let showing = tour.activeTour.map { TourHost.host(for: $0) == host } ?? false
        ZStack(alignment: .topLeading) {
            if showing, let tourId = tour.activeTour, let step = tour.currentStep {
                let shown = tour.shownStepIndex == tour.stepIndex
                let target = frames[step.targetId ?? ""]
                let safe = Self.safeRect(size: size)
                let viewport = tour.scrollViewport(step.targetId ?? "", host: host).intersection(safe)
                let groupArea = CGRect(x: viewport.minX,
                    y: max(viewport.minY + 6, safe.minY + bubbleHeight + 18), width: viewport.width,
                    height: max(0, viewport.maxY - 6 - max(viewport.minY + 6, safe.minY + bubbleHeight + 18)))
                let rows = step.highlightsRows ? tour.groupRows(step.targetId ?? "", host: host).compactMap { frames[$0.0] } : []
                let complete = rows.filter { $0.rect.minY >= groupArea.minY - 1 && $0.rect.maxY <= groupArea.maxY + 1 }
                let groupBounds = complete.reduce(CGRect.null) { $0.union($1.rect) }
                // Safe-area margins constrain the bubble, not the target. The dock extends
                // below them; clipping its bounds there draws the outline through its labels.
                let rect = step.highlightsRows ? (groupBounds.isNull ? nil : groupBounds)
                    : target?.rect.intersection(CGRect(origin: .zero, size: size))
                let cutout = shown ? rect.map { $0.insetBy(dx: -6, dy: -6) } : nil
                let radius = (target?.cornerRadius ?? 0) + 6
                scrim(cutout: cutout, radius: radius)
                if let cutout, !cutout.isNull {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(AppColors.accent.opacity(0.95), lineWidth: 1.5)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .allowsHitTesting(false)
                }
                // Reserve room for the leading rows and one item, or the whole group when it must stay together.
                let required = step.rowHighlight?.keepsAllRows != false ? rows : Array(rows.prefix((step.rowHighlight?.leadingRows ?? 0) + 1))
                let requiredBounds = required.reduce(CGRect.null) { $0.union($1.rect) }
                let minimumRow = requiredBounds.isNull ? 96 : max(48, requiredBounds.height)
                let maxBubbleHeight = step.highlightsRows
                    ? max(48, viewport.maxY - safe.minY - 30 - minimumRow) : safe.height
                ScrollView {
                    bubble(step: step, text: step.text(for: target?.flags ?? []), index: tour.stepIndex,
                           total: tour.steps.count, isTip: tourId.kind == .tip)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TourBubbleHeightKey.self, value: geometry.size.height)
                        })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: bubbleSpan(cutout: cutout).width, height: min(naturalBubbleHeight, maxBubbleHeight))
                .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, rect in
                        tour.bubbleBounds = rect.offsetBy(dx: -origin.x, dy: -origin.y)
                    }
                })
                .onPreferenceChange(TourBubbleHeightKey.self) { height in
                    guard height > 0 else { return }
                    naturalBubbleHeight = height
                    bubbleHeight = min(height, maxBubbleHeight)
                    measuredBubbleStep = step.id
                }
                .onChange(of: maxBubbleHeight) { _, height in bubbleHeight = min(naturalBubbleHeight, height) }
                .offset(x: bubbleSpan(cutout: cutout).x,
                    y: step.highlightsRows ? safe.minY : bubbleY(cutout: cutout))
                .opacity(shown ? bubbleOpacity : 0)
                .allowsHitTesting(shown)
                .id(step.id)
                .onAppear {
                    bubbleOpacity = 0
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { bubbleOpacity = 1 }
                }
                .onChange(of: groupArea, initial: true) { _, rect in
                    if step.highlightsRows { tour.groupViewport = rect }
                }
                .onChange(of: step.id, initial: true) { _, _ in
                    if step.highlightsRows { tour.groupViewport = groupArea }
                }
                .onChange(of: groupBounds, initial: true) { _, rect in
                    tour.groupHighlightBounds = rect.isNull ? nil : rect
                }
                .onChange(of: shown) { _, visible in
                    if visible { UIAccessibility.post(notification: .screenChanged, argument: LanguageManager.t(step.text(for: target?.flags ?? []).titleKey)) }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { tour.update(frames: frames, bounds: size, origin: origin, host: host) }
        .onChange(of: frames) { _, newFrames in tour.update(frames: newFrames, bounds: size, origin: origin, host: host) }
        .onChange(of: size) { _, newSize in tour.update(frames: frames, bounds: newSize, origin: origin, host: host) }
        .task(id: revealKey(showing: showing)) {
            guard showing, bubbleHeight > 0, measuredBubbleStep == tour.currentStep?.id else { return }
            await tour.revealCurrentStep(host: host, bubbleHeight: bubbleHeight)
        }
    }

    private func revealKey(showing: Bool) -> String {
        guard showing, let id = tour.activeTour else { return "idle" }
        // Scrolling can change anchor arithmetic below one pixel. Revealing again
        // for that noise would snap a long section back to its first row.
        let heightInPixels = (bubbleHeight * displayScale).rounded()
        return "\(id.rawValue)-\(tour.stepIndex)-\(tour.steps.map(\.id).joined(separator: ","))-\(measuredBubbleStep ?? "")-\(heightInPixels)-\(size)"
    }

    /// The bubble's width and leading edge: centered between the side safe areas and, beside a fold,
    /// on the page holding the target.
    private func bubbleSpan(cutout: CGRect?) -> (x: CGFloat, width: CGFloat) {
        let insets = Self.windowSafeInsets
        var lower = insets.left
        var upper = size.width - insets.right
        if let fold {
            if let cutout, cutout.midX > fold.midX { lower = max(lower, fold.maxX) } else { upper = min(upper, fold.minX) }
        }
        let width = min(upper - lower - 32, 420)
        return (lower + (upper - lower - width) / 2, width)
    }

    private func bubbleY(cutout: CGRect?) -> CGFloat {
        let insets = Self.windowSafeInsets
        let top = insets.top + 16
        let bottom = size.height - insets.bottom - 16
        guard let cutout else { return max(top, (size.height - bubbleHeight) / 2) }
        if cutout.maxY + 12 + bubbleHeight <= bottom { return cutout.maxY + 12 }
        if cutout.minY - 12 - bubbleHeight >= top { return cutout.minY - 12 - bubbleHeight }
        return cutout.midY > size.height / 2 ? top : bottom - bubbleHeight
    }

    @ViewBuilder
    private func scrim(cutout: CGRect?, radius: CGFloat) -> some View {
        let color = themeManager.currentTheme.isDark
            ? AppColors.background.opacity(0.72)
            : Color(red: 0x14 / 255, green: 0x17 / 255, blue: 0x1A / 255).opacity(0.55)
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let cutout {
                path.addRoundedRect(in: cutout, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
            }
        }
        .fill(color, style: FillStyle(eoFill: true))
        // The scrim takes every touch outside the bubble, so nothing behind it reacts.
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
        .accessibilityHidden(true)
    }

    private func bubble(step: TourStep, text: TourText, index: Int, total: Int, isTip: Bool) -> some View {
        let title = LanguageManager.t(text.titleKey)
        let body = LanguageManager.t(text.bodyKey, text.args.mapValues { LanguageManager.t($0) })
        let isLast = index >= total - 1
        return VStack(alignment: .leading, spacing: 8) {
            if !isTip {
                HStack {
                    Text(LanguageManager.t("tour.stepCount", ["current": "\(index + 1)", "total": "\(total)"]))
                        .font(.app(size: captionSize, weight: .medium))
                        .foregroundStyle(AppColors.muted)
                    Spacer()
                    if !step.isPremium {
                        Button(LanguageManager.t("tour.skip")) { tour.skip() }
                            .font(.app(size: skipSize))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(minHeight: 48)
                            .accessibilityIdentifier("tour-skip")
                    }
                }
            }
            Text(title)
                .font(.app(size: titleSize, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.app(size: bodySize))
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if step.id == "home.days" { HomeDayTourLegend() }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                if step.isPremium {
                    TourButton(LanguageManager.t("tour.seePremium"), primary: false, id: "tour-see-premium") { tour.requestPremium() }
                    TourButton(LanguageManager.t("tour.done"), primary: true, id: "tour-next") { tour.next() }
                } else if isTip {
                    TourButton(LanguageManager.t("tour.ok"), primary: true, id: "tour-next") { tour.next() }
                } else {
                    if index > 0 {
                        TourButton(LanguageManager.t("tour.back"), primary: false, id: "tour-back") { tour.back() }
                    }
                    TourButton(LanguageManager.t(isLast ? "tour.done" : "tour.next"), primary: true, id: "tour-next") { tour.next() }
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("tour-bubble")
    }

}

struct HomeDayTourLegend: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var daySize: CGFloat = 11
    @ScaledMetric(relativeTo: .title3) private var numberSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .subheadline) private var descriptionSize: CGFloat = 13

    var body: some View {
        let glass = AppColors.homeDayGlassColors
        let isDark = themeManager.currentTheme.isDark
        VStack(alignment: .leading, spacing: 10) {
            Text(LanguageManager.t("tour.home.days.examples"))
                .font(.app(size: captionSize)).foregroundStyle(AppColors.muted)
                .padding(.bottom, 2)
            ForEach(HomeDayTourExample.allCases, id: \.self) { example in
                HStack(spacing: 10) {
                    VStack(spacing: 2) {
                        Text(LanguageManager.dayLabels[example.dayIndex])
                            .font(.app(size: daySize, weight: .semibold)).tracking(0.4)
                        Text("\(example.number)")
                            .font(.app(size: numberSize, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.text)
                    .padding(.horizontal, 5).padding(.vertical, 7)
                    .frame(width: 62).frame(minHeight: 55)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(AppColors.background)
                            HomeDayCalmSurface(glass: glass, statusTint: tint(example, glass), isDark: isDark,
                                selected: false, today: false, accent: AppColors.accent, cornerRadius: 12)
                                .padding(-14)
                        }
                    }
                    .accessibilityHidden(true)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18)).foregroundStyle(AppColors.muted)
                        .frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LanguageManager.t(example.titleKey))
                            .font(.app(size: titleSize, weight: .semibold)).foregroundStyle(AppColors.text)
                        Text(LanguageManager.t(example.bodyKey))
                            .font(.app(size: descriptionSize)).foregroundStyle(AppColors.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 64)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("tour-day-\(example.rawValue)")
            }
        }
        .padding(.top, 12)
        .accessibilityIdentifier("tour-day-legend")
    }

    private func tint(_ example: HomeDayTourExample, _ glass: AppColors.HomeDayGlassColors) -> Color? {
        switch example {
        case .done: return glass.completedLight
        case .unfinished: return glass.unfinishedLight
        case .missed: return glass.missedLight
        case .upcoming: return nil
        }
    }
}

private struct TourBubbleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TourButton: View {
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 15
    let title: String
    let primary: Bool
    let id: String
    let action: () -> Void

    init(_ title: String, primary: Bool, id: String, action: @escaping () -> Void) {
        self.title = title
        self.primary = primary
        self.id = id
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.app(size: fontSize, weight: primary ? .semibold : .medium))
                .foregroundStyle(primary ? AppColors.background : AppColors.text)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(primary ? AppColors.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if !primary { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Marks sample analytics during their one-time tour, in the compact chip language of the Pro badge.
struct SampleDataLabel: View {
    var body: some View {
        Text(LanguageManager.t("tour.sampleData"))
            .font(.app(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .accessibilityIdentifier("pro-sample-data-label")
    }
}

@MainActor
private final class TourScrollTarget {
    weak var view: UIView?
    init(view: UIView) { self.view = view }
    var scrollView: UIScrollView? {
        var parent = view?.superview
        while let current = parent {
            if let scroll = current as? UIScrollView,
               scroll.contentSize.height > scroll.bounds.height + 1 || scroll.alwaysBounceVertical {
                return scroll
            }
            parent = current.superview
        }
        return nil
    }
    func scroll(by delta: CGFloat) {
        guard let scroll = scrollView else { return }
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
            y: min(maximum, max(minimum, scroll.contentOffset.y + delta))), animated: false)
        scroll.layoutIfNeeded()
    }
}

private struct TourScrollProbe: UIViewRepresentable {
    let id: String
    final class Coordinator {
        let id: String
        init(id: String) { self.id = id }
    }
    func makeCoordinator() -> Coordinator { Coordinator(id: id) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        TourController.shared.attachScrollTarget(id, view: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        TourController.shared.attachScrollTarget(id, view: uiView)
    }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        TourController.shared.detachScrollTarget(coordinator.id, view: uiView)
    }
}
