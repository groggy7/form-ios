import SwiftUI

public struct BottomDock: View {
    @Binding var currentView: ViewMode

    public init(currentView: Binding<ViewMode>) {
        self._currentView = currentView
    }

    public var body: some View {
        HStack(spacing: 0) {
            dockItem(mode: .today, title: LanguageManager.t("nav.today"), systemIcon: "calendar.badge.clock")
            dockItem(mode: .plan, title: LanguageManager.t("nav.plan"), systemIcon: "calendar")
            dockItem(mode: .library, title: LanguageManager.t("nav.library"), systemIcon: "books.vertical")
            dockItem(mode: .history, title: LanguageManager.t("nav.history"), systemIcon: "clock.arrow.circlepath")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func dockItem(mode: ViewMode, title: String, systemIcon: String) -> some View {
        let isSelected = currentView == mode
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentView = mode
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: systemIcon)
                    .font(.system(size: 18, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
