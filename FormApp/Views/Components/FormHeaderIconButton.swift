import SwiftUI

public struct FormHeaderIconButton: View {
    let icon: String // SF Symbol name
    let contentDescription: String
    let tint: Color
    let onClick: () -> Void

    public init(
        icon: String,
        contentDescription: String = "",
        tint: Color = AppColors.secondaryText,
        onClick: @escaping () -> Void
    ) {
        self.icon = icon
        self.contentDescription = contentDescription
        self.tint = tint
        self.onClick = onClick
    }

    public var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 48, height: 48)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contentDescription)
    }
}

public struct FormModalCloseButton: View {
    private let action: () -> Void
    private let accessibilityLabelText: String
    private let accessibilityIdentifierText: String?

    public init(
        action: @escaping () -> Void,
        accessibilityLabel: String = LanguageManager.t("common.close"),
        accessibilityIdentifier: String? = nil
    ) {
        self.action = action
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityIdentifierText = accessibilityIdentifier
    }

    public var body: some View {
        let button = Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.secondaryText)
                .frame(width: 32, height: 32)
                .background(AppColors.surfaceRaised)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)

        if let identifier = accessibilityIdentifierText {
            button.accessibilityIdentifier(identifier)
        } else {
            button
        }
    }
}
