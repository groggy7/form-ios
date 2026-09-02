import SwiftUI

public struct BottomDock: View {
    @Binding var currentView: ViewMode

    public init(currentView: Binding<ViewMode>) {
        self._currentView = currentView
    }

    public var body: some View {
        HStack(spacing: 4) {
            dockItem(mode: .today, title: LanguageManager.t("nav.today"), icon: "bolt.fill")
            dockItem(mode: .plan, title: LanguageManager.t("nav.plan"), icon: "calendar")
            dockItem(mode: .library, title: LanguageManager.t("nav.library"), icon: "dumbbell.fill")
            dockItem(mode: .history, title: LanguageManager.t("nav.history"), icon: "clock.arrow.circlepath")
        }
        .padding(6)
        .frame(maxWidth: 360)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func dockItem(mode: ViewMode, title: String, icon: String) -> some View {
        let isSelected = currentView == mode

        return Button(action: {
            withAnimation(.linear(duration: 0.1)) {
                currentView = mode
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(isSelected ? AppColors.positiveBg : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
