import SwiftUI

enum ExerciseBackdropStyle {
    static func file(for themeId: String) -> String {
        switch themeId {
        case "espresso", "stealth", "cobalt", "crimson", "amethyst": return themeId + ".png"
        default: return "green.png"
        }
    }
    static func perimeter(for themeId: String) -> Color {
        switch themeId {
        case "espresso": return Color(hex: 0x1B130F)
        case "stealth": return Color(hex: 0x101015)
        case "cobalt": return Color(hex: 0x08131F)
        case "crimson": return Color(hex: 0x1B0E13)
        case "amethyst": return Color(hex: 0x140E1E)
        default: return Color(hex: 0x051214)
        }
    }
}

private enum ExerciseBackdropImages {
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>(); cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    static let queue = DispatchQueue(label: "com.form.exercise-backdrops", qos: .userInitiated)
    static func cached(_ file: String) -> UIImage? { cache.object(forKey: file as NSString) }
    static func load(_ file: String) async -> UIImage? {
        if let image = cached(file) { return image }
        return await withCheckedContinuation { continuation in
            queue.async {
                if let image = cached(file) { continuation.resume(returning: image); return }
                guard let url = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "ExerciseBackdrops"),
                      let image = UIImage(contentsOfFile: url.path) else { continuation.resume(returning: nil); return }
                let prepared = image.preparingForDisplay() ?? image
                let cost = prepared.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
                cache.setObject(prepared, forKey: file as NSString, cost: cost)
                continuation.resume(returning: prepared)
            }
        }
    }
}

/// The same shared studio image backs static thumbnails and transparent video.
struct ExerciseMediaBackdrop: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var loadedImage: UIImage?
    @State private var loadedFile: String?
    var body: some View {
        let id = themeManager.currentTheme.id
        let file = ExerciseBackdropStyle.file(for: id)
        ZStack {
            ExerciseBackdropStyle.perimeter(for: id)
            if let image = ExerciseBackdropImages.cached(file) ?? (loadedFile == file ? loadedImage : nil) {
                Image(uiImage: image).resizable()
            }
        }
        .accessibilityHidden(true)
        .task(id: file) {
            let image = await ExerciseBackdropImages.load(file)
            guard !Task.isCancelled else { return }
            loadedFile = file; loadedImage = image
        }
    }
}
