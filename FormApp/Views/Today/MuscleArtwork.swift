import SwiftUI
import CoreGraphics

public struct MuscleArtwork: View {
    let view: BodyView
    let muscles: [MuscleGroup]
    var alpha: CGFloat = 1.0
    var centered: Bool = false

    public init(view: BodyView, muscles: [MuscleGroup], alpha: CGFloat = 1.0, centered: Bool = false) {
        self.view = view
        self.muscles = muscles
        self.alpha = alpha
        self.centered = centered
    }

    public var body: some View {
        let matchingPaths = MuscleMasks.paths(for: view).filter { muscles.contains($0.key) }
        let isLegs = (view == .legsFront || view == .legsBack)
        let tint = isLegs ? Color(hex: 0x8EA9F4) : Color(hex: 0xBD9CF2)

        Canvas { context, size in
            guard size.width > 0 && size.height > 0 else { return }

            let athleteCenterX: CGFloat
            switch view {
            case .legsFront: athleteCenterX = 835
            case .legsBack: athleteCenterX = 855
            case .back: athleteCenterX = 870
            case .front: athleteCenterX = 866
            }

            let scale = max(size.width, size.height) / MuscleMasks.viewport
            let width = MuscleMasks.viewport * scale
            let left = centered ? ((size.width / 2.0) - (athleteCenterX * scale)) : ((size.width - width) / 2.0)
            let top = (size.height - width) * 0.41

            var rootContext = context
            rootContext.opacity = Double(alpha)
            rootContext.clip(to: Path(CGRect(origin: .zero, size: size)))
            rootContext.translateBy(x: left, y: top)
            rootContext.scaleBy(x: scale, y: scale)

            // Draw base physique bitmap
            if let uiImage = UIImage(named: view.artworkName) {
                rootContext.draw(
                    Image(uiImage: uiImage),
                    in: CGRect(x: 0, y: 0, width: MuscleMasks.viewport, height: MuscleMasks.viewport)
                )
            }

            // Draw each muscle group mask
            let gradient = Gradient(stops: [
                .init(color: tint.opacity(0.78), location: 0.0),
                .init(color: tint.opacity(0.48), location: 1.0)
            ])

            let startPoint: CGPoint
            let endPoint: CGPoint
            if view == .back {
                startPoint = CGPoint(x: 866, y: 250)
                endPoint = CGPoint(x: 866, y: 1000)
            } else {
                startPoint = CGPoint(x: 620, y: 250)
                endPoint = CGPoint(x: 1050, y: 1000)
            }

            for (_, cgPath) in matchingPaths {
                let p = Path(cgPath)

                // Hue/saturation tint retaining original photo luminance
                var fillContext = rootContext
                fillContext.blendMode = .color
                fillContext.fill(
                    p,
                    with: .linearGradient(
                        gradient,
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                )

                // Subtle outline stroke
                rootContext.stroke(
                    p,
                    with: .color(tint.opacity(0.24)),
                    lineWidth: 1.2
                )
            }
        }
    }
}
