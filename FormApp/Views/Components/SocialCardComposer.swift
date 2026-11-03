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

/// Local presentation preferences stay outside workout backups and cloud sync.
final class SocialCardPreferences: ObservableObject {
    static let shared = SocialCardPreferences()
    @Published var reviewDeferredForVisit = false
    private var suggestionActive = false
    private var suggestionEngaged = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var options: SocialCardOptions {
        get { defaults.data(forKey: "social_card_options").flatMap { try? JSONDecoder().decode(SocialCardOptions.self, from: $0) } ?? SocialCardOptions() }
        set { if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "social_card_options") } }
    }
    var state: SocialSuggestionState {
        get { defaults.data(forKey: "social_suggestions").flatMap { try? JSONDecoder().decode(SocialSuggestionState.self, from: $0) } ?? SocialSuggestionState() }
        set { if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "social_suggestions") } }
    }
    func beginSuggestion(today: Date = Date()) -> Bool {
        guard state.canOffer(today: today) else { return false }
        state = state.offered(today: today)
        suggestionActive = true; suggestionEngaged = false; reviewDeferredForVisit = true
        return true
    }
    func engaged() { suggestionEngaged = true; state = state.engaged() }
    func finishSuggestion(today: Date = Date()) {
        guard suggestionActive else { return }
        suggestionActive = false
        state = suggestionEngaged ? state.engaged() : state.dismissed(today: today)
    }
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
    @State private var customizing = false

    init(request: SocialShareRequest, onDismiss: @escaping () -> Void) {
        self.request = request; self.onDismiss = onDismiss
        _options = State(initialValue: SocialCardPreferences.shared.options)
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
                    Button { customizing.toggle() } label: {
                        Text(t("customize")).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).accessibilityIdentifier("social-customize")
                    if customizing {
                        if request.cards.count > 1 {
                            Text(t("card")).foregroundStyle(AppColors.secondaryText)
                            Menu {
                                ForEach(Array(request.cards.enumerated()), id: \.element.id) { index, item in
                                    Button { selected = index } label: {
                                        if selected == index { Label(cardLabel(item), systemImage: "checkmark") }
                                        else { Text(cardLabel(item)) }
                                    }.accessibilityIdentifier("social-card-\(index)")
                                }
                            } label: {
                                Text(cardLabel(card)).frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.bordered).accessibilityIdentifier("social-card-choice")
                        }
                        Text(t("format")).foregroundStyle(AppColors.secondaryText)
                        HStack(spacing: 8) {
                            ForEach(SocialCardFormat.allCases, id: \.self) { option in
                                Button { format = option } label: {
                                    Text(t(option.rawValue)).frame(maxWidth: .infinity, minHeight: 48)
                                        .foregroundStyle(format == option ? AppColors.accent : AppColors.text)
                                        .background(format == option ? AppColors.positiveBg : AppColors.surfaceRaised)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).disabled(busy)
                                    .accessibilityAddTraits(format == option ? .isSelected : [])
                                    .accessibilityIdentifier("social-format-\(option.rawValue)")
                            }
                        }
                        Button { choosingPhoto = true } label: {
                            Text(t(photo == nil ? "addPhoto" : "changePhoto")).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("social-add-photo")
                        .photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images, preferredItemEncoding: .compatible)
                        if photo != nil {
                            Text(t("reposition")).appFont(.footnote).foregroundStyle(AppColors.secondaryText)
                            Button { photo = nil; photoItem = nil; photoRevision = UUID(); position = SocialPhotoPosition(); dragStart = position } label: {
                                Text(t("removePhoto")).frame(minHeight: 48)
                            }.disabled(busy)
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
                            Button { do { if let rendered { try SocialCardSharing.story(rendered); SocialCardPreferences.shared.engaged() } } catch { message = t("error") } } label: {
                                Text("Instagram Stories").frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.bordered).disabled(!ready)
                        }
                    }
                }.padding(20)
            }
            .background(AppColors.background)
            .navigationTitle(t(request.suggested ? "saved" : "share")).navigationBarTitleDisplayMode(.inline)
            .toolbar { FormCloseToolbarItem(action: onDismiss) }
            .tint(AppColors.accent)
            .sheet(item: $sharedURL) { SocialActivitySheet(url: $0.url) }
            .onAppear { SocialCardPreferences.shared.reviewDeferredForVisit = true }
            .onChange(of: options) { _, value in SocialCardPreferences.shared.options = value }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let message { Text(message).appFont(.footnote).foregroundStyle(AppColors.secondaryText).accessibilityIdentifier("social-status") }
                    action(t("share") + "…") {
                        if let rendered { sharedURL = SocialSharedURL(url: try SocialCardSharing.shareURL(rendered.image)); SocialCardPreferences.shared.engaged() }
                    }.accessibilityIdentifier("social-share")
                    Button {
                        guard let rendered else { return }
                        busy = true
                        Task {
                            do { try await SocialCardSharing.save(rendered.image); SocialCardPreferences.shared.engaged(); message = t("savedImage") }
                            catch SocialCardSharing.SharingError.permission { message = t("permission") }
                            catch { message = t("error") }
                            busy = false
                        }
                    } label: { Text(t("save")).frame(maxWidth: .infinity, minHeight: 48) }
                    .disabled(!ready).accessibilityIdentifier("social-save")
                }.padding(.horizontal, 20).padding(.top, 12).background(AppColors.surface).tint(AppColors.accent)
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

    private var ready: Bool { rendered != nil && renderedKey == renderKey && !busy  }
    private var preview: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered.image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity).frame(maxHeight: customizing ? 260 : 350)
                    .accessibilityLabel(description).accessibilityIdentifier("social-preview")
                    .gesture(DragGesture().onChanged { value in
                        guard photo != nil else { return }
                        position.x = min(1, max(-1, dragStart.x + value.translation.width / 150))
                        position.y = min(1, max(-1, dragStart.y + value.translation.height / 175))
                    }.onEnded { _ in dragStart = position })
                    .accessibilityAdjustableAction { direction in
                        guard photo != nil else { return }
                        position.y = min(1, max(-1, position.y + (direction == .increment ? 0.1 : -0.1))); dragStart = position
                    }
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
        }
    }
    private func cardLabel(_ item: SocialCardContent) -> String {
        item.kind == .record ? item.title : t(item.kind == .week ? "week" : "summary")
    }
    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding).padding(.horizontal, 14).frame(minHeight: 48)
            .foregroundStyle(AppColors.text).background(AppColors.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func action(_ title: String, perform: @escaping () throws -> Void) -> some View {
        Button { do { try perform() } catch { message = t("error") } } label: { Text(title).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(AppColors.background) }
            .buttonStyle(.borderedProminent).disabled(!ready)
    }
}
