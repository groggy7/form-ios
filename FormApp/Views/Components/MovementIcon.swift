import SwiftUI
import UIKit

// MARK: - Animation Clock (Shared singleton on main runloop)
public final class MovementAnimationClock: ObservableObject {
    public static let shared = MovementAnimationClock()

    @Published public private(set) var currentFrame: Int = 0

    private var pos: Int = 0
    private let sequence: [Int] = [0, 1, 2, 1]
    private let durations: [TimeInterval] = [0.65, 0.40, 0.65, 0.40]
    private var timer: Timer?

    public init() {
        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.start()
            }
        }
    }

    public func start() {
        guard timer == nil else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        currentFrame = sequence[pos]
        let delay = durations[pos]
        pos = (pos + 1) % sequence.count

        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.timer = nil
            self?.scheduleNext()
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }
}

// MARK: - Sprite Definition
public struct MovementSprite {
    public let imageName: String
    public let top: CGFloat
    public let bottom: CGFloat
    public let atlasHeight: CGFloat
    public let atlasWidth: CGFloat
    public let frameStarts: [CGFloat]?
    public let frameWidth: CGFloat?

    public init(
        imageName: String,
        top: CGFloat,
        bottom: CGFloat,
        atlasHeight: CGFloat = 1254,
        atlasWidth: CGFloat = 1254,
        frameStarts: [CGFloat]? = nil,
        frameWidth: CGFloat? = nil
    ) {
        self.imageName = imageName
        self.top = top
        self.bottom = bottom
        self.atlasHeight = atlasHeight
        self.atlasWidth = atlasWidth
        self.frameStarts = frameStarts
        self.frameWidth = frameWidth
    }
}

// MARK: - Sliced Frame Cache
public enum MovementFrameCache {
    private static var cache: [String: UIImage] = [:]
    private static var atlasCache: [String: UIImage] = [:]
    private static let lock = NSLock()

    public static func getFrame(for sprite: MovementSprite, frame: Int) -> UIImage? {
        let key = "\(sprite.imageName):\(Int(sprite.top)):\(Int(sprite.bottom)):\(frame)"

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }

        let atlas: UIImage? = {
            if let img = atlasCache[sprite.imageName] {
                return img
            }
            if let img = UIImage(named: sprite.imageName) {
                atlasCache[sprite.imageName] = img
                return img
            }
            return nil
        }()
        lock.unlock()

        guard let sourceAtlas = atlas, let cgImage = sourceAtlas.cgImage else { return nil }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        let top = sprite.top * pixelHeight / sprite.atlasHeight
        let bottom = sprite.bottom * pixelHeight / sprite.atlasHeight
        let height = max(1, bottom - top)

        let frameStart: CGFloat = {
            if let starts = sprite.frameStarts, starts.indices.contains(frame) {
                return starts[frame]
            }
            return CGFloat(frame) * sprite.atlasWidth / 3.0
        }()
        let sourceLeft = frameStart * pixelWidth / sprite.atlasWidth
        let frameWidthVal = sprite.frameWidth ?? (sprite.atlasWidth / 3.0)
        let sourceWidth = frameWidthVal * pixelWidth / sprite.atlasWidth

        let cropRect = CGRect(x: sourceLeft, y: top, width: sourceWidth, height: height)

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let result = UIImage(cgImage: cropped)

        lock.lock()
        cache[key] = result
        lock.unlock()

        return result
    }
}

// MARK: - MovementIcon View
public struct MovementIcon: View {
    let name: String
    let size: CGFloat
    let large: Bool
    let movementType: MovementType
    let movementAssetId: String?
    let allowCategoryFallback: Bool

    @ObservedObject private var clock = MovementAnimationClock.shared

    public init(
        name: String,
        size: CGFloat = 56,
        large: Bool = false,
        movementType: MovementType = .other,
        movementAssetId: String? = nil,
        allowCategoryFallback: Bool = true
    ) {
        self.name = name
        self.size = size
        self.large = large
        self.movementType = movementType
        self.movementAssetId = movementAssetId
        self.allowCategoryFallback = allowCategoryFallback
    }

    public var body: some View {
        let finalSize: CGFloat = large ? 108 : size

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.surface)

            MovementIllustration(
                name: name,
                movementType: movementType,
                movementAssetId: movementAssetId,
                allowCategoryFallback: allowCategoryFallback
            )
            .padding(3)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: finalSize, height: finalSize)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.border.opacity(0.4), lineWidth: 1)
        )
    }

    public func resolveSprite() -> MovementSprite? {
        if let assetId = movementAssetId, let s = MovementIcon.movementAssetSprite(assetId) {
            return s
        }
        if allowCategoryFallback {
            return MovementIcon.categorySprite(movementType)
        }
        return nil
    }
}

public struct MovementIllustration: View {
    let name: String
    let movementType: MovementType
    let movementAssetId: String?
    let allowCategoryFallback: Bool

    @ObservedObject private var clock = MovementAnimationClock.shared

