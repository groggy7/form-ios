import SwiftUI

/// Preserves the existing thumbnail frame while replacement media is prepared.
public struct MovementIcon: View {
    private let size: CGFloat
    private let large: Bool

    public init(
        name: String,
        size: CGFloat = 56,
        large: Bool = false,
        movementType: MovementType = .other,
        movementAssetId: String? = nil,
        allowCategoryFallback: Bool = true
    ) {
        self.size = size
        self.large = large
    }

    public var body: some View {
        let finalSize: CGFloat = large ? 108 : size
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AppColors.surface)
            .frame(width: finalSize, height: finalSize)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.border.opacity(0.4), lineWidth: 1)
            )
    }
}

/// Deliberately empty: no fallback glyph, image decoding, or animation clock.
public struct MovementIllustration: View {
    public init(
        name: String,
        movementType: MovementType = .other,
        movementAssetId: String? = nil,
        allowCategoryFallback: Bool = true
    ) {}

    public var body: some View {
        Color.clear.accessibilityHidden(true)
    }
}
