import SwiftUI

public struct RestTimerBar: View {
    let secondsRemaining: Int
    let totalSeconds: Int
    let exerciseName: String
    let isRunning: Bool
    var onTogglePause: () -> Void
    var onAddSeconds: (Int) -> Void
    var onSkip: () -> Void
    var isMuted: Bool
    var onToggleMute: () -> Void

    public init(
        secondsRemaining: Int,
        totalSeconds: Int,
        exerciseName: String,
        isRunning: Bool,
        onTogglePause: @escaping () -> Void,
        onAddSeconds: @escaping (Int) -> Void,
        onSkip: @escaping () -> Void,
        isMuted: Bool,
        onToggleMute: @escaping () -> Void
    ) {
        self.secondsRemaining = secondsRemaining
        self.totalSeconds = totalSeconds
        self.exerciseName = exerciseName
        self.isRunning = isRunning
        self.onTogglePause = onTogglePause
        self.onAddSeconds = onAddSeconds
        self.onSkip = onSkip
        self.isMuted = isMuted
        self.onToggleMute = onToggleMute
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Top info row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LanguageManager.t("rest.title").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppColors.purple)
                    Text(exerciseName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.text)
                        .lineLimit(1)
                }

                Spacer()

                Text(RestTimerUtils.formatSecondsToTime(secondsRemaining))
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundColor(AppColors.purple)
            }

            // Controls
            HStack(spacing: 12) {
                Button(action: { onAddSeconds(-15) }) {
                    Text("-15s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: { onAddSeconds(30) }) {
                    Text("+30s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onTogglePause) {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isMuted ? AppColors.muted : AppColors.purple)
                        .padding(6)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onSkip) {
                    Text(LanguageManager.t("rest.skip"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColors.purple.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
    }
}
