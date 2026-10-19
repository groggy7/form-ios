import Foundation

/// Guided tours, sample previews and one-time tips. The contract, copy and saved-state rules
/// live in gym/docs/design/app-tour.md; Android mirrors these ids and keys.
public enum TourKind {
    case screen, preview, tip
}

public enum TourId: String, CaseIterable, Codable {
    case home, plan, library, exercise, progress, programs, workout
    case volumeMatrix = "volume_matrix"
    case repLab = "rep_lab"
    case dayStatus = "day_status"
    case restTimer = "rest_timer"

    public var kind: TourKind {
        switch self {
        case .volumeMatrix, .repLab: return .preview
        case .dayStatus, .restTimer: return .tip
        default: return .screen
        }
    }

    public var version: Int { 1 }

    public var storageKey: String {
        (kind == .tip ? "tip_seen_" : "tour_seen_") + rawValue + "_v\(version)"
    }

    public static var screenToursAndTips: Set<TourId> { Set(allCases.filter { $0.kind != .preview }) }
}

/// Title and body keys; `args` maps a body placeholder to the translation key that fills it.
public struct TourText: Equatable {
    public let titleKey: String
    public let bodyKey: String
    public let args: [String: String]

    public init(titleKey: String, bodyKey: String, args: [String: String] = [:]) {
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.args = args
    }
}

/// One bubble. `targetId` names a registered target; nil centres the bubble (the Premium step).
/// A target may report flags, and the first matching variant replaces `text`.
public struct TourStep: Equatable {
    public let id: String
    public let targetId: String?
    public let text: TourText
    public let variants: [(flag: String, text: TourText)]
    public let isPremium: Bool

    public init(id: String, targetId: String?, text: TourText, variants: [(flag: String, text: TourText)] = [], isPremium: Bool = false) {
        self.id = id
        self.targetId = targetId
        self.text = text
        self.variants = variants
        self.isPremium = isPremium
    }

    public func text(for flags: Set<String>) -> TourText {
        variants.first { flags.contains($0.flag) }?.text ?? text
    }

    public static func == (lhs: TourStep, rhs: TourStep) -> Bool {
        lhs.id == rhs.id && lhs.targetId == rhs.targetId && lhs.text == rhs.text && lhs.isPremium == rhs.isPremium
    }
}

/// What has been seen. Only screen tours count toward the skip limit.
public struct TourProgress: Equatable {
    public static let maxSkips = 2
    public static let stateVersion = 1

    public var seen: Set<TourId>
    public var skipCount: Int
    public var existingUser: Bool

    public init(seen: Set<TourId> = [], skipCount: Int = 0, existingUser: Bool = false) {
        self.seen = seen
        self.skipCount = skipCount
        self.existingUser = existingUser
    }

    /// Previews start for locked users whatever their history, and for Premium users only on new installs.
    public func shouldStart(_ id: TourId, featureUnlocked: Bool = false) -> Bool {
        switch id.kind {
        case .screen: return !seen.contains(id) && skipCount < Self.maxSkips
        case .tip: return !seen.contains(id)
        case .preview: return !seen.contains(id) && (!featureUnlocked || !existingUser)
        }
    }

    public func finished(_ id: TourId) -> TourProgress {
        var next = self
        next.seen.insert(id)
        return next
    }

    public func skipped(_ id: TourId) -> TourProgress {
        var next = finished(id)
        if id.kind == .screen { next.skipCount += 1 }
        return next
    }

    /// A returning user: no screen tours or tips; previews follow `shouldStart`.
    public func returningUser() -> TourProgress {
        var next = self
        next.seen.formUnion(TourId.screenToursAndTips)
        next.existingUser = true
        return next
    }
}

public enum TourCatalog {
    public static let labRepMaxStep = "lab.repmax"
    public static let labCurvesStep = "lab.curves"
    public static let labBalanceStep = "lab.balance"

    private static func text(_ key: String, _ args: [String: String] = [:]) -> TourText {
        TourText(titleKey: "\(key).title", bodyKey: "\(key).body", args: args)
    }

    private static let workoutArgs = ["start": "plan.startWorkout", "front": "anatomy.front", "back": "anatomy.back"]

