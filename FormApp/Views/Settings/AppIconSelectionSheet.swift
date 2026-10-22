import SwiftUI

/// Founder app icon picker. A choice applies at once; iOS then shows its own confirmation.
struct AppIconSelectionSheet: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject var manager: AppIconManager
    var onDismiss: () -> Void
    @State private var failed = false

    var body: some View {
        let _ = themeManager.currentTheme
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(LanguageManager.t("settings.appIcon"))
                    .appFont(.title2, weight: .semibold)
                    .foregroundStyle(AppColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                FormCloseButton(action: onDismiss)
                    .accessibilityIdentifier("app-icon-picker-close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(manager.icons) { option in
                        let isSelected = option == manager.current

                        Button {
                            Task { failed = !(await manager.select(option)) }
                        } label: {
                            HStack(spacing: 14) {
                                AppIconPreview(option: option, size: 48)

                                Text(LanguageManager.t(option.nameKey))
                                    .font(.app(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(AppColors.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minHeight: 68)
                            .background(isSelected ? AppColors.surfaceRaised : AppColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(isSelected ? AppColors.accent.opacity(0.8) : AppColors.border, lineWidth: isSelected ? 1.5 : 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("app-icon-option-\(option.id)")
                    }

                    if failed {
                        Text(LanguageManager.t("settings.appIconFailed"))
                            .font(.app(size: 12))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .accessibilityIdentifier("app-icon-picker-error")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(AppColors.background)
        .accessibilityIdentifier("app-icon-picker-sheet")
    }
}

/// The Appearance row that opens the picker; Settings shows it to founders only.
struct SettingsAppIconRow: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    let current: AppIconOption
    let action: () -> Void

    var body: some View {
        let _ = themeManager.currentTheme
        Button(action: action) {
            HStack(spacing: 12) {
                AppIconPreview(option: current, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("settings.appIcon"))
                        .font(.app(size: 15))
                        .foregroundStyle(AppColors.text)
                    Text(LanguageManager.t("settings.appIconSubtitle"))
                        .font(.app(size: 12))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(LanguageManager.t(current.nameKey))
                    .appFont(.subheadline)
                    .foregroundStyle(AppColors.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.muted)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-app-icon-row")
    }
}

/// The icon as the Home Screen draws it, in the system's continuous corner shape.
struct AppIconPreview: View {
    let option: AppIconOption
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Group {
            if let image = AppIconManager.previewImage(for: option) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                AppColors.surfaceRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppColors.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
