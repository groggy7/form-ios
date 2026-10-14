import UIKit
import ImageIO

enum BundledPNGImage {
    /// Decode on the caller's worker queue; UIKit's display preparation warns for valid PNGs.
    static func load(from url: URL) -> UIImage? {
        let options = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: image)
    }
}
