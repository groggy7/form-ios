import UIKit
import SwiftUI

enum SocialCardFormat: String, CaseIterable { case story, post }
struct SocialCardOptions: Codable, Equatable {
    var date = true
    var title = true
    var muscles = true
    var hiddenMetrics: Set<String> = []
}
struct SocialPhotoPosition: Equatable { var x: CGFloat = 0; var y: CGFloat = 0 }
struct SocialRenderedImage { let image: UIImage; var background: UIImage? = nil; var sticker: UIImage? = nil }

/// Fixed-canvas native renderer. The exact bitmap shown in the preview is passed to sharing.
enum SocialCardRenderer {
    private static let palette = AppThemes.default
    private static var ink: UIColor { UIColor(palette.text) }
    private static var secondary: UIColor { UIColor(palette.secondaryText) }
    private static var accent: UIColor { UIColor(palette.accent) }
    private static func attributes(_ size: CGFloat, _ bold: Bool, _ color: UIColor) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: color]
    }
    private static func measure(_ text: String, _ width: CGFloat, _ size: CGFloat, _ bold: Bool) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(size, bold, ink), context: nil).height)
    }
    @discardableResult
    private static func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat, bold: Bool = false, color: UIColor? = nil, maxLines: Int = .max) -> CGFloat {
        var fitting = size
        while measure(text, width, fitting, bold) > UIFont.systemFont(ofSize: fitting, weight: bold ? .bold : .regular).lineHeight * CGFloat(maxLines == .max ? 10000 : maxLines) && fitting > 12 { fitting -= 1 }
        let height = measure(text, width, fitting, bold)
        (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(fitting, bold, color ?? ink), context: nil)
        return height
    }
    private static func renderer(_ size: CGSize, opaque: Bool = false) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = opaque; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }
    static func titleFits(_ title: String) -> Bool { measure(title, 260, 18, true) <= ceil(UIFont.systemFont(ofSize: 18, weight: .bold).lineHeight * 3) }

    static func render(_ card: SocialCardContent, format: SocialCardFormat, options: SocialCardOptions = SocialCardOptions(), photo: UIImage? = nil, position: SocialPhotoPosition = SocialPhotoPosition()) -> SocialRenderedImage {
        let canvasHeight: CGFloat = format == .post ? 450 : 640
        if let photo {
            let background = renderer(CGSize(width: 360, height: canvasHeight), opaque: true).image { _ in
                let scale = max(360 / photo.size.width, canvasHeight / photo.size.height)
                let w = photo.size.width * scale, h = photo.size.height * scale
                let left = (360 - w) / 2 + (w - 360) / 2 * min(1, max(-1, position.x))
                let top = (canvasHeight - h) / 2 + (h - canvasHeight) / 2 * min(1, max(-1, position.y))
                photo.draw(in: CGRect(x: left, y: top, width: w, height: h))
            }
            let sticker = panel(card, options, width: 300, maxHeight: format == .post ? 270 : 330, overlay: true)
            let image = renderer(CGSize(width: 360, height: canvasHeight), opaque: true).image { _ in
                background.draw(in: CGRect(x: 0, y: 0, width: 360, height: canvasHeight))
                sticker.draw(in: CGRect(x: 30, y: canvasHeight - (format == .post ? 20 : 114) - sticker.size.height, width: 300, height: sticker.size.height))
            }
            return SocialRenderedImage(image: sRGB(image), background: sRGB(background), sticker: sRGB(sticker))
        }
        let height: CGFloat = format == .post ? 450 : 640
        let cardPanel = panel(card, options, width: 320, maxHeight: 410, overlay: false)
        let image = renderer(CGSize(width: 360, height: height), opaque: true).image { c in
            UIColor(palette.background).setFill(); c.fill(CGRect(x: 0, y: 0, width: 360, height: height))
            cardPanel.draw(in: CGRect(x: 20, y: height == 640 ? 90 + (436 - cardPanel.size.height) / 2 : (height - cardPanel.size.height) / 2, width: 320, height: cardPanel.size.height))
        }
        return SocialRenderedImage(image: sRGB(image))
    }

    private static func sRGB(_ image: UIImage) -> UIImage {
        guard let source = image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output, scale: 3, orientation: .up)
    }

    private static func panel(_ card: SocialCardContent, _ options: SocialCardOptions, width: CGFloat, maxHeight: CGFloat, overlay: Bool) -> UIImage {
        let inset: CGFloat = 20, usable = width - 40
        let title = !options.title && card.kind == .summary ? LanguageManager.t("social.summary") : card.title
        var metrics = card.metrics.filter { !options.hiddenMetrics.contains($0.key) }
        var includeDate = options.date && card.date != nil
        var titleSize: CGFloat = overlay ? 23 : 27
        var resultSize: CGFloat = overlay ? 36 : card.kind == .record ? 52 : card.kind == .summary ? 34 : 50
        let detailSize: CGFloat = 13
        while measure(title, usable, titleSize, true) > UIFont.systemFont(ofSize: titleSize, weight: .bold).lineHeight * 3 && titleSize > 18 { titleSize -= 1 }
        func titleHeight() -> CGFloat { min(measure(title, usable, titleSize, true), ceil(UIFont.systemFont(ofSize: titleSize, weight: .bold).lineHeight * 3)) }
        func baseHeight() -> CGFloat {
            20 + titleHeight() + 10 + measure(card.result, usable, resultSize, true) + 4 + measure(card.detail, usable, detailSize, false) + 10 +
                (card.previous.map { measure($0, usable, 11, false) + 8 } ?? 0) + CGFloat(metrics.count) * 18 + 37 + (includeDate ? 26 : 0)
        }
        if baseHeight() > maxHeight { includeDate = false }
        while baseHeight() > maxHeight && !metrics.isEmpty { metrics.removeLast() }
        while baseHeight() > maxHeight && resultSize > 20 { resultSize -= 1 }
        let hasMap = options.muscles && (!card.primary.isEmpty || !card.secondary.isEmpty)
        let mapTarget: CGFloat = overlay ? 80 : 170
        let availableMapHeight = hasMap ? min(mapTarget, max(0, maxHeight - baseHeight() - 8)) : 0
        let mapHeight = availableMapHeight >= 60 ? availableMapHeight : 0
        let height = baseHeight() + (mapHeight > 0 ? mapHeight + 8 : 0)
        return renderer(CGSize(width: width, height: height)).image { _ in
            let shape = UIBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), cornerRadius: 20)
            UIColor(palette.surface).withAlphaComponent(overlay ? 0.9 : 1).setFill(); shape.fill()
            UIColor(palette.border).setStroke(); shape.lineWidth = 1; shape.stroke()
            var y: CGFloat = 20
            var fittedTitle = title
            if measure(fittedTitle, usable, titleSize, true) > titleHeight() {
                while !fittedTitle.isEmpty && measure(fittedTitle + "…", usable, titleSize, true) > titleHeight() { fittedTitle.removeLast() }
                fittedTitle += "…"
            }
            (fittedTitle as NSString).draw(with: CGRect(x: inset, y: y, width: usable, height: titleHeight()), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(titleSize, true, ink), context: nil)
            y += titleHeight() + 10
            y += label(card.result, inset, y, usable, resultSize, bold: true) + 4
            y += label(card.detail, inset, y, usable, detailSize, color: card.kind == .record ? accent : secondary) + 10
            if mapHeight > 0 {
                drawMuscles(card, rect: CGRect(x: inset, y: y, width: usable, height: mapHeight)); y += mapHeight + 8
            }
            if let previous = card.previous { y += label(previous, inset, y, usable, 11, color: secondary) + 8 }
            for metric in metrics {
                label(LanguageManager.t("social." + metric.key), inset, y, usable * 0.55, 10, color: secondary, maxLines: 1)
                let metricWidth = max(usable * 0.45, (metric.value as NSString).size(withAttributes: attributes(12, true, ink)).width)
                label(metric.value, width - inset - metricWidth, y, metricWidth, 12, bold: true, maxLines: 1)
                y += 18
            }
            if includeDate, let date = card.date { label(date, inset, height - 62, usable, 9, color: secondary, maxLines: 2) }
            UIImage(named: "LaunchMark")?.draw(in: CGRect(x: inset - 9, y: height - 34, width: 36, height: 36))
            label("Forced Rep", inset + 26, height - 21, usable - 26, 10, bold: true)
        }
    }

    private static func drawMuscles(_ card: SocialCardContent, rect: CGRect) {
        guard let catalog = ExerciseMuscleCatalog.shared, let context = UIGraphicsGetCurrentContext() else { return }
        let figureWidth = min(rect.width / 2, rect.height * catalog.width / catalog.height + 12)
        let groupLeft = rect.minX + (rect.width - figureWidth * 2) / 2
        for (index, view) in ["front", "back"].enumerated() {
            guard let anatomy = catalog.views[view], let image = ExerciseMuscleCatalog.images[view] else { continue }
            let scale = min(figureWidth / catalog.width, rect.height / catalog.height)
            context.saveGState()
            context.translateBy(x: groupLeft + CGFloat(index) * figureWidth + (figureWidth - catalog.width * scale) / 2, y: rect.minY)
            context.scaleBy(x: scale, y: scale)
            image.draw(in: CGRect(x: 0, y: 0, width: catalog.width, height: catalog.height))
            context.translateBy(x: -anatomy.offsetX, y: 0)
            for (muscle, path) in catalog.parsedPaths(for: view) where card.primary.contains(muscle) || card.secondary.contains(muscle) {
                let color = card.primary.contains(muscle) ? UIColor(palette.purple) : UIColor(red: 142/255, green: 169/255, blue: 244/255, alpha: 1)
                context.setBlendMode(.color); context.setFillColor(color.withAlphaComponent(0.7).cgColor)
                context.addPath(path); context.fillPath()
            }
            context.restoreGState()
        }
    }
}
