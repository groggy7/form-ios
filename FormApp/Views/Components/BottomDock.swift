import SwiftUI
import UIKit

public struct BottomDock: View {
    @Binding var currentView: ViewMode
    var dragPosition: CGFloat?

    public init(currentView: Binding<ViewMode>, dragPosition: CGFloat? = nil) {
        self._currentView = currentView
        self.dragPosition = dragPosition
    }

    private let destinations: [(mode: ViewMode, title: String, icon: String)] = [
        (.today, LanguageManager.t("nav.home"), "bolt.fill"),
        (.plan, LanguageManager.t("nav.plan"), "calendar"),
        (.library, LanguageManager.t("nav.library"), "dumbbell.fill"),
        (.history, LanguageManager.t("nav.progress"), "chart.xyaxis.line")
    ]

    public var body: some View {
        GeometryReader { proxy in
            let innerPadding: CGFloat = 6
            let spacing: CGFloat = 4
            let totalAvailableWidth = proxy.size.width - (innerPadding * 2)
            let itemWidth = max(0, (totalAvailableWidth - (spacing * CGFloat(destinations.count - 1))) / CGFloat(destinations.count))
            let currentIndex = CGFloat(destinations.firstIndex(where: { $0.mode == currentView }) ?? 0)
            let activePosition = max(0, min(CGFloat(destinations.count - 1), dragPosition ?? currentIndex))
            let pillOffset = innerPadding + activePosition * (itemWidth + spacing)

            ZStack(alignment: .leading) {
                // Sliding active pill
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(AppColors.positiveBg)
                    .frame(width: itemWidth, height: proxy.size.height - (innerPadding * 2))
                    .offset(x: pillOffset, y: 0)
                    .allowsHitTesting(false)

                HStack(spacing: spacing) {
                    ForEach(Array(destinations.enumerated()), id: \.offset) { index, item in
                        dockItem(mode: item.mode, title: item.title, icon: item.icon, index: CGFloat(index), activePosition: activePosition)
                    }
                }
                .padding(innerPadding)
            }
        }
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
        .padding(.bottom, 20)
    }

    private func dockItem(mode: ViewMode, title: String, icon: String, index: CGFloat, activePosition: CGFloat) -> some View {
        let distance = abs(activePosition - index)
        let selectionFraction = max(0, min(1, 1 - distance))
        let foreground = interpolatedForeground(selectionFraction)

        return Button(action: {
            currentView = mode
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(foreground)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dock-\(mode.rawValue)")
        .accessibilityAddTraits(currentView == mode ? .isSelected : [])
    }

    private func interpolatedForeground(_ fraction: CGFloat) -> Color {
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        UIColor(AppColors.secondaryText).getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        UIColor(AppColors.accent).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        return Color(.sRGB,
                     red: Double(r0 + (r1 - r0) * fraction),
                     green: Double(g0 + (g1 - g0) * fraction),
                     blue: Double(b0 + (b1 - b0) * fraction),
                     opacity: Double(a0 + (a1 - a0) * fraction))
    }

}