    public init(
        name: String,
        movementType: MovementType = .other,
        movementAssetId: String? = nil,
        allowCategoryFallback: Bool = true
    ) {
        self.name = name
        self.movementType = movementType
        self.movementAssetId = movementAssetId
        self.allowCategoryFallback = allowCategoryFallback
    }

    public var body: some View {
        let sprite = resolveSprite()
        let activeFrame = UIAccessibility.isReduceMotionEnabled ? 1 : clock.currentFrame

        if let sprite = sprite, let frameImg = MovementFrameCache.getFrame(for: sprite, frame: activeFrame) {
            Image(uiImage: frameImg)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 36))
                .foregroundColor(AppColors.muted)
        }
    }

    public func resolveSprite() -> MovementSprite? {
        if let assetId = movementAssetId, let s = MovementIcon.movementAssetSprite(assetId) {
            return s
        }
        if allowCategoryFallback {
            return MovementIcon.categorySprite(movementType)
        }
        return nil
    }
}

public extension MovementIcon {
    static func categorySprite(_ type: MovementType) -> MovementSprite? {
        switch type {
        case .press: return MovementSprite(imageName: "anatomy_compound", top: 0, bottom: 385)
        case .pullUp: return MovementSprite(imageName: "anatomy_compound", top: 385, bottom: 815)
        case .row: return MovementSprite(imageName: "anatomy_compound", top: 815, bottom: 1254)
        case .shoulderRaise: return MovementSprite(imageName: "anatomy_isolation", top: 0, bottom: 414)
        case .curl: return MovementSprite(imageName: "anatomy_isolation", top: 414, bottom: 815)
        case .triceps: return MovementSprite(imageName: "anatomy_isolation", top: 815, bottom: 1254)
        case .squat: return MovementSprite(imageName: "anatomy_lower", top: 0, bottom: 415)
        case .hinge: return MovementSprite(imageName: "anatomy_lower", top: 415, bottom: 816)
        case .lunge: return MovementSprite(imageName: "anatomy_lower", top: 816, bottom: 1254)
        case .calf: return MovementSprite(imageName: "anatomy_core", top: 0, bottom: 418)
        case .core: return MovementSprite(imageName: "anatomy_core", top: 418, bottom: 836)
        case .other, .conditioning, .boxing: return nil
        }
    }

