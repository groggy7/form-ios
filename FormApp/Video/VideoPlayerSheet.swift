import SwiftUI

public struct VideoPlayerSheet: View {
    let exerciseName: String
    let videoUrl: String
    var onClose: () -> Void

    @StateObject private var controller: YouTubePlayerController
    private let parsedVideo: YouTubeVideo?

    public init(exerciseName: String, videoUrl: String, onClose: @escaping () -> Void) {
        self.exerciseName = exerciseName
        self.videoUrl = videoUrl
        self.onClose = onClose

        let parsed = YouTubeVideo.parse(videoUrl)
        self.parsedVideo = parsed
        _controller = StateObject(wrappedValue: YouTubePlayerController(
            video: parsed ?? YouTubeVideo(id: "00000000000")!,
            initialSeconds: Double(parsed?.startSeconds ?? 0)
        ))
    }

    public var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if parsedVideo == nil {
                invalidUrlContent
            } else {
                playerContent
            }
        }
        .preferredColorScheme(.dark)
    }

    private var invalidUrlContent: some View {
        VStack(spacing: 20) {
            HStack {
                Text(exerciseName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.text)
                    .lineLimit(2)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.text)
                        .padding(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.muted)

                Text(LanguageManager.t("video.invalid"))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let url = URL(string: videoUrl) {
                    Button(action: { UIApplication.shared.open(url) }) {
                        Text(LanguageManager.t("video.openExternal"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()
        }
    }

    private var playerContent: some View {
        GeometryReader { geo in
            let isShort = parsedVideo?.isShort == true
            let availableWidth = max(200, geo.size.width - 32)
            let availableHeight = max(200, geo.size.height - 240)

            let targetHeight = isShort ? availableWidth * (16.0 / 9.0) : availableWidth * (9.0 / 16.0)
            let videoHeight = min(availableHeight, max(200, targetHeight))
            let videoWidth = isShort ? videoHeight * (9.0 / 16.0) : min(availableWidth, videoHeight * (16.0 / 9.0))

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exerciseName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.text)
                            .lineLimit(2)

                        Text(isShort ? "YouTube Shorts" : "YouTube")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.muted)
                    }

                    Spacer()

                    if let watchUrl = parsedVideo?.watchUrl, let url = URL(string: watchUrl) {
                        Button(action: { UIApplication.shared.open(url) }) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.muted)
                                .frame(width: 36, height: 36)
                        }
                    }

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.text)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Spacer()

                // Video viewport
                ZStack {
                    Color.black

                    if controller.state.error == nil {
                        YouTubeWebPlayerView(controller: controller) { link in
                            if let url = URL(string: link) {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 32))
                                .foregroundColor(AppColors.muted)

                            let errKey = controller.state.error == "network" ? "video.networkError" : "video.embedError"
                            Text(LanguageManager.t(errKey))
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            Button(action: { controller.reload() }) {
                                Text(LanguageManager.t("video.retry"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(AppColors.surface)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(16)
                    }
                }
                .frame(width: videoWidth, height: videoHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border, lineWidth: 1))

                Spacer()

                // Controls Bar
                HStack(spacing: 32) {
                    // -5s button
                    Button(action: { controller.seek(-5) }) {
                        VStack(spacing: 2) {
                            Image(systemName: "gobackward.5")
                                .font(.system(size: 22, weight: .medium))
                            Text("−5s")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(controller.state.canControl ? AppColors.text : AppColors.muted.opacity(0.4))
                        .frame(width: 60, height: 50)
                    }
                    .disabled(!controller.state.canControl)

                    // Play / Pause / Replay primary circle
                    Button(action: {
                        if controller.state.playing {
                            controller.pause()
                        } else {
                            controller.play()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(controller.state.canControl ? AppColors.accent : AppColors.accent.opacity(0.3))
                                .frame(width: 64, height: 64)

                            Image(systemName: controller.state.playing ? "pause.fill" : (controller.state.ended ? "arrow.counterclockwise" : "play.fill"))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(AppColors.background)
                        }
                    }
                    .disabled(!controller.state.canControl)

                    // +5s button
                    Button(action: { controller.seek(5) }) {
                        VStack(spacing: 2) {
                            Image(systemName: "goforward.5")
                                .font(.system(size: 22, weight: .medium))
                            Text("+5s")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(controller.state.canControl ? AppColors.text : AppColors.muted.opacity(0.4))
                        .frame(width: 60, height: 50)
                    }
                    .disabled(!controller.state.canControl)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(AppColors.surface)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                )

                // Time status row
                HStack(spacing: 6) {
                    if controller.state.error == nil {
                        if !controller.state.ready || controller.state.playerState == 3 {
                            ProgressView()
                                .scaleEffect(0.65)
                                .tint(AppColors.muted)
                        }

                        if !controller.state.ready {
                            Text(LanguageManager.t("video.loading"))
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.muted)
                        } else {
                            Text("\(formatVideoTime(controller.state.currentSeconds)) / \(formatVideoTime(controller.state.durationSeconds))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppColors.muted)
                        }
                    }
                }
                .frame(height: 36)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }
}
