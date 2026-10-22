import SwiftUI
import PhotosUI
import Photos
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum SocialCardSharing {
    enum SharingError: Error { case unavailable, permission, encoding }
    static var metaAppId: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "SocialMetaAppID") as? String ?? ""
        return !value.isEmpty && value.allSatisfy(\.isNumber) ? value : ""
    }
    static var canShareStory: Bool {
        !metaAppId.isEmpty && UIApplication.shared.canOpenURL(URL(string: "instagram-stories://share")!)
    }
    static func png(_ image: UIImage) throws -> Data {
        guard let data = image.pngData() else { throw SharingError.encoding }; return data
    }
    static func shareURL(_ image: UIImage) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("shared_cards", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: url) }
        }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try png(image).write(to: url, options: .atomic)
        return url
    }
    static func story(_ output: SocialRenderedImage) throws {
        guard canShareStory else { throw SharingError.unavailable }
        var item: [String: Any] = ["com.instagram.sharedSticker.backgroundImage": try png(output.background ?? output.image)]
        if let sticker = output.sticker { item["com.instagram.sharedSticker.stickerImage"] = try png(sticker) }
        UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(300), .localOnly: true])
        UIApplication.shared.open(URL(string: "instagram-stories://share?source_application=\(metaAppId)")!)
    }
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SharingError.permission }
        let data = try png(image)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions(); options.uniformTypeIdentifier = UTType.png.identifier
            request.addResource(with: .photo, data: data, options: options)
        }
    }
    nonisolated static func readPhoto(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1920
              ] as CFDictionary) else { throw SharingError.encoding }
        return UIImage(cgImage: image)
    }
}

// Serial actor work skips obsolete queued drag frames and bounds full-resolution bitmap memory.
private actor SocialRenderingWorker {
    static let shared = SocialRenderingWorker()
    func render(_ card: SocialCardContent, format: SocialCardFormat, options: SocialCardOptions,
                photo: UIImage?, position: SocialPhotoPosition) -> SocialRenderedImage? {
        guard !Task.isCancelled else { return nil }
        let output = SocialCardRenderer.render(card, format: format, options: options, photo: photo, position: position)
        return Task.isCancelled ? nil : output
    }
}

private struct SocialSharedURL: Identifiable { let id = UUID(); let url: URL }
private struct SocialActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ viewController: UIActivityViewController, context: Context) {}
}

struct SocialCardComposer: View {
    @ObservedObject private var theme = ThemeManager.shared
    let request: SocialShareRequest
    let onDismiss: () -> Void
    @State private var selected = 0
    @State private var format = SocialCardFormat.story
    @State private var options = SocialCardOptions()
    @State private var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var position = SocialPhotoPosition()
    @State private var dragStart = SocialPhotoPosition()
    @State private var rendered: SocialRenderedImage?
    @State private var renderedKey = ""
    @State private var photoRevision = UUID()
    @State private var busy = false
    @State private var message: String?
    @State private var sharedURL: SocialSharedURL?
    @State private var composer: Bool