    static func movementAssetSprite(_ id: String) -> MovementSprite? {
        switch id {
        case "jump-rope":
            return MovementSprite(imageName: "anatomy_jump_rope", top: 0, bottom: 1024, atlasHeight: 1024, atlasWidth: 1536)
        case "weighted-pull-up":
            return MovementSprite(imageName: "anatomy_batch_01_upper", top: 0, bottom: 556)
        case "chest-supported-dumbbell-row":
            return MovementSprite(imageName: "anatomy_batch_01_upper", top: 556, bottom: 938, frameStarts: [0, 386, 797], frameWidth: 382)
        case "push-up":
            return MovementSprite(imageName: "anatomy_batch_01_upper", top: 938, bottom: 1254)
        case "barbell-front-squat":
            return MovementSprite(imageName: "anatomy_batch_01_lower", top: 0, bottom: 419)
        case "trap-bar-deadlift":
            return MovementSprite(imageName: "anatomy_batch_01_lower", top: 419, bottom: 821)
        case "seated-leg-curl":
            return MovementSprite(imageName: "anatomy_batch_01_lower", top: 821, bottom: 1254)
        case "ab-wheel-rollout":
            return MovementSprite(imageName: "anatomy_batch_01_accessory", top: 0, bottom: 371, atlasHeight: 371)
        case "cable-lateral-raise":
            return MovementSprite(imageName: "anatomy_cable_lateral_raise", top: 0, bottom: 456, atlasHeight: 456)
        case "overhead-cable-triceps-extension":
            return MovementSprite(imageName: "anatomy_overhead_cable_triceps_extension", top: 0, bottom: 887, atlasHeight: 887, atlasWidth: 1774)
        case "side-plank":
            return MovementSprite(imageName: "anatomy_batch_02_core", top: 0, bottom: 444)
        case "dead-bug":
            return MovementSprite(imageName: "anatomy_dead_bug", top: 0, bottom: 390, atlasHeight: 390)
        case "hollow-body-hold":
            return MovementSprite(imageName: "anatomy_batch_02_core", top: 834, bottom: 1254)
        case "reverse-crunch":
            return MovementSprite(imageName: "anatomy_batch_02_bodyweight", top: 0, bottom: 463)
        case "sliding-hamstring-curl":
            return MovementSprite(imageName: "anatomy_batch_02_bodyweight", top: 463, bottom: 795)
        case "pike-push-up":
            return MovementSprite(imageName: "anatomy_batch_02_bodyweight", top: 795, bottom: 1254)
        case "band-face-pull":
            return MovementSprite(imageName: "anatomy_batch_02_equipment", top: 0, bottom: 405)
        case "incline-dumbbell-press":
            return MovementSprite(imageName: "anatomy_batch_02_equipment", top: 405, bottom: 811)
        case "dumbbell-step-up":
            return MovementSprite(imageName: "anatomy_batch_02_equipment", top: 811, bottom: 1254)
        case "barbell-romanian-deadlift":
            return MovementSprite(imageName: "anatomy_batch_03_lower", top: 0, bottom: 418)
        case "kettlebell-goblet-squat":
            return MovementSprite(imageName: "anatomy_batch_03_lower", top: 418, bottom: 836)
        case "leg-press-45-degree":
            return MovementSprite(imageName: "anatomy_batch_03_lower", top: 836, bottom: 1254)
        case "barbell-bench-press":
            return MovementSprite(imageName: "anatomy_batch_03_upper", top: 0, bottom: 418)
        case "dumbbell-lateral-raise":
            return MovementSprite(imageName: "anatomy_batch_03_upper", top: 418, bottom: 836)
        case "rope-triceps-pressdown":
            return MovementSprite(imageName: "anatomy_batch_03_upper", top: 836, bottom: 1254)
        case "single-leg-calf-raise":
            return MovementSprite(imageName: "anatomy_batch_03_accessory", top: 0, bottom: 418)
        case "standing-machine-calf-raise":
            return MovementSprite(imageName: "anatomy_batch_03_accessory", top: 418, bottom: 836)
        case "hanging-knee-raise":
            return MovementSprite(imageName: "anatomy_batch_03_accessory", top: 836, bottom: 1254)
        case "barbell-back-squat":
            return MovementSprite(imageName: "anatomy_batch_04_lower", top: 0, bottom: 418)
        case "conventional-barbell-deadlift":
            return MovementSprite(imageName: "anatomy_batch_04_lower", top: 418, bottom: 806)
        case "dumbbell-romanian-deadlift":
            return MovementSprite(imageName: "anatomy_batch_04_lower", top: 806, bottom: 1254)
        case "standing-barbell-overhead-press":
            return MovementSprite(imageName: "anatomy_batch_04_upper", top: 0, bottom: 432)
        case "dumbbell-floor-press":
            return MovementSprite(imageName: "anatomy_batch_04_upper", top: 432, bottom: 783)
        case "dumbbell-hammer-curl":
            return MovementSprite(imageName: "anatomy_batch_04_upper", top: 783, bottom: 1254)
        case "straight-bar-cable-triceps-pressdown":
            return MovementSprite(imageName: "anatomy_batch_04_accessory", top: 0, bottom: 418)
        case "seated-machine-calf-raise":
            return MovementSprite(imageName: "anatomy_batch_04_accessory", top: 418, bottom: 833)
        case "kneeling-cable-crunch":
            return MovementSprite(imageName: "anatomy_batch_04_accessory", top: 833, bottom: 1254)
        case "dumbbell-bench-press":
            return MovementSprite(imageName: "anatomy_batch_05_upper", top: 0, bottom: 418)
        case "one-arm-dumbbell-row":
            return MovementSprite(imageName: "anatomy_batch_05_upper", top: 418, bottom: 749)
        case "lat-pulldown":
            return MovementSprite(imageName: "anatomy_batch_05_upper", top: 810, bottom: 1254)
        case "rear-foot-elevated-split-squat":
            return MovementSprite(imageName: "anatomy_batch_05_lower", top: 0, bottom: 421)
        case "leg-extension":
            return MovementSprite(imageName: "anatomy_batch_05_lower", top: 421, bottom: 820)
        case "lying-leg-curl":
            return MovementSprite(imageName: "anatomy_batch_05_lower", top: 836, bottom: 1254)
        case "pec-deck-fly":
            return MovementSprite(imageName: "anatomy_batch_05_accessory", top: 0, bottom: 418)
        case "ez-bar-curl":
            return MovementSprite(imageName: "anatomy_batch_05_accessory", top: 418, bottom: 857)
        case "barbell-hip-thrust":
            return MovementSprite(imageName: "anatomy_batch_05_accessory", top: 857, bottom: 1254)
        case "barbell-row":
            return MovementSprite(imageName: "anatomy_batch_06_upper", top: 0, bottom: 409)
        case "incline-barbell-bench-press":
            return MovementSprite(imageName: "anatomy_batch_06_upper", top: 409, bottom: 814)
        case "incline-dumbbell-curl":
            return MovementSprite(imageName: "anatomy_batch_06_upper", top: 814, bottom: 1254)
        case "kettlebell-swing":
            return MovementSprite(imageName: "anatomy_batch_06_athletic", top: 0, bottom: 414)
        case "farmer-carry":
            return MovementSprite(imageName: "anatomy_batch_06_athletic", top: 414, bottom: 788)
        case "push-press":
            return MovementSprite(imageName: "anatomy_batch_06_athletic", top: 788, bottom: 1254)
        case "pallof-press":
            return MovementSprite(
                imageName: "anatomy_pallof_press",
                top: 0,
                bottom: 887,
                atlasHeight: 887,
                atlasWidth: 1774,
                frameStarts: [0, 591, 1182],
                frameWidth: 591
            )
        default:
            return nil
        }
    }
}
