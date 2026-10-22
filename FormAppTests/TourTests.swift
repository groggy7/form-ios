import XCTest
import SwiftUI
import UIKit
@testable import FormApp

/// Saved-state and catalog rules from gym/docs/design/app-tour.md §3–6; Android's TourModelsTest mirrors these.
final class TourTests: XCTestCase {

    func testFreshInstallsSeeCurrentToursAndRestTip() {
        let fresh = TourProgress()
        for id in TourId.allCases where id != .dayStatus { XCTAssertTrue(fresh.shouldStart(id), id.rawValue) }
        XCTAssertFalse(fresh.shouldStart(.dayStatus))
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
        XCTAssertFalse(twice.shouldStart(.dayStatus))
        XCTAssertTrue(twice.shouldStart(.volumeMatrix))
        XCTAssertEqual(TourProgress().skipped(.repLab).skipped(.restTimer).skipCount, 0)
    }

    func testHomeCombinesDaysAndColorsAndLongSectionsAreScrollable() {
        let home = TourCatalog.steps(.home)
        XCTAssertEqual(home.map(\.id), ["home.days", "home.workout", "home.week", "home.exercises", "home.tabs"])
        XCTAssertEqual(home.first?.targetId, "home.days")
        XCTAssertEqual(home.first?.text(for: ["scroll"]).bodyKey, "tour.home.days.bodyScroll")
        XCTAssertTrue(home.first { $0.id == "home.exercises" }!.scrollsContent)
        XCTAssertTrue(TourCatalog.steps(.repLab).first!.scrollsContent)
        XCTAssertTrue(TourProgress().finished(.home).seen.contains(.dayStatus))
        XCTAssertFalse(TourProgress().skipped(.home).shouldStart(.dayStatus))
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
            XCTAssertTrue((1...6).contains(steps.count), "\(id.rawValue) has \(steps.count) steps")
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
        var keys: [(String, Set<String>)] = TourId.allCases.flatMap { id in
            TourCatalog.steps(id, locked: true).flatMap { step in
                ([step.text] + step.variants.map(\.text)).flatMap { text -> [(String, Set<String>)] in
                    [(text.titleKey, []), (text.bodyKey, Set(text.args.keys))] + text.args.values.map { ($0, []) }
                }
            }
        }
        keys += HomeDayTourExample.allCases.flatMap { [($0.titleKey, Set<String>()), ($0.bodyKey, Set<String>())] }
        keys += ["tour.home.days.examples", "tour.next", "tour.back", "tour.done", "tour.skip", "tour.ok", "tour.seePremium", "tour.sampleData", "tour.scrollHint", "tour.scrollUp", "tour.scrollDown"].map { ($0, []) }
        keys.append(("tour.stepCount", ["current", "total"]))
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

/// Exercise real screen geometry and scrolling, including the last row of long sections.
final class TourLayoutTests: XCTestCase {
    @MainActor
    private func settle(file: StaticString = #filePath, line: UInt = #line,
                        message: @autoclosure () -> String = "Tour did not settle", _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message(), file: file, line: line)
    }

    @MainActor
    private func capture(_ window: UIWindow, _ name: String) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tour-\(name).png")
        try image.pngData()!.write(to: file)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("TOUR_SCREENSHOT \(file.path)")
    }

    @MainActor
    func testHomeHeroAndEveryExerciseCanBeSeen() async throws {
        try await checkHomeLayout(width: 393, textSize: .large, heroMustFit: true)
    }

    @MainActor
    func testLongSectionAt320PointsWithAccessibilityText() async throws {
        try await checkHomeLayout(width: 320, textSize: .accessibility3, heroMustFit: false)
    }

