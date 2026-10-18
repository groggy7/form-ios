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
        movingBack = false
        shownStepIndex = nil
        stepIndex += 1
    }

    func back() {
        guard activeTour != nil, stepIndex > 0 else { return }
        movingBack = true
        shownStepIndex = nil
        stepIndex -= 1
    }

    func finish() { end(skipped: false) }
    func skip() { end(skipped: true) }

    /// Ends the current tour without saving it, so it starts again when next due.
    func cancel() {
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
        activeTour = nil
        steps = []
        stepIndex = 0
        shownStepIndex = nil
        let transform: (TourProgress) -> TourProgress = { skipped ? $0.skipped(id) : $0.finished(id) }
        // Update locally too, so no trigger sees the tour as due before the saved value returns.
        progress = transform(progress)
        store.updateTourProgress(transform)
    }

    func update(frames newFrames: [String: TourFrame], bounds size: CGSize, host: TourHost) {
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
    func revealCurrentStep(host: TourHost) async {
        guard let step = currentStep else { return }
        guard let targetId = step.targetId else {
            shownStepIndex = stepIndex
            return
        }
        // A step may first switch the view (Rep Lab) or swap the blurred teaser for sharp content.
        var waited = 0
        while frames[host]?[targetId] == nil && waited < 12 {
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
    func tourTarget(_ id: String, cornerRadius: CGFloat = 16, flags: Set<String> = []) -> some View {
        self
            .id(id)
            .anchorPreference(key: TourTargetKey.self, value: .bounds) {
                [id: TourTargetAnchor(anchor: $0, cornerRadius: cornerRadius, flags: flags)]
            }
    }

    /// Registers a target only when `id` is set, such as the first row of a list.
    @ViewBuilder
    func tourTargetIf(_ id: String?, cornerRadius: CGFloat = 16) -> some View {
        if let id { tourTarget(id, cornerRadius: cornerRadius) } else { self }
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
        content.onChange(of: tour.scrollRequest) { _, request in
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
                        TourFrame(rect: proxy[$0.anchor], cornerRadius: $0.cornerRadius, flags: $0.flags)
                    }
                    TourOverlay(host: host, frames: frames, size: proxy.size)
                }
                .ignoresSafeArea()
            }
    }
}

struct TourOverlay: View {
    @ObservedObject private var tour = TourController.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let host: TourHost
    let frames: [String: TourFrame]
    let size: CGSize
    @State private var bubbleHeight: CGFloat = 0
    @State private var bubbleOpacity: Double = 0

    static var windowSafeInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets ?? .zero
    }

    var body: some View {
        let showing = tour.activeTour.map { TourHost.host(for: $0) == host } ?? false
        ZStack(alignment: .topLeading) {
            if showing, let tourId = tour.activeTour {
                let shownIndex = tour.shownStepIndex
                let step = shownIndex.flatMap { tour.steps.indices.contains($0) ? tour.steps[$0] : nil }
                let target = step.flatMap { tour.frame($0.targetId, host: host) }
                let cutout = target.map { $0.rect.insetBy(dx: -6, dy: -6) }
                let radius = (target?.cornerRadius ?? 0) + 6
                scrim(cutout: cutout, radius: radius)
                if let cutout {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(AppColors.accent.opacity(0.95), lineWidth: 1.5)
                        .frame(width: cutout.width, height: cutout.height)
                        .position(x: cutout.midX, y: cutout.midY)
                        .allowsHitTesting(false)
                }
                if let step, let shownIndex {
                    bubble(step: step, text: step.text(for: target?.flags ?? []), index: shownIndex,
                           total: tour.steps.count, isTip: tourId.kind == .tip)
                        .frame(width: bubbleWidth)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TourBubbleHeightKey.self, value: geometry.size.height)
                        })
                        .onPreferenceChange(TourBubbleHeightKey.self) { bubbleHeight = $0 }
                        .offset(x: (size.width - bubbleWidth) / 2, y: bubbleY(cutout: cutout))
                        .opacity(bubbleOpacity)
                        .id(step.id)
                        .onAppear {
                            bubbleOpacity = 0
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { bubbleOpacity = 1 }
                            let title = LanguageManager.t(step.text(for: target?.flags ?? []).titleKey)
                            UIAccessibility.post(notification: .screenChanged, argument: title)
                        }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { tour.update(frames: frames, bounds: size, host: host) }
        .onChange(of: frames) { _, newFrames in tour.update(frames: newFrames, bounds: size, host: host) }
        .onChange(of: size) { _, newSize in tour.update(frames: frames, bounds: newSize, host: host) }
        .task(id: revealKey(showing: showing)) {
            guard showing else { return }
            await tour.revealCurrentStep(host: host)
        }
    }

    private func revealKey(showing: Bool) -> String {
        guard showing, let id = tour.activeTour else { return "idle" }
        return "\(id.rawValue)-\(tour.stepIndex)-\(tour.steps.map(\.id).joined(separator: ","))"
    }

    private var bubbleWidth: CGFloat { min(size.width - 32, 420) }

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
        .gesture(DragGesture(minimumDistance: 0))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.muted)
                    Spacer()
                    if !step.isPremium {
                        Button(LanguageManager.t("tour.skip")) { tour.skip() }
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(minHeight: 48)
                            .accessibilityIdentifier("tour-skip")
                    }
                }
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
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

private struct TourBubbleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TourButton: View {
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
                .font(.system(size: 15, weight: primary ? .semibold : .medium))
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AppColors.border, lineWidth: 1))
            .accessibilityIdentifier("pro-sample-data-label")
    }
}
