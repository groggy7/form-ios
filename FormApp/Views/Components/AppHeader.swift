import SwiftUI

public struct AppHeader: View {
    let title: String
    var subtitle: String? = nil
    var onSubtitleClick: (() -> Void)? = nil
    var onSettingsClick: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        onSubtitleClick: (() -> Void)? = nil,
        onSettingsClick: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onSubtitleClick = onSubtitleClick
        self.onSettingsClick = onSettingsClick
    }

    public var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppColors.text)

                if let sub = subtitle {
                    Button(action: { onSubtitleClick?() }) {
                        HStack(spacing: 4) {
                            Text(sub)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                            if onSubtitleClick != nil {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button(action: onSettingsClick) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.muted)
                    .frame(width: 44, height: 44)
                    .background(AppColors.surface)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(AppColors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