    @MainActor
    func testCompactDayLegendSnapshotsAcrossLanguagesAndThemes() throws {
        let language = LanguageManager.shared.currentLanguage
        let selectedTheme = ThemeManager.shared.selectedThemeId
        let subscribed = ProAccessManager.shared.isProSubscribed
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        defer {
            LanguageManager.setLanguage(language)
            ThemeManager.shared.setThemeId(selectedTheme)
            ProAccessManager.shared.updateSubscriptionStatus(active: subscribed)
        }
        for theme in ["default", "oat"] {
            ThemeManager.shared.setThemeId(theme)
            for language in ["en", "tr", "de", "fr", "es"] {
                LanguageManager.setLanguage(language)
                for size in [DynamicTypeSize.large, .accessibility1] {
                    let content = HomeDayTourLegend()
                        .frame(width: 252).padding(18)
                        .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: 20))
                        .padding(16).background(AppColors.background)
                        .dynamicTypeSize(size)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 320)
                    XCTAssertTrue(image.size.height.isFinite && image.size.height > 250)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "day-legend-\(theme)-\(language)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    private func checkHomeLayout(width: CGFloat, textSize: DynamicTypeSize, heroMustFit: Bool) async throws {
        let store = AppStore.shared
        let tour = TourController.shared
        let saved = store.state
        let savedProgress = store.tourProgress
        let savedSelection = store.selectedWorkoutId
        let language = LanguageManager.shared.currentLanguage
        LanguageManager.setLanguage("en")
        tour.cancel()
        store.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }
        let exercise = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3 × 8–12")
        let workout = Workout(id: "tour-upper", day: store.weekCalendar.today + 1, title: "Upper", exercises: (1...7).map { index in
            var item = exercise; item.id = "bench-\(index)"; return item
        })
        let program = Program(id: "tour-layout", name: "Tour layout", workouts: [workout])
        store.state = StoredAppState(programs: [program], activeProgramId: program.id, currentWeekKey: saved.currentWeekKey)
        store.selectedWorkoutId = workout.id
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        // Only one main tour host may report geometry. Detach the running app while
        // the fixture owns the shared controller, then restore it after the test.
        let previousRoot = previous?.rootViewController
        previous?.rootViewController = nil
        tour.update(frames: [:], bounds: .zero, origin: .zero, host: .main)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        let host = UIHostingController(rootView:
            TodayView(store: store, onOpenPrograms: {}, onOpenSettings: {}, onSelectExercise: { _ in })
                .background(AppColors.background).tourOverlay(.main).dynamicTypeSize(textSize))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer {
            tour.cancel(); window.isHidden = true; window.rootViewController = nil
            store.state = saved; store.selectedWorkoutId = savedSelection
            store.updateTourProgress { _ in savedProgress }; LanguageManager.setLanguage(language)
            previous?.rootViewController = previousRoot; previous?.makeKeyAndVisible()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        try await settle { tour.hasTarget("home.hero") && tour.hasTarget("home.exercises.row.7") }
        tour.start(.home)
        try await settle { tour.shownStepIndex == 0 }
        try capture(window, "ios-home-days-\(Int(width))")
        tour.next(); try await settle { tour.shownStepIndex == 1 }
        let hero = try XCTUnwrap(tour.frame("home.hero", host: .main)?.rect)
        let bubble = try XCTUnwrap(tour.bubbleBounds)
        if heroMustFit { XCTAssertFalse(hero.intersects(bubble), "The hero and explanation fit without overlap") }
        try capture(window, "ios-home-hero-\(Int(width))")
        tour.next(); try await settle { tour.shownStepIndex == 2 }
        tour.next(); try await settle { tour.shownStepIndex == 3 }
        try await settle(message: "First exercise must fit: viewport=\(String(describing: tour.groupViewport)), header=\(String(describing: tour.frame("home.exercises.row.0", host: .main)?.rect)), row=\(String(describing: tour.frame("home.exercises.row.1", host: .main)?.rect)), bubble=\(String(describing: tour.bubbleBounds))") {
            guard let area = tour.groupViewport,
                  let row = tour.frame("home.exercises.row.1", host: .main)?.rect else { return false }
            return row.minY >= area.minY - 1 && row.maxY <= area.maxY + 1
        }
        try capture(window, "ios-home-exercises-first-\(Int(width))")
        try await revealLastRow("home.exercises", tour: tour)
        try capture(window, "ios-home-exercises-last-\(Int(width))")
    }

    @MainActor
    func testRepMaxCanRevealItsCompleteLastRow() async throws {
        let store = AppStore.shared
        let tour = TourController.shared
        let saved = store.tourProgress
        tour.cancel(); store.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let previousRoot = previous?.rootViewController
        previous?.rootViewController = nil
        tour.update(frames: [:], bounds: .zero, origin: .zero, host: .main)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: ScrollViewReader { proxy in
            ScrollView { FormLabView(store: store, isPreview: true).padding(20) }
                .tourScrollable(proxy).background(AppColors.background).tourOverlay(.main)
        })
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer {
            tour.cancel(); window.isHidden = true; window.rootViewController = nil
            store.updateTourProgress { _ in saved }
            previous?.rootViewController = previousRoot; previous?.makeKeyAndVisible()
        }
        try await settle { tour.hasTarget("lab.repmax.row.3") }
        tour.start(.repLab)
        try await settle { tour.shownStepIndex == 0 }
        try capture(window, "ios-repmax-first")
        try await revealLastRow("lab.repmax", tour: tour)
        try capture(window, "ios-repmax-last")
    }

    @MainActor
    private func revealLastRow(_ id: String, tour: TourController) async throws {
        let last = try XCTUnwrap(tour.groupRows(id, host: .main).last?.0)
        for _ in 0..<10 {
            let viewport = try XCTUnwrap(tour.groupViewport)
            let frame = try XCTUnwrap(tour.frame(last, host: .main)?.rect)
            if frame.minY >= viewport.minY - 1 && frame.maxY <= viewport.maxY + 1 { return }
            tour.pageGroup(forward: true, host: .main)
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        XCTFail("The entire final row must be reachable in \(id)")
    }
}
