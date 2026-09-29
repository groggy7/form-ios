import SwiftUI

public enum ToastStyle: Equatable {
    case info
    case error
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
    let item: ToastItem?
    var bottomPadding: CGFloat

    @State private var currentItem: ToastItem? = nil
    @State private var isVisible: Bool = false
    @State private var dismissTimer: DispatchWorkItem? = nil

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
        VStack {
            Spacer()
            if isVisible, let displayed = currentItem, !displayed.message.isEmpty {
                HStack(spacing: 8) {
                    if displayed.style == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppColors.danger)
                    }
                    Text(displayed.message)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(displayed.style == .error ? AppColors.danger : AppColors.accent)
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
                                    displayed.style == .error ? AppColors.danger.opacity(0.4) : AppColors.border,
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
                )
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, bottomPadding)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onChange(of: item) { _, newItem in
            dismissTimer?.cancel()
            guard let newItem = newItem, !newItem.message.isEmpty else {
                withAnimation(.easeIn(duration: 0.2)) {
                    isVisible = false
                }
                return
            }

            currentItem = newItem
            withAnimation(.easeOut(duration: 0.28)) {
                isVisible = true
            }

            let work = DispatchWorkItem {
                withAnimation(.easeIn(duration: 0.24)) {
                    isVisible = false
                }
            }
            dismissTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + newItem.duration, execute: work)
        }
    }
}
