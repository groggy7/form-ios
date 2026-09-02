import SwiftUI

public struct MovementIcon: View {
    let name: String
    let size: CGFloat
    let movementType: MovementType
    let movementAssetId: String?

    public init(
        name: String,
        size: CGFloat = 56,
        movementType: MovementType = .other,
        movementAssetId: String? = nil
    ) {
        self.name = name
        self.size = size
        self.movementType = movementType
        self.movementAssetId = movementAssetId
    }

    public var body: some View {
        let imageName = resolveImageName()

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.surface)

            if let img = imageName {
                Image(img)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundColor(AppColors.muted)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppColors.border.opacity(0.4), lineWidth: 1)
        )
    }

    private func resolveImageName() -> String? {
        if let assetId = movementAssetId {
            switch assetId {
            case "cable-lateral-raise": return "anatomy_cable_lateral_raise"
            case "dead-bug": return "anatomy_dead_bug"
            case "jump-rope": return "anatomy_jump_rope"
            case "overhead-cable-triceps-extension": return "anatomy_overhead_cable_triceps_extension"
            case "pallof-press": return "anatomy_pallof_press"
            case "barbell-bench-press", "dumbbell-lateral-raise", "rope-triceps-pressdown":
                return "anatomy_batch_03_upper"
            case "dumbbell-bench-press", "one-arm-dumbbell-row", "lat-pulldown":
                return "anatomy_batch_05_upper"
            case "barbell-row", "incline-barbell-bench-press", "incline-dumbbell-curl":
                return "anatomy_batch_06_upper"
            case "incline-dumbbell-press", "dumbbell-step-up", "band-face-pull":
                return "anatomy_batch_02_equipment"
            case "standing-barbell-overhead-press", "dumbbell-floor-press", "dumbbell-hammer-curl":
                return "anatomy_batch_04_upper"
            case "barbell-back-squat", "conventional-barbell-deadlift", "dumbbell-romanian-deadlift":
                return "anatomy_batch_04_lower"
            case "rear-foot-elevated-split-squat", "leg-extension", "lying-leg-curl":
                return "anatomy_batch_05_lower"
            case "barbell-romanian-deadlift", "kettlebell-goblet-squat", "leg-press-45-degree":
                return "anatomy_batch_03_lower"
            case "barbell-front-squat", "trap-bar-deadlift", "seated-leg-curl":
                return "anatomy_batch_01_lower"
            case "weighted-pull-up", "chest-supported-dumbbell-row", "push-up":
                return "anatomy_batch_01_upper"
            case "pec-deck-fly", "ez-bar-curl", "barbell-hip-thrust":
                return "anatomy_batch_05_accessory"
            case "straight-bar-cable-triceps-pressdown", "seated-machine-calf-raise", "kneeling-cable-crunch":
                return "anatomy_batch_04_accessory"
            case "single-leg-calf-raise", "standing-machine-calf-raise", "hanging-knee-raise":
                return "anatomy_batch_03_accessory"
            case "kettlebell-swing", "farmer-carry", "push-press":
                return "anatomy_batch_06_athletic"
            case "side-plank", "hollow-body-hold":
                return "anatomy_batch_02_core"
            case "reverse-crunch", "sliding-hamstring-curl", "pike-push-up":
                return "anatomy_batch_02_bodyweight"
            case "ab-wheel-rollout":
                return "anatomy_batch_01_accessory"
            default:
                break
            }
        }

        switch movementType {
        case .press, .pullUp, .row:
            return "anatomy_compound"
        case .shoulderRaise, .curl, .triceps:
            return "anatomy_isolation"
        case .squat, .hinge, .lunge:
            return "anatomy_lower"
        case .calf, .core:
            return "anatomy_core"
        case .other, .conditioning, .boxing:
            return nil
        }
    }
}
