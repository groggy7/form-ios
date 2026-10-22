import SwiftUI
import UIKit

/// App-wide width text scale (docs/design/form-design-system.md#width-scaled-text). Text sizes are authored for a
/// 393pt-wide phone. Other phones multiply them by their width ratio, rounded to 0.01 and bounded so narrow phones
/// never get tiny text and large phones never get oversized text. Dynamic Type still applies through
/// `@ScaledMetric` sizes and `appFont(_:)` text styles; spacing, icon frames and touch targets stay fixed.
/// Keep the reference and bounds in sync with Android `TextWidthScale`.
enum TextWidthScale {
    static let referenceWidth: CGFloat = 393
    static let minFactor: CGFloat = 0.92
    static let maxFactor: CGFloat = 1.05

    static func factor(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        let ratio = (width / referenceWidth * 100).rounded() / 100
        return min(max(ratio, minFactor), maxFactor)
    }

    nonisolated(unsafe) private static var resolved: CGFloat?

    /// This device's factor, from its screen's narrower side so rotation never changes it. Views read it while the
    /// window scene is connected; before that it stays 1 without caching.
    static var factor: CGFloat {
        if let resolved { return resolved }
        guard Thread.isMainThread else { return 1 }
        let width = MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen.bounds.size }
                .first.map { min($0.width, $0.height) }
        }
        guard let width else { return 1 }
        let value = factor(forWidth: width)
        resolved = value
        return value
    }
}

extension Font {
    /// The system font at an authored size, scaled by `TextWidthScale` (and by Dynamic Type when the size is a
    /// `@ScaledMetric`). Use it instead of `.system(size:)`.
    static func app(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: size * TextWidthScale.factor, weight: weight, design: design)
    }
}

/// A text style that keeps Dynamic Type and follows `TextWidthScale`.
private struct AppTextStyleFont: ViewModifier {
    let weight: Font.Weight?
    @ScaledMetric private var size: CGFloat

    init(_ style: Font.TextStyle, weight: Font.Weight?) {
        self.weight = weight ?? (style == .headline ? .semibold : nil)
        _size = ScaledMetric(wrappedValue: Self.defaultSize(style), relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.app(size: size, weight: weight))
    }

    /// Text style sizes at the default Large Dynamic Type setting.
    static func defaultSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

extension View {
    /// Use instead of `.font(.caption)` and other text styles.
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(AppTextStyleFont(style, weight: weight))
    }
}
