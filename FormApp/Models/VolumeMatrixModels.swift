import SwiftUI

public enum VolumeZone: String, CaseIterable {
    case underMev = "under_mev"
    case progressive = "progressive"
    case optimalMav = "optimal_mav"
    case highFatigue = "high_fatigue"
    case overMrv = "over_mrv"

    public var titleKey: String {
        switch self {
        case .underMev: return "matrix.zone.under_mev"
        case .progressive: return "matrix.zone.progressive"
        case .optimalMav: return "matrix.zone.optimal_mav"
        case .highFatigue: return "matrix.zone.high_fatigue"
        case .overMrv: return "matrix.zone.over_mrv"
        }
    }

    public var descriptionKey: String {
        switch self {
        case .underMev: return "matrix.zone.under_mev_desc"
        case .progressive: return "matrix.zone.progressive_desc"
        case .optimalMav: return "matrix.zone.optimal_mav_desc"
        case .highFatigue: return "matrix.zone.high_fatigue_desc"
        case .overMrv: return "matrix.zone.over_mrv_desc"
        }
    }

    public var color: Color {
        switch self {
        case .underMev: return Color(hex: 0x62717E)
        case .progressive: return Color(hex: 0x12D8D2)
        case .optimalMav: return Color(hex: 0x20D791)
        case .highFatigue: return Color(hex: 0xB18AFF)
        case .overMrv: return Color(hex: 0xFF897B)
        }
    }

    public var badgeBgColor: Color {
        switch self {
        case .underMev: return Color(hex: 0x1E252B)
        case .progressive: return Color(hex: 0x0C292B)
        case .optimalMav: return Color(hex: 0x142D29)
        case .highFatigue: return Color(hex: 0x28203D)
        case .overMrv: return Color(hex: 0x331818)
        }
    }
}

public struct VolumeLandmark: Equatable {
    public let muscleKey: String
    public let mev: Float
    public let mavMin: Float
    public let mavMax: Float
    public let mrv: Float

    public func zone(for sets: Float) -> VolumeZone {
        if sets < mev {
            return .underMev
        } else if sets < mavMin {
            return .progressive
        } else if sets <= mavMax {
            return .optimalMav
        } else if sets <= mrv {
            return .highFatigue
        } else {
            return .overMrv
        }
    }

    public static let defaults: [String: VolumeLandmark] = [
        "chest": VolumeLandmark(muscleKey: "chest", mev: 6, mavMin: 10, mavMax: 18, mrv: 22),
        "front-delts": VolumeLandmark(muscleKey: "front-delts", mev: 4, mavMin: 6, mavMax: 12, mrv: 16),
        "rear-delts": VolumeLandmark(muscleKey: "rear-delts", mev: 8, mavMin: 12, mavMax: 20, mrv: 25),
        "biceps": VolumeLandmark(muscleKey: "biceps", mev: 8, mavMin: 12, mavMax: 20, mrv: 24),
        "triceps": VolumeLandmark(muscleKey: "triceps", mev: 6, mavMin: 10, mavMax: 18, mrv: 22),
        "upper-back": VolumeLandmark(muscleKey: "upper-back", mev: 8, mavMin: 12, mavMax: 20, mrv: 25),
        "lats": VolumeLandmark(muscleKey: "lats", mev: 8, mavMin: 12, mavMax: 20, mrv: 24),
        "abs": VolumeLandmark(muscleKey: "abs", mev: 6, mavMin: 10, mavMax: 18, mrv: 22),
        "obliques": VolumeLandmark(muscleKey: "obliques", mev: 4, mavMin: 8, mavMax: 14, mrv: 18),
        "quads": VolumeLandmark(muscleKey: "quads", mev: 6, mavMin: 10, mavMax: 16, mrv: 20),
        "hamstrings": VolumeLandmark(muscleKey: "hamstrings", mev: 6, mavMin: 10, mavMax: 16, mrv: 20),
        "glutes": VolumeLandmark(muscleKey: "glutes", mev: 4, mavMin: 8, mavMax: 16, mrv: 20),
        "calves": VolumeLandmark(muscleKey: "calves", mev: 8, mavMin: 12, mavMax: 20, mrv: 25)
    ]

    public static func forMuscle(_ key: String) -> VolumeLandmark {
        defaults[key] ?? VolumeLandmark(muscleKey: key, mev: 6, mavMin: 10, mavMax: 18, mrv: 22)
    }
}

public struct MuscleVolumeContribution: Identifiable, Equatable {
    public var id: String { "\(exerciseName)_\(date ?? "")_\(isPrimary)" }
    public let exerciseName: String
    public let completedSets: Int
    public let effectiveSets: Float
    public let isPrimary: Bool
    public let date: String?
}

public struct MuscleVolumeSummary: Equatable {
    public let muscleKey: String
    public let localizedName: String
    public let totalEffectiveSets: Float
    public let directSets: Int
    public let indirectSets: Int
    public let landmarks: VolumeLandmark
    public let zone: VolumeZone
    public let contributions: [MuscleVolumeContribution]
    public let defaultView: String
}

public struct VolumeMatrixReport: Equatable {
    public let weekKey: String
    public let isPlannedRoutine: Bool
    public let muscleSummaries: [String: MuscleVolumeSummary]
    public let totalEffectiveSets: Float
    public let optimalMuscleCount: Int
    public let underTrainedCount: Int
    public let highFatigueCount: Int
}