    /// Every step a tour can show; `locked` adds the Premium step to the sample previews.
    public static func steps(_ id: TourId, locked: Bool = false) -> [TourStep] {
        switch id {
        case .home:
            return [
                TourStep(id: "home.days", targetId: "home.days", text: text("tour.home.days"),
                         variants: [("scroll", TourText(titleKey: "tour.home.days.title", bodyKey: "tour.home.days.bodyScroll"))]),
                TourStep(id: "home.workout", targetId: "home.hero", text: text("tour.home.workout", workoutArgs),
                         variants: [("rest", text("tour.home.rest")),
                                    ("views", TourText(titleKey: "tour.home.workout.title", bodyKey: "tour.home.workout.bodyViews", args: workoutArgs))]),
                TourStep(id: "home.week", targetId: "home.week", text: text("tour.home.week")),
                TourStep(id: "home.exercises", targetId: "home.exercises", text: text("tour.home.exercises")),
                TourStep(id: "home.tabs", targetId: "dock", text: text("tour.home.tabs",
                    ["plan": "nav.plan", "library": "nav.library", "progress": "nav.progress"]))
            ]
        case .plan:
            return [
                TourStep(id: "plan.days", targetId: "plan.days", text: text("tour.plan.days", ["home": "nav.home"])),
                TourStep(id: "plan.change", targetId: "plan.change", text: TourText(titleKey: "weekly.changeProgram", bodyKey: "tour.plan.change.body"))
            ]
        case .library:
            return [
                TourStep(id: "library.search", targetId: "library.search", text: text("tour.library.search")),
                TourStep(id: "library.filters", targetId: "library.filters", text: text("tour.library.filters")),
                TourStep(id: "library.exercise", targetId: "library.firstEntry", text: text("tour.library.exercise"))
            ]
        case .exercise:
            return [
                TourStep(id: "exercise.media", targetId: "exercise.media", text: text("tour.exercise.media")),
                TourStep(id: "exercise.tabs", targetId: "exercise.tabs", text: text("tour.exercise.tabs",
                    ["technique": "exercise.tab.technique", "history": "exercise.tab.history"]))
            ]
        case .progress:
            return [
                TourStep(id: "progress.calendar", targetId: "progress.calendar", text: TourText(titleKey: "history.calendar", bodyKey: "tour.progress.calendar.body")),
                TourStep(id: "progress.matrix", targetId: "progress.tab.matrix", text: TourText(titleKey: "history.volumeMatrix", bodyKey: "tour.progress.matrix.body")),
                TourStep(id: "progress.lab", targetId: "progress.tab.lab", text: TourText(titleKey: "history.formLab", bodyKey: "tour.progress.lab.body"))
            ]
        case .programs:
            return [
                TourStep(id: "programs.list", targetId: "programs.list", text: text("tour.programs.list")),
                TourStep(id: "programs.add", targetId: "programs.add", text: text("tour.programs.add"))
            ]
        case .workout:
            return [
                TourStep(id: "workout.exercises", targetId: "workout.exercises", text: text("tour.workout.exercises")),
                TourStep(id: "workout.sets", targetId: "workout.sets", text: text("tour.workout.sets", ["weight_unit": "settings.unitKg"]),
                         variants: [("lbs", text("tour.workout.sets", ["weight_unit": "settings.unitLbs"]))]),
                TourStep(id: "workout.finish", targetId: "workout.finish", text: TourText(titleKey: "session.finishBtn", bodyKey: "tour.workout.finish.body"))
            ]
        case .volumeMatrix:
            var steps = [
                TourStep(id: "matrix.body", targetId: "matrix.figure", text: text("tour.matrix.body")),
                TourStep(id: "matrix.legend", targetId: "matrix.legend", text: text("tour.matrix.legend")),
                TourStep(id: "matrix.detail", targetId: "matrix.detail", text: text("tour.matrix.detail")),
                TourStep(id: "matrix.mode", targetId: "matrix.mode", text: text("tour.matrix.mode", ["cycle": "matrix.mode.planned"]))
            ]
            if locked { steps.append(premiumStep("matrix.premium", feature: "history.volumeMatrix")) }
            return steps
        case .repLab:
            var steps = [
                TourStep(id: labRepMaxStep, targetId: "lab.repmax", text: TourText(titleKey: "form_lab.tab_rep_max", bodyKey: "tour.lab.repmax.body")),
                TourStep(id: labCurvesStep, targetId: "lab.curves", text: TourText(titleKey: "form_lab.tab_curves", bodyKey: "tour.lab.curves.body")),
                TourStep(id: labBalanceStep, targetId: "lab.balance", text: TourText(titleKey: "form_lab.tab_balance", bodyKey: "tour.lab.balance.body"))
            ]
            if locked { steps.append(premiumStep("lab.premium", feature: "history.formLab")) }
            return steps
        case .dayStatus:
            return [TourStep(id: "tip.dayStatus", targetId: "home.days", text: text("tip.dayStatus"))]
        case .restTimer:
            return [TourStep(id: "tip.rest", targetId: "workout.rest", text: text("tip.rest", ["skip": "rest.skip"]))]
        }
    }

    private static func premiumStep(_ id: String, feature: String) -> TourStep {
        TourStep(id: id, targetId: nil, text: TourText(titleKey: "tour.premium.title", bodyKey: "tour.premium.body", args: ["feature": feature]), isPremium: true)
    }
}
