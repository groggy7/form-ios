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
        let trimmed = inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return trimmed
        } else if lower.contains("://") {
            return trimmed
        } else if !trimmed.isEmpty {
            return "https://\(trimmed)"
        }
        return trimmed
    }

    private var isValidUrl: Bool {
        guard cleanInput.count <= 2_000,
              let url = URL(string: cleanInput),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty,
              host.contains(".") else {
            return false
        }
        return true
    }

    private var isDuplicate: Bool {
        linkedUrls.contains { $0.caseInsensitiveCompare(cleanInput) == .orderedSame }
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
                            .lineLimit(1)
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
                            // Left: Animation
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppColors.surfaceRaised)

                                MovementIllustration(
                                    name: exercise.name,
                                    movementType: exercise.resolvedMovement,
                                    movementAssetId: exercise.movementAssetId,
                                    allowCategoryFallback: false
                                )
                                .padding(4)
                            }
                            .frame(width: 76, height: 76)

                            // Right: Title & category pill
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.name)
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
                                        if let author = metadata?.authorName, !author.isEmpty, !isUnavailable {
                                            return "\(author) • \(platform)"
                                        }
                                        return platform
                                    }()

                                    HStack(spacing: 12) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(AppColors.coral)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(AppColors.text)
                                                .lineLimit(1)

                                            Text(subtitle)
                                                .font(.system(size: 11))
                                                .foregroundColor(AppColors.muted)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Button(action: { previewVideoUrl = url }) {
                                            Text(LanguageManager.t("video.previewVideo"))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(AppColors.accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            linkedUrls.removeAll { $0 == url }
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14))
                                                .foregroundColor(AppColors.danger)
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(AppColors.surface)
                                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AppColors.border, lineWidth: 1))
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LanguageManager.t("video.urlInputLabel"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)

                            HStack(spacing: 8) {
                                TextField(LanguageManager.t("video.urlInputPlaceholder"), text: $inputUrl)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.text)
                                    .accentColor(AppColors.accent)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(.horizontal, 12)
                                    .frame(height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppColors.background)
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                                    )

                                Button(action: {
                                    if let clip = UIPasteboard.general.string {
                                        inputUrl = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                }) {
                                    Text(LanguageManager.t("video.pasteButton"))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppColors.accent)
                                        .frame(height: 44)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(AppColors.surfaceRaised)
                                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }

                            // Validation & Add Button
                            HStack {
                                if linkedUrls.count >= 3 {
                                    Text(LanguageManager.t("video.maxLimitReached"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.muted)
                                } else if isDuplicate {
                                    Text(LanguageManager.t("video.duplicateUrl"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.coral)
                                } else if !inputUrl.isEmpty && !isValidUrl {
                                    Text(LanguageManager.t("video.invalidUrl"))
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.danger)
                                }

                                Spacer()

                                Button(action: addUrl) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                        Text(LanguageManager.t("video.addUrlButton"))
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .foregroundColor(canAdd ? AppColors.background : AppColors.muted)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(canAdd ? AppColors.accent : AppColors.surfaceRaised)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(!canAdd)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                // Bottom Save Action
                VStack(spacing: 0) {
                    Divider().background(AppColors.border)

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
