import XCTest
@testable import FormApp

/// Saved-state and catalog rules from gym/docs/design/app-tour.md §3–6; Android's TourModelsTest mirrors these.
final class TourTests: XCTestCase {

    func testFreshInstallsSeeEveryScreenTourPreviewAndTip() {
        let fresh = TourProgress()
        for id in TourId.allCases { XCTAssertTrue(fresh.shouldStart(id), id.rawValue) }
        XCTAssertTrue(fresh.shouldStart(.volumeMatrix, featureUnlocked: true))
    }

    func testReturningUsersKeepOnlyTheSamplePreviewsForLockedFeatures() {
        let returning = TourProgress().returningUser()
        for id in TourId.allCases where id.kind != .preview { XCTAssertFalse(returning.shouldStart(id), id.rawValue) }
        XCTAssertTrue(returning.shouldStart(.volumeMatrix, featureUnlocked: false))
        XCTAssertTrue(returning.shouldStart(.repLab, featureUnlocked: false))
        XCTAssertFalse(returning.shouldStart(.volumeMatrix, featureUnlocked: true))
    }

    func testTwoSkippedScreenToursStopTheRestButNotTipsOrPreviews() {
        let once = TourProgress().skipped(.home)
        XCTAssertEqual(once.skipCount, 1)
        XCTAssertTrue(once.shouldStart(.plan))
        let twice = once.skipped(.plan)
        XCTAssertFalse(twice.shouldStart(.library))
        XCTAssertFalse(twice.shouldStart(.workout))
        XCTAssertTrue(twice.shouldStart(.dayStatus))
        XCTAssertTrue(twice.shouldStart(.volumeMatrix))
        XCTAssertEqual(TourProgress().skipped(.repLab).skipped(.restTimer).skipCount, 0)
    }

    func testStorageKeysMatchAndroid() {
        XCTAssertEqual(TourId.home.storageKey, "tour_seen_home_v1")
        XCTAssertEqual(TourId.volumeMatrix.storageKey, "tour_seen_volume_matrix_v1")
        XCTAssertEqual(TourId.dayStatus.storageKey, "tip_seen_day_status_v1")
        XCTAssertEqual(Set(TourId.allCases.map(\.storageKey)).count, TourId.allCases.count)
    }

    func testPremiumStepsCloseOnlyLockedPreviews() {
        XCTAssertEqual(TourCatalog.steps(.volumeMatrix, locked: true).last?.isPremium, true)
        XCTAssertFalse(TourCatalog.steps(.volumeMatrix, locked: false).contains { $0.isPremium })
        XCTAssertNil(TourCatalog.steps(.repLab, locked: true).last?.targetId)
        for id in TourId.allCases where id.kind != .preview {
            XCTAssertFalse(TourCatalog.steps(id, locked: true).contains { $0.isPremium }, id.rawValue)
        }
    }

    func testStepsStayShortAndFlagsChooseTheWording() {
        for id in TourId.allCases {
            let steps = TourCatalog.steps(id, locked: true)
            XCTAssertTrue((1...5).contains(steps.count), "\(id.rawValue) has \(steps.count) steps")
            if id.kind == .tip { XCTAssertEqual(steps.count, 1) }
        }
        let workout = TourCatalog.steps(.home).first { $0.id == "home.workout" }!
        XCTAssertEqual(workout.text(for: []).bodyKey, "tour.home.workout.body")
        XCTAssertEqual(workout.text(for: ["views"]).bodyKey, "tour.home.workout.bodyViews")
        XCTAssertEqual(workout.text(for: ["rest"]).titleKey, "tour.home.rest.title")
        let sets = TourCatalog.steps(.workout).first { $0.id == "workout.sets" }!
        XCTAssertEqual(sets.text(for: ["kg"]).args["weight_unit"], "settings.unitKg")
        XCTAssertEqual(sets.text(for: ["lbs"]).args["weight_unit"], "settings.unitLbs")
    }

    /// Every key a step uses exists in every shipped language, with its placeholders filled.
    func testEveryStepHasCopyInAllLanguages() throws {
        let keys: [(String, Set<String>)] = TourId.allCases.flatMap { id in
            TourCatalog.steps(id, locked: true).flatMap { step in
                ([step.text] + step.variants.map(\.text)).flatMap { text -> [(String, Set<String>)] in
                    [(text.titleKey, []), (text.bodyKey, Set(text.args.keys))] + text.args.values.map { ($0, []) }
                }
            }
        } + ["tour.next", "tour.back", "tour.done", "tour.skip", "tour.ok", "tour.seePremium", "tour.sampleData"].map { ($0, []) }
            + [("tour.stepCount", ["current", "total"])]
        let placeholder = try NSRegularExpression(pattern: "\\{(\\w+)\\}")
        for language in ["en", "tr", "de", "fr", "es"] {
            for (key, args) in keys {
                let value = LanguageManager.shared.translate(key, language: language)
                XCTAssertNotEqual(value, key, "\(language) is missing \(key)")
                let range = NSRange(value.startIndex..., in: value)
                for match in placeholder.matches(in: value, range: range) {
                    let name = String(value[Range(match.range(at: 1), in: value)!])
                    XCTAssertTrue(args.contains(name), "\(language)/\(key) has no value for {\(name)}")
                }
            }
        }
    }
}
