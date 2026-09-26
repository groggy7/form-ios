import SwiftUI

public struct ExerciseVideoLinksSheet: View {
    let exercise: Exercise
    var onDismiss: () -> Void
    var onSave: ((Exercise, [String]) -> Void)? = nil

    @State private var linkedUrls: [String]
    @State private var inputUrl: String = ""
    @State private var previewVideoUrl: String? = nil
    @State private var metadataMap: [String: VideoMetadata] = [:]

    public init(
        exercise: Exercise,
        onDismiss: @escaping () -> Void,
        onSave: ((Exercise, [String]) -> Void)? = nil
    ) {
        self.exercise = exercise
        self.onDismiss = onDismiss
        self.onSave = onSave
        _linkedUrls = State(initialValue: exercise.videos)
    }

    private var cleanInput: String {
        YouTubeVideo.normalizeInput(inputUrl)
    }

    private var isValidUrl: Bool {
        YouTubeVideo.isSupportedLink(cleanInput)
    }

    private var validLinkedUrls: Bool { linkedUrls.allSatisfy(YouTubeVideo.isSupportedLink) }

    private var isDuplicate: Bool {
        linkedUrls.contains { YouTubeVideo.isSameVideo($0, cleanInput) }
    }

    private var canAdd: Bool {
        isValidUrl && !isDuplicate && linkedUrls.count < 3
    }

