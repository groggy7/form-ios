import SwiftUI

public struct ToastOverlay: View {
    let message: String?
    @State private var displayedMessage: String = ""
    @State private var isVisible: Bool = false

    public init(message: String?) {
        self.message = message
    }

    public var body: some View {
        VStack {
            Spacer()
            if isVisible && !displayedMessage.isEmpty {
                Text(displayedMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AppColors.surfaceRaised)
                            .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 80)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onChange(of: message) { _, newMsg in
            if let newMsg = newMsg, !newMsg.isEmpty {
                displayedMessage = newMsg
                withAnimation(.easeOut(duration: 0.28)) {
                    isVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeIn(duration: 0.24)) {
                        isVisible = false
                    }
                }
            }
        }
    }
}
