import SwiftUI

public struct ExerciseVideosView: View {
    let exercise: Exercise
    var onAddVideo: (() -> Void)? = nil
    var onRemoveVideo: ((String) -> Void)? = nil

    @State private var selectedVideoUrl: String? = nil
    @State private var metadataMap: [String: VideoMetadata] = [:]

    public init(
        exercise: Exercise,
        onAddVideo: (() -> Void)? = nil,
        onRemoveVideo: ((String) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.onAddVideo = onAddVideo
        self.onRemoveVideo = onRemoveVideo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LanguageManager.t("library.videos"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.text)

            ForEach(Array(exercise.videos.enumerated()), id: \.offset) { index, url in
                let isYouTube = YouTubeVideo.isYouTubeUrl(url)
                let parsed = YouTubeVideo.parse(url)
                let metadata = metadataMap[url]
                let isUnavailable = metadata?.isUnavailable == true

                let title: String = {
                    if isUnavailable {
                        return LanguageManager.t("library.videoUnavailable")
                    }
                    if let t = metadata?.title, !t.isEmpty {
                        return t
                    }
                    return LanguageManager.t("library.videoItem", ["num": "\(index + 1)"])
                }()

                let subtitle: String = {
                    let domain = URL(string: url)?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? ""
                    let platform = parsed?.isShort == true ? "YouTube Shorts" : (isYouTube ? "YouTube" : domain)
                    if let author = metadata?.authorName, !author.isEmpty, !isUnavailable {
                        return "\(author) • \(platform)"
                    }
                    return platform
                }()

                Button(action: {
                    if isUnavailable { return }
                    if isYouTube {
                        selectedVideoUrl = url
                    } else if let link = URL(string: url) {
                        UIApplication.shared.open(link)
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: isUnavailable ? "wifi.slash" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isUnavailable ? AppColors.danger : AppColors.coral)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isUnavailable ? AppColors.danger : AppColors.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.muted)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isUnavailable, let onRemove = onRemoveVideo {
                            Button(action: {
                                VideoMetadataStore.shared.evict(for: url)
                                onRemove(url)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                    Text(LanguageManager.t("library.remove"))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(AppColors.danger)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: isYouTube ? "chevron.right" : "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.muted.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(isUnavailable ? AppColors.surface.opacity(0.7) : AppColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(isUnavailable ? AppColors.danger.opacity(0.4) : AppColors.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .task(id: url) {
                    if metadataMap[url] == nil && isYouTube {
                        let fetched = await VideoMetadataStore.shared.fetch(for: url)
                        metadataMap[url] = fetched
                    }
                }
            }

            if let onAdd = onAddVideo {
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text(LanguageManager.t("library.attachVideoCta"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: Binding<IdentifiedVideo?>(
            get: { selectedVideoUrl.map { IdentifiedVideo(url: $0) } },
            set: { selectedVideoUrl = $0?.url }
        )) { item in
            VideoPlayerSheet(exerciseName: exercise.name, videoUrl: item.url) {
                selectedVideoUrl = nil
            }
        }
    }
}

private struct IdentifiedVideo: Identifiable {
    let url: String
    var id: String { url }
}
