import SwiftUI

/// Exact STEP1 images, independent of retired movementAssetId/category aliases.
enum ExerciseThumbnails {
    struct Entry: Decodable { let file: String }
    static let catalog: [String: Entry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "ExerciseThumbnails"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }()
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
    private static let loadQueue = DispatchQueue(label: "com.form.exercise-thumbnails", qos: .userInitiated)

    /// Safe during view construction: never touches the filesystem or decodes an image.
    static func cachedImage(for exerciseId: String?) -> UIImage? {
        exerciseId.flatMap { cache.object(forKey: $0 as NSString) }
    }

    static func load(for exerciseId: String?) async -> UIImage? {
        guard let exerciseId else { return nil }
        if let image = cachedImage(for: exerciseId) { return image }
        return await withCheckedContinuation { continuation in
            loadQueue.async {
                continuation.resume(returning: readImage(for: exerciseId))
            }
        }
    }

    private static func readImage(for exerciseId: String) -> UIImage? {
        dispatchPrecondition(condition: .onQueue(loadQueue))
        // Recheck after queueing so simultaneous requests for an ID share the decoded image.
        if let image = cachedImage(for: exerciseId) { return image }
        guard let entry = catalog[exerciseId] else { return nil }
        guard let url = Bundle.main.url(forResource: entry.file, withExtension: nil, subdirectory: "ExerciseThumbnails"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        let prepared = image.preparingForDisplay() ?? image
        let cost = prepared.cgImage.map { $0.bytesPerRow * $0.height } ?? Int(image.size.width * image.size.height * 4)
        cache.setObject(prepared, forKey: exerciseId as NSString, cost: cost)
        return prepared
    }
}

/// Static thumbnail by default; can optionally play looping movement animation when animated is true.
public struct MovementIcon: View {
    private let exerciseId: String?
    private let size: CGFloat
    private let large: Bool
    private let animated: Bool

    public init(
        exerciseId: String?,
        size: CGFloat = 56,
        large: Bool = false,
        animated: Bool = false
    ) {
        self.exerciseId = exerciseId
        self.size = size
        self.large = large
        self.animated = animated
    }

    public var body: some View {
        let finalSize: CGFloat = large ? 108 : size
        let cornerRadius: CGFloat = finalSize >= 96 ? 12 : (finalSize >= 68 ? 11 : 10)
        let hasVideo = animated && ExerciseVideoCatalog.url(for: exerciseId) != nil
        ZStack {
            if animated && hasVideo {
                ExerciseDetailVideo(exerciseId: exerciseId)
                    .accessibilityIdentifier("movement-icon-video")
            } else {
                MovementIllustration(exerciseId: exerciseId)
                    .padding(4)
            }
        }
        .frame(width: finalSize, height: finalSize)
        .background(AppColors.exerciseThumbnailSurface)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppColors.border.opacity(0.4), lineWidth: 1)
        )
    }
}

/// Unknown exercises remain empty instead of inheriting a similar movement.
public struct MovementIllustration: View {
    private let exerciseId: String?
    @State private var loadedImage: UIImage?
    @State private var loadedExerciseId: String?
    public init(exerciseId: String?) {
        self.exerciseId = exerciseId
    }

    public var body: some View {
        ZStack {
            Color.clear
            if let image = ExerciseThumbnails.cachedImage(for: exerciseId)
                ?? (loadedExerciseId == exerciseId ? loadedImage : nil) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }.accessibilityHidden(true)
        .task(id: exerciseId) {
            let image = await ExerciseThumbnails.load(for: exerciseId)
            guard !Task.isCancelled else { return }
            loadedExerciseId = exerciseId
            loadedImage = image
        }
    }
}
