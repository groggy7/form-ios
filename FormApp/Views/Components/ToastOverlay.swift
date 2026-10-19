import SwiftUI

public enum ToastStyle: Equatable {
    case info
    case error
    /// Explains a locked Premium control; not an error.
    case premium
}

public struct ToastItem: Identifiable, Equatable {
    public let id: UUID
    public let message: String
    public let style: ToastStyle
    public let duration: Double

    public init(id: UUID = UUID(), message: String, style: ToastStyle = .info, duration: Double = 3.0) {
        self.id = id
        self.message = message
        self.style = style
        self.duration = duration
    }

    public static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

public struct ToastOverlay: View {
    @ObservedObject var themeManager = ThemeManager.shared
    let item: ToastItem?
    var bottomPadding: CGFloat

    @State private var currentItem: ToastItem? = nil
    @State private var isVisible: Bool = false

    public init(item: ToastItem?, bottomPadding: CGFloat = 80) {
        self.item = item
        self.bottomPadding = bottomPadding
    }

    public init(message: String?, bottomPadding: CGFloat = 80) {
        if let msg = message, !msg.isEmpty {
            self.item = ToastItem(message: msg)
        } else {
            self.item = nil
        }
        self.bottomPadding = bottomPadding
    }

    public var body: some View {
        let _ = themeManager.currentTheme
        VStack {
            Spacer()
            if isVisible, let displayed = currentItem, !displayed.message.isEmpty {
                ToastPill(item: displayed)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, bottomPadding)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .task(id: item?.id) { @MainActor in
            guard let item, !item.message.isEmpty else {
                withAnimation(.easeIn(duration: 0.2)) { isVisible = false }
                return
            }
            currentItem = item
            withAnimation(.easeOut(duration: 0.28)) { isVisible = true }
            do { try await Task.sleep(for: .seconds(max(0, item.duration))) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.24)) { isVisible = false }
        }
    }
}

/// The notice pill itself, separate from its timing so tests can render it directly.
struct ToastPill: View {
    let item: ToastItem

    var body: some View {
        HStack(spacing: 8) {
            switch item.style {
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.danger)
            case .premium:
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.purple)
            case .info:
                EmptyView()
            }
            Text(item.message)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(textColor(item.style))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            item.style == .error ? AppColors.danger.opacity(0.4) : AppColors.border,
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
        )
    }

    private func textColor(_ style: ToastStyle) -> Color {
        switch style {
        case .error: AppColors.danger
        case .premium: AppColors.text
        case .info: AppColors.accent
        }
    }
}