    init(request: SocialShareRequest, onDismiss: @escaping () -> Void) {
        self.request = request; self.onDismiss = onDismiss
        _composer = State(initialValue: !request.suggested)
    }
    private func t(_ key: String) -> String { LanguageManager.t("social." + key) }
    private var card: SocialCardContent { request.cards[selected] }
    private var renderKey: String { "\(selected):\(format):\(options):\(position):\(photoRevision)" }
    private var description: String {
        ([!options.title && card.kind == .summary ? t("summary") : card.title, card.result, card.detail, card.previous, options.date ? card.date : nil].compactMap { $0 }
         + card.metrics.filter { !options.hiddenMetrics.contains($0.key) }.map { t($0.key) + ": " + $0.value }).joined(separator: ". ")
    }
    var body: some View {
        let _ = theme.currentTheme
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    preview
                    if composer {
                        if request.cards.count > 1 {
                            Text(t("card")).foregroundStyle(AppColors.secondaryText)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(request.cards.enumerated()), id: \.element.id) { index, item in
                                        Button { selected = index } label: {
                                            Text(item.kind == .record ? item.title : t(item.kind == .week ? "week" : "summary"))
                                                .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 48)
                                                .foregroundStyle(selected == index ? AppColors.accent : AppColors.text)
                                                .background(selected == index ? AppColors.positiveBg : AppColors.surfaceRaised)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }.buttonStyle(.plain).accessibilityAddTraits(selected == index ? .isSelected : [])
                                            .accessibilityIdentifier("social-card-\(index)")
                                    }
                                }
                            }
                        }
                        Text(t("format")).foregroundStyle(AppColors.secondaryText)
                        Picker(t("format"), selection: $format) {
                            ForEach(SocialCardFormat.allCases, id: \.self) { option in Text(t(option.rawValue)).tag(option) }
                        }.pickerStyle(.segmented).frame(minHeight: 48).disabled(busy).accessibilityIdentifier("social-format")
                        if format == .photo {
                            Button { choosingPhoto = true } label: {
                                Text(t(photo == nil ? "choosePhoto" : "changePhoto")).frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("social-choose-photo")
                            .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .compatible)
                            Text(t("reposition")).appFont(.footnote).foregroundStyle(AppColors.secondaryText)
                        }
                        toggle(t("date"), $options.date)
                        if card.kind == .summary { toggle(t("workoutTitle"), $options.title) }
                        if !card.primary.isEmpty || !card.secondary.isEmpty { toggle(t("muscles"), $options.muscles) }
                        ForEach(card.metrics, id: \.key) { metric in
                            toggle(t(metric.key), Binding(get: { !options.hiddenMetrics.contains(metric.key) }, set: { visible in
                                if visible { options.hiddenMetrics.remove(metric.key) } else { options.hiddenMetrics.insert(metric.key) }
                            }))
                        }
                        if format != .post && SocialCardSharing.canShareStory {
                            action("Instagram Stories") { if let rendered { try SocialCardSharing.story(rendered) } }
                        }
                        action(t("share") + "…") {
                            if let rendered { sharedURL = SocialSharedURL(url: try SocialCardSharing.shareURL(rendered.image)) }
                        }.accessibilityIdentifier("social-share")
                        Button {
                            guard let rendered else { return }
                            busy = true
                            Task {
                                do { try await SocialCardSharing.save(rendered.image); message = t("savedImage") }
                                catch SocialCardSharing.SharingError.permission { message = t("permission") }
                                catch { message = t("error") }
                                busy = false
                            }
                        } label: { Text(t("save")).frame(maxWidth: .infinity, minHeight: 48) }
                        .buttonStyle(.bordered).disabled(!ready).accessibilityIdentifier("social-save")
                    } else {
                        Button { composer = true } label: { Text(t("share")).frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("social-open-composer")
                    }
                    if let message { Text(message).appFont(.footnote).foregroundStyle(AppColors.secondaryText).accessibilityIdentifier("social-status") }
                }.padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(t(composer ? "title" : "saved")).navigationBarTitleDisplayMode(.inline)
            .toolbar { FormCloseToolbarItem(action: onDismiss) }
            .tint(AppColors.accent)
            .sheet(item: $sharedURL) { SocialActivitySheet(url: $0.url) }
            .onChange(of: format) { _, value in
                if value == .photo && photo == nil && !busy { choosingPhoto = true }
            }
            .onChange(of: choosingPhoto) { _, showing in
                if !showing && photoItem == nil && photo == nil && format == .photo { format = .story }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                busy = true
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw SocialCardSharing.SharingError.encoding }
                        photo = try await Task.detached { try SocialCardSharing.readPhoto(data) }.value
                        position = SocialPhotoPosition(); dragStart = position
                        // itemIdentifier is optional; force a new render even for providers without one.
                        photoRevision = UUID()
                    } catch { message = t("error") }
                    busy = false
                }
            }
        }.accessibilityIdentifier("social-composer")
            .task(id: renderKey) {
                let key = renderKey
                let value = card, choice = format, visibility = options, background = photo, offset = position
                let output = await SocialRenderingWorker.shared.render(value, format: choice, options: visibility, photo: background, position: offset)
                if let output, !Task.isCancelled { rendered = output; renderedKey = key }
            }
    }

    private var ready: Bool { rendered != nil && renderedKey == renderKey && !busy && (format != .photo || photo != nil) }
    private var preview: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered.image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(maxHeight: composer ? 350 : 290)
                    .accessibilityLabel(description).accessibilityIdentifier("social-preview")
                    .gesture(DragGesture().onChanged { value in
                        guard format == .photo && photo != nil else { return }
                        position.x = min(1, max(-1, dragStart.x + value.translation.width / 150))
                        position.y = min(1, max(-1, dragStart.y + value.translation.height / 175))
                    }.onEnded { _ in dragStart = position })
                    .accessibilityAdjustableAction { direction in
                        guard format == .photo else { return }
                        position.y = min(1, max(-1, position.y + (direction == .increment ? 0.1 : -0.1))); dragStart = position
                    }
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
        }
    }
    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding).padding(.horizontal, 14).frame(minHeight: 48)
            .foregroundStyle(AppColors.text).background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func action(_ title: String, perform: @escaping () throws -> Void) -> some View {
        Button { do { try perform() } catch { message = t("error") } } label: { Text(title).frame(maxWidth: .infinity, minHeight: 48) }
            .buttonStyle(.borderedProminent).disabled(!ready)
    }
}
