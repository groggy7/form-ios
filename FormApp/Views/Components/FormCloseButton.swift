import SwiftUI

/// Circular dismiss controls share one opaque palette surface in every theme.
struct FormCloseButton: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let action: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .frame(width: 36, height: 36)
                .background(AppColors.surfaceRaised, in: Circle())
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LanguageManager.t("common.close"))
    }
}

struct FormCloseToolbarItem: ToolbarContent {
    var accessibilityIdentifier = "form-close"
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            FormCloseButton(action: action)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}
