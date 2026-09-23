import SwiftUI

public enum RepMaxFormula: String, CaseIterable, Identifiable {
    case brzycki = "brzycki"
    case epley = "epley"

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .brzycki: return "form_lab.formula.brzycki"
        case .epley: return "form_lab.formula.epley"
        }
    }
}

public struct RepMaxTarget: Equatable, Identifiable {
    public var id: Int { reps }
    public let reps: Int
    public let estimatedWeightKg: Double
    public let percentageOf1RM: Double

    public init(reps: Int, estimatedWeightKg: Double, percentageOf1RM: Double) {
        self.reps = reps
        self.estimatedWeightKg = estimatedWeightKg
        self.percentageOf1RM = percentageOf1RM
    }
}

public struct ExerciseRepMaxSummary: Equatable, Identifiable {
    public var id: String { exerciseId }
    public let exerciseId: String
    public let exerciseName: String
    public let bestWeightKg: Double
    public let bestReps: Int
    public let achievedDate: String?
    public let estimated1rmKg: Double
    public let formula: RepMaxFormula
    public let targets: [RepMaxTarget]

    public init(
        exerciseId: String,
        exerciseName: String,
        bestWeightKg: Double,
        bestReps: Int,
        achievedDate: String?,
        estimated1rmKg: Double,
        formula: RepMaxFormula,
        targets: [RepMaxTarget]
    ) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.bestWeightKg = bestWeightKg
        self.bestReps = bestReps
        self.achievedDate = achievedDate
        self.estimated1rmKg = estimated1rmKg
        self.formula = formula
        self.targets = targets
    }
}

public enum StrengthCurveTimeframe: String, CaseIterable, Identifiable {
    case threeMonths = "3m"
    case sixMonths = "6m"
    case oneYear = "1y"
    case allTime = "all"

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .threeMonths: return "form_lab.timeframe.3m"
        case .sixMonths: return "form_lab.timeframe.6m"
        case .oneYear: return "form_lab.timeframe.1y"
        case .allTime: return "form_lab.timeframe.all"
        }
    }

    public var days: Int? {
        switch self {
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        case .allTime: return nil
        }
    }
}

public struct StrengthDataPoint: Equatable, Identifiable {
    public var id: String { "\(dateString)_\(estimated1rmKg)" }
    public let date: Date
    public let dateString: String
    public let topWeightKg: Double
    public let topReps: Int
    public let estimated1rmKg: Double
    public let workoutTitle: String

    public init(
        date: Date,
        dateString: String,
        topWeightKg: Double,
        topReps: Int,
        estimated1rmKg: Double,
        workoutTitle: String
    ) {
        self.date = date
        self.dateString = dateString
        self.topWeightKg = topWeightKg
        self.topReps = topReps
        self.estimated1rmKg = estimated1rmKg
        self.workoutTitle = workoutTitle
    }
}

public struct LongitudinalCurveReport: Equatable {
    public let exerciseName: String
    public let points: [StrengthDataPoint]
    public let start1rmKg: Double?
    public let current1rmKg: Double?
    public let peak1rmKg: Double?
    public let deltaKg: Double
    public let percentageGain: Double

    public init(
        exerciseName: String,
        points: [StrengthDataPoint],
        start1rmKg: Double?,
        current1rmKg: Double?,
        peak1rmKg: Double?,
        deltaKg: Double,
        percentageGain: Double
    ) {
        self.exerciseName = exerciseName
        self.points = points
        self.start1rmKg = start1rmKg
        self.current1rmKg = current1rmKg
        self.peak1rmKg = peak1rmKg
        self.deltaKg = deltaKg
        self.percentageGain = percentageGain
    }
}

public enum AntagonistStatus: String, CaseIterable {
    case optimal = "optimal"
    case primaryDominant = "primary_dominant"
    case antagonistDominant = "antagonist_dominant"
    case insufficientData = "insufficient_data"

    public var labelKey: String {
        switch self {
        case .optimal: return "form_lab.balance.optimal"
        case .primaryDominant: return "form_lab.balance.primary_dominant"
        case .antagonistDominant: return "form_lab.balance.antagonist_dominant"
        case .insufficientData: return "form_lab.balance.insufficient_data"
        }
    }
}

public struct AntagonistRatio: Equatable, Identifiable {
    public let id: String
    public let titleKey: String
    public let primaryLabelKey: String
    public let antagonistLabelKey: String
    public let primarySets: Int
    public let antagonistSets: Int
    public let ratio: Double?
    public let optimalMin: Double
    public let optimalMax: Double
    public let status: AntagonistStatus
    public let alertMessageKey: String
    public let recommendationKey: String

    public init(
        id: String,
        titleKey: String,
        primaryLabelKey: String,
        antagonistLabelKey: String,
        primarySets: Int,
        antagonistSets: Int,
        ratio: Double?,
        optimalMin: Double,
        optimalMax: Double,
        status: AntagonistStatus,
        alertMessageKey: String,
        recommendationKey: String
    ) {
        self.id = id
        self.titleKey = titleKey
        self.primaryLabelKey = primaryLabelKey
        self.antagonistLabelKey = antagonistLabelKey
        self.primarySets = primarySets
        self.antagonistSets = antagonistSets
        self.ratio = ratio
        self.optimalMin = optimalMin
        self.optimalMax = optimalMax
        self.status = status
        self.alertMessageKey = alertMessageKey
        self.recommendationKey = recommendationKey
    }
}

public struct AntagonistBalanceReport: Equatable {
    public let pushPull: AntagonistRatio
    public let quadHamstring: AntagonistRatio
    public let upperLower: AntagonistRatio
    public let totalWorkingSets: Int
    public let unclassifiedWorkingSets: Int

    public init(
        pushPull: AntagonistRatio,
        quadHamstring: AntagonistRatio,
        upperLower: AntagonistRatio,
        totalWorkingSets: Int,
        unclassifiedWorkingSets: Int = 0
    ) {
        self.pushPull = pushPull
        self.quadHamstring = quadHamstring
        self.upperLower = upperLower
        self.totalWorkingSets = totalWorkingSets
        self.unclassifiedWorkingSets = unclassifiedWorkingSets
    }
}

public struct CloudMirrorStatus: Equatable {
    public let isEnabled: Bool
    public let isEncrypted: Bool
    public let lastSyncTimestamp: TimeInterval?
    public let snapshotSizeBytes: Int64?
    public let providerName: String
    public let isCloudConnected: Bool
    public let isUploadPending: Bool

    public init(
        isEnabled: Bool,
        isEncrypted: Bool = false,
        lastSyncTimestamp: TimeInterval?,
        snapshotSizeBytes: Int64?,
        providerName: String,
        isCloudConnected: Bool = false,
        isUploadPending: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.isEncrypted = isEncrypted
        self.lastSyncTimestamp = lastSyncTimestamp
        self.snapshotSizeBytes = snapshotSizeBytes
        self.providerName = providerName
        self.isCloudConnected = isCloudConnected
        self.isUploadPending = isUploadPending
    }
}