    private func addUrl() {
        if canAdd {
            linkedUrls.append(cleanInput)
            inputUrl = ""
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageManager.t("video.linkTitle"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.text)

                        Text(LanguageManager.t("video.linkSubtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.muted)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.muted)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Body scrollable
                ScrollView {
                    VStack(spacing: 16) {
                        // Exercise Card
                        HStack(spacing: 14) {
                            // Left: Static STEP1 thumbnail
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.exerciseThumbnailSurface)

                                MovementIllustration(exerciseId: exercise.exerciseId)
                                .padding(4)
                            }
                            .frame(width: 76, height: 76)

                            // Right: Title & category pill
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.displayName)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(AppColors.text)
                                    .lineLimit(2)

                                Text(LanguageManager.t("category.\(exercise.resolvedMovement.key)").uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )

                        // Linked Videos Section
                        HStack {
                            Text(LanguageManager.t("video.linkedCount", ["count": "\(linkedUrls.count)"]))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppColors.text)

                            Spacer()
                        }

                        if linkedUrls.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "play.rectangle.on.rectangle")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppColors.muted)

                                Text(LanguageManager.t("video.noVideos"))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.muted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(Array(linkedUrls.enumerated()), id: \.offset) { index, url in
                                    let isYouTube = YouTubeVideo.isYouTubeUrl(url)
                                    let parsed = YouTubeVideo.parse(url)
                                    let metadata = metadataMap[url]
                                    let isUnavailable = metadata?.isUnavailable == true

                                    let title: String = {
                                        if isUnavailable { return LanguageManager.t("library.videoUnavailable") }
                                        if let t = metadata?.title, !t.isEmpty { return t }
                                        return LanguageManager.t("library.videoItem", ["num": "\(index + 1)"])
                                    }()

                                    let subtitle: String = {
                                        let domain = URL(string: url)?.host?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? ""
                                        let platform = parsed?.isShort == true ? "YouTube Shorts" : (isYouTube ? "YouTube" : domain)
                                        let hint = LanguageManager.t("video.tapToPlay")
                                        if isUnavailable {
                                            return platform
                                        }
                                        if let author = metadata?.authorName, !author.isEmpty {
                                            return "\(author) • \(platform) • \(hint)"
                                        }
                                        return "\(platform) • \(hint)"
                                    }()

                                    HStack(spacing: 0) {
                                        // Clickable card body that plays video
                                        Button(action: {
                                            if !isUnavailable {
                                                previewVideoUrl = url
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: isUnavailable ? "wifi.slash" : "play.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundColor(isUnavailable ? AppColors.danger : AppColors.coral)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(title)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(isUnavailable ? AppColors.danger : AppColors.text)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)

                                                    Text(subtitle)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(AppColors.muted)
                                                        .lineLimit(1)
                                                }

                                                Spacer()
                                            }
                                            .padding(.leading, 14)
                                            .padding(.trailing, 10)
                                            .padding(.vertical, 10)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        // Subtle vertical divider before remove button
                                        Rectangle()
                                            .fill(AppColors.border.opacity(0.7))
                                            .frame(width: 1, height: 28)

                                        // Remove action
                                        Button(action: {
                                            linkedUrls.removeAll { $0 == url }
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 15))
                                                .foregroundColor(AppColors.danger)
                                                .frame(width: 42, height: 42)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(AppColors.surface)
                                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(isUnavailable ? AppColors.danger.opacity(0.4) : AppColors.border, lineWidth: 1))
                                    )
                                    .task(id: url) {
                                        if metadataMap[url] == nil && isYouTube {
                                            let fetched = await VideoMetadataStore.shared.fetch(for: url)
                                            metadataMap[url] = fetched
                                        }
                                    }
                                }
                            }
                        }

                        // Add Video Section
                        if linkedUrls.count < 3 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(LanguageManager.t("library.attachVideoCta"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.text)

                                // Input box with inline Paste / Clear button
                                HStack(spacing: 8) {
                                    TextField(LanguageManager.t("video.urlInputLabel"), text: $inputUrl)
                                        .font(.system(size: 14))
                                        .foregroundColor(AppColors.text)
                                        .accentColor(AppColors.accent)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .submitLabel(.done)
                                        .onSubmit { addUrl() }

                                    if inputUrl.isEmpty {
                                        Button(action: {
                                            if let clip = UIPasteboard.general.string {
                                                inputUrl = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.on.clipboard")
                                                    .font(.system(size: 13))
                                                Text(LanguageManager.t("video.paste"))
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .foregroundColor(AppColors.accent)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 4)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Button(action: { inputUrl = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(AppColors.muted)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppColors.background)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .stroke((!inputUrl.isEmpty && (!isValidUrl || isDuplicate)) ? AppColors.danger : AppColors.border, lineWidth: 1)
                                        )
                                 )

                                // Supporting / validation text
                                Group {
                                    if isDuplicate {
                                        Text(LanguageManager.t("video.alreadyAdded"))
                                            .foregroundColor(AppColors.danger)
                                    } else if !inputUrl.isEmpty && !isValidUrl {
                                        Text(LanguageManager.t("video.youtubeOnly"))
                                            .foregroundColor(AppColors.danger)
                                    } else {
                                        Text(LanguageManager.t("programs.videoHint"))
                                            .foregroundColor(AppColors.muted)
                                    }
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 4)

                                // Full-width Add link button
                                Button(action: addUrl) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .bold))
                                        Text(LanguageManager.t("video.addUrlButton"))
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(canAdd ? AppColors.background : AppColors.muted)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(canAdd ? AppColors.accent : AppColors.surfaceRaised)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!canAdd)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppColors.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                            )
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColors.accent)

                                Text(LanguageManager.t("video.maxReached"))
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.muted)

                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.surfaceRaised)
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                // Bottom Save Action
                VStack(spacing: 0) {
                    Divider().background(AppColors.border)

                    if !validLinkedUrls {
                        Text(LanguageManager.t("video.youtubeOnly"))
                            .font(.system(size: 12)).foregroundColor(AppColors.danger)
                            .padding(.horizontal, 20).padding(.top, 8)
                    }

                    Button(action: {
                        if let onSave = onSave {
                            onSave(exercise, linkedUrls)
                        } else {
                            AppStore.shared.setExerciseVideos(exerciseName: exercise.name, videoUrls: linkedUrls)
                            onDismiss()
                        }
                    }) {
                        Text(LanguageManager.t("video.saveLinks"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AppColors.accent)
                            )
                    }
                    .disabled(!validLinkedUrls)
                    .opacity(validLinkedUrls ? 1 : 0.5)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .background(AppColors.surface)
            }
            .background(AppColors.background)
            .sheet(item: Binding<IdentifiedVideo?>(
                get: { previewVideoUrl.map { IdentifiedVideo(url: $0) } },
                set: { previewVideoUrl = $0?.url }
            )) { item in
                VideoPlayerSheet(exerciseName: exercise.name, videoUrl: item.url) {
                    previewVideoUrl = nil
                }
            }
        }
    }
}

private struct IdentifiedVideo: Identifiable {
    let url: String
    var id: String { url }
}
