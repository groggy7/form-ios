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
    static func image(for exerciseId: String?) -> UIImage? {
        guard let id = exerciseId, let entry = catalog[id] else { return nil }
        if let image = cache.object(forKey: id as NSString) { return image }
        guard let url = Bundle.main.url(forResource: entry.file, withExtension: nil, subdirectory: "ExerciseThumbnails"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: id as NSString, cost: Int(image.size.width * image.size.height * 4))
        return image
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
        let hasVideo = ExerciseVideoCatalog.url(for: exerciseId) != nil
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
    public init(exerciseId: String?) {
        self.exerciseId = exerciseId
    }

    public var body: some View {
        ZStack {
            Color.clear
            if let image = ExerciseThumbnails.image(for: exerciseId) {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }.accessibilityHidden(true)
    }
}
