import SwiftUI
import UIKit

// iPhone Duo support (docs/design/form-design-system.md#foldable-iphone).
// Phones without a hinge or a vertical bar never enter any of these paths.

/// Whether a foldable iPhone is open. Rotation is allowed only while it is.
final class FoldState: ObservableObject {
    static let shared = FoldState()

    /// Before the hinge first reports, only an open foldable's inner display is this wide on its short side.
    static let openDisplayMinimumSide: CGFloat = 600

    @Published private(set) var isOpen = false
    /// Set once the system reports a hinge; never on other iPhones.
    private(set) var hasHinge = false

    var supportedOrientations: UIInterfaceOrientationMask {
        isOpen ? .allButUpsideDown : .portrait
    }

    /// The orientations for a window on a screen of `screenSize`. Once the hinge reports, it decides. Before that, a
    /// launch on an open foldable keeps landscape allowed: a portrait-only start makes the system begin turning to
    /// portrait, and when the hinge reverses that turn mid-way the window can stay sideways.
    func supportedOrientations(onScreen screenSize: CGSize?, isPhone: Bool) -> UIInterfaceOrientationMask {
        if !hasHinge, isPhone, let screenSize, min(screenSize.width, screenSize.height) >= Self.openDisplayMinimumSide {
            return .allButUpsideDown
        }
        return supportedOrientations
    }

    func update(isOpen: Bool) {
        hasHinge = true
        guard isOpen != self.isOpen else { return }
        self.isOpen = isOpen
        // Ask every window to re-read the mask; folding returns the app to portrait.
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

private struct HingeTracking: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                // The angle streams while opening; only the status decides rotation.
                let status = context.hinge?.status
                FoldState.shared.update(isOpen: status == .partiallyOpen || status == .fullyOpen)
            }
        } else {
            content
        }
    }
}

/// The two pages of an open foldable held in landscape, split at the fold.
struct TwoPageLayout: Equatable {
    var leadingWidth: CGFloat
    var foldWidth: CGFloat
    var trailingWidth: CGFloat

    /// Each page keeps at least the narrowest supported phone width.
    static let minimumPageWidth: CGFloat = 320

    /// Splits the view at the fold; nil without a vertical fold or with a page narrower than a phone.
    static func resolve(in proxy: GeometryProxy) -> TwoPageLayout? {
        guard let fold = verticalFold(in: proxy) else { return nil }
        let layout = TwoPageLayout(leadingWidth: fold.minX, foldWidth: fold.width, trailingWidth: proxy.size.width - fold.maxX)
        guard layout.leadingWidth >= minimumPageWidth, layout.trailingWidth >= minimumPageWidth else { return nil }
        return layout
    }

    /// The system's division region across a landscape-shaped view, in its coordinates.
    static func verticalFold(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *), proxy.size.width > proxy.size.height else { return nil }
        let size = proxy.size
        return proxy.reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height >= size.height / 2 && $0.width < size.width / 4 && $0.minX > 0 && $0.maxX < size.width }
    }
}

private struct TwoPageLayoutKey: EnvironmentKey {
    static let defaultValue: TwoPageLayout? = nil
}

extension EnvironmentValues {
    /// Set on main tab pages while an open foldable shows two pages.
    var twoPageLayout: TwoPageLayout? {
        get { self[TwoPageLayoutKey.self] }
        set { self[TwoPageLayoutKey.self] = newValue }
    }
}

/// Places `leading` and `trailing` on either side of the fold.
struct TwoPageSpread<Leading: View, Trailing: View>: View {
    let layout: TwoPageLayout
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: layout.leadingWidth)
            Color.clear.frame(width: layout.foldWidth)
            trailing.frame(width: layout.trailingWidth)
        }
    }
}

/// Supplies the edge of the system's vertical bar, or nil where bars stay horizontal.
struct VerticalBarEdgeReader<Content: View>: View {
    @ViewBuilder var content: (HorizontalEdge?) -> Content

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalBarEdgeEnvironment(content: content)
        } else {
            content(nil)
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarEdgeEnvironment<Content: View>: View {
    @Environment(\.toolbarVerticalEdge) private var edge
    var content: (HorizontalEdge?) -> Content

    var body: some View { content(edge) }
}

/// Lays out the main pager beside the side dock, which fills the vertical bar's safe-area strip.
struct SideDockLayout: Layout {
    var edge: HorizontalEdge

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let pager = subviews.first else { return }
        let dock = subviews.count > 1 ? subviews[1] : nil
        let dockWidth = dock?.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width ?? 0
        let pagerWidth = max(0, bounds.width - dockWidth)
        let dockLeading = edge == .leading
        pager.place(at: CGPoint(x: dockLeading ? bounds.minX + dockWidth : bounds.minX, y: bounds.minY),
                    proposal: ProposedViewSize(width: pagerWidth, height: bounds.height))
        dock?.place(at: CGPoint(x: dockLeading ? bounds.minX : bounds.maxX - dockWidth, y: bounds.minY),
                    proposal: ProposedViewSize(width: dockWidth, height: bounds.height))
    }
}

/// The vertical bar's strip: status bar on top, the side dock centered below it.
struct SideDockSlot: View {
    @Binding var currentView: ViewMode
    var dragPosition: CGFloat?
    var width: CGFloat
    var isDockVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            let top = Self.statusBarBottom(in: proxy)
            if isDockVisible {
                BottomDock(currentView: $currentView, dragPosition: dragPosition, axis: .vertical)
                    .frame(width: proxy.size.width)
                    .position(x: proxy.size.width / 2, y: top + max(0, proxy.size.height - top) / 2)
            }
        }
        .frame(width: width)
        // The pager's scroll view does not clip; the strip covers whatever slides beneath it.
        .background(AppColors.background)
    }

    /// The bottom of the system status bar inside this strip, from its occlusion regions.
    private static func statusBarBottom(in proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return proxy.safeAreaInsets.top }
        let strip = CGRect(origin: .zero, size: proxy.size)
        let bottoms = proxy.reservedRegions(kind: .occlusion)
            .map(\.frame)
            .filter { $0.intersects(strip) && $0.minY < proxy.size.height / 2 }
            .map(\.maxY)
        return max(proxy.safeAreaInsets.top, bottoms.max() ?? 0)
    }
}

extension View {
    /// Beside a vertical bar the top safe area is ~0; adds the headroom a status bar gives elsewhere.
    func verticalBarHeadroom(_ amount: CGFloat) -> some View {
        VerticalBarEdgeReader { edge in
            self.safeAreaPadding(.top, edge == nil ? 0 : amount)
        }
    }

    /// Keeps `FoldState` in step with the device hinge.
    func tracksDeviceHinge() -> some View {
        modifier(HingeTracking())
    }
}
