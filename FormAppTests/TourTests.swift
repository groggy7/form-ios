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

    func testHomeCombinesDaysAndColorsAndRowHighlightsUseFocusedSamples() {
        let home = TourCatalog.steps(.home)
        XCTAssertEqual(home.map(\.id), ["home.days", "home.workout", "home.week", "home.exercises", "home.tabs"])
        XCTAssertEqual(home.first?.targetId, "home.days")
        XCTAssertEqual(home.first?.text(for: ["scroll"]).bodyKey, "tour.home.days.bodyScroll")
        XCTAssertTrue(home.first { $0.id == "home.exercises" }!.highlightsRows)
        XCTAssertEqual(home.first { $0.id == "home.exercises" }!.rowHighlight, TourRowHighlight(leadingRows: 1, itemLimit: 3))
        XCTAssertEqual(TourCatalog.steps(.repLab).first!.rowHighlight, TourRowHighlight())
        XCTAssertEqual(ProPreviewData.formLabRepMaxSummary.targets.map(\.reps), [1, 3, 5, 8, 10])
        XCTAssertTrue(TourCatalog.steps(.workout).first { $0.id == "workout.sets" }!.highlightsRows)
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
        keys += ["tour.home.days.examples", "tour.next", "tour.back", "tour.done", "tour.skip", "tour.ok", "tour.seePremium", "tour.sampleData"].map { ($0, []) }
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
    @discardableResult
    private func capture(_ window: UIWindow, _ name: String) throws -> UIImage {
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
        return image
    }

    @MainActor
    func testHomeDockHighlightEnclosesTheWholeDockInTurkish() async throws {
        try await checkDockHighlight(width: 440, textSize: .large, theme: "default")
    }

    @MainActor
    func testHomeDockHighlightAt320PointsWithAccessibilityTextInOat() async throws {
        try await checkDockHighlight(width: 320, textSize: .accessibility3, theme: "oat")
    }

    @MainActor
    private func checkDockHighlight(width: CGFloat, textSize: DynamicTypeSize, theme: String) async throws {
        let store = AppStore.shared
        let tour = TourController.shared
        let progress = store.tourProgress
        let language = LanguageManager.shared.currentLanguage
        let selectedTheme = ThemeManager.shared.selectedThemeId
        let subscribed = ProAccessManager.shared.isProSubscribed
        tour.cancel()
        store.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }
        LanguageManager.setLanguage("tr")
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        ThemeManager.shared.setThemeId(theme)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let previousRoots = scene.windows.filter { $0.windowLevel == .normal && $0.rootViewController != nil }
            .map { ($0, $0.rootViewController) }
        previousRoots.forEach { $0.0.rootViewController = nil }
        tour.update(frames: [:], bounds: .zero, origin: .zero, host: .main)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        // Match RootView's dock placement, including its extension into the bottom safe area.
        let host = UIHostingController(rootView:
            VStack(spacing: 0) {
                Spacer()
                BottomDock(currentView: .constant(.today))
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .background(AppColors.background.ignoresSafeArea())
            .tourOverlay(.main).dynamicTypeSize(textSize))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer {
            tour.cancel(); window.isHidden = true; window.rootViewController = nil
            store.updateTourProgress { _ in progress }; LanguageManager.setLanguage(language)
            ThemeManager.shared.setThemeId(selectedTheme)
            ProAccessManager.shared.updateSubscriptionStatus(active: subscribed)
            previousRoots.forEach { $0.0.rootViewController = $0.1 }; previous?.makeKeyAndVisible()
        }
        try await settle { tour.hasTarget("dock") }
        try await Task.sleep(nanoseconds: 200_000_000)
        // Keep this single-target fixture independent of delayed preferences from restored app windows.
        let dockFrame = try XCTUnwrap(tour.frame("dock", host: .main))
        tour.cancel()
        tour.update(frames: ["dock": dockFrame], bounds: window.bounds.size, origin: .zero, host: .main)
        tour.start(.home)
        try await settle { tour.currentStepId == "home.tabs" && tour.shownStepIndex == 0 }
        try await Task.sleep(nanoseconds: 200_000_000)
        let dock = try XCTUnwrap(tour.frame("dock", host: .main)?.rect)
        let bubble = try XCTUnwrap(tour.bubbleBounds)
        XCTAssertLessThanOrEqual(bubble.maxY + 12, dock.minY - 6 + 1)
        let image = try capture(window, "ios-home-dock-\(Int(width))-\(theme)")
        let cg = try XCTUnwrap(image.cgImage)
        let accent = AppColors.accent.resolve(in: EnvironmentValues())
        func isOutline(x: CGFloat, y: CGFloat) -> Bool {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: -x * image.scale,
                y: -(CGFloat(cg.height) - y * image.scale - 1), width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return abs(Float(rgba[0]) / 255 - accent.red) < 0.15
                && abs(Float(rgba[1]) / 255 - accent.green) < 0.15
                && abs(Float(rgba[2]) / 255 - accent.blue) < 0.15
        }
        let expected = dock.insetBy(dx: -6, dy: -6)
        // Inspect the rendered ring, so clipping it to the bubble's safe area fails this check.
        for edge in [CGPoint(x: expected.midX, y: expected.minY), CGPoint(x: expected.midX, y: expected.maxY),
                     CGPoint(x: expected.minX, y: expected.midY), CGPoint(x: expected.maxX, y: expected.midY)] {
            XCTAssertTrue(isOutline(x: edge.x, y: edge.y), "The outline must surround the complete dock at \(edge)")
        }
    }

    @MainActor
    func testHomeHeroAndEveryExerciseCanBeSeen() async throws {
        try await checkHomeLayout(width: 393, textSize: .large, heroMustFit: true)
    }

    @MainActor
    func testWorkoutSetsShowAFocusedSampleAboveNavigation() async throws {
        try await checkWorkoutSets(width: 440, textSize: .large, theme: "default")
    }

    @MainActor
    func testWorkoutSetsAt320PointsWithAccessibilityTextInOat() async throws {
        try await checkWorkoutSets(width: 320, textSize: .accessibility3, theme: "oat")
    }

    @MainActor
    private func checkWorkoutSets(width: CGFloat, textSize: DynamicTypeSize, theme: String) async throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let tour = TourController.shared
        let progress = AppStore.shared.tourProgress
        let language = LanguageManager.shared.currentLanguage
        let selectedTheme = ThemeManager.shared.selectedThemeId
        let subscribed = ProAccessManager.shared.isProSubscribed
        let collapsed = store.sessionStripCollapsed
        tour.cancel()
        AppStore.shared.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }
        LanguageManager.setLanguage("tr")
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        ThemeManager.shared.setThemeId(theme)
        store.sessionStripCollapsed = false
        let exercise = Exercise(id: "bench", name: "Dumbbell Bench Press", exerciseId: "dumbbell-bench-press",
                                sets: 8, reps: RepTarget(min: 6, max: 10))
        let workout = Workout(id: "tour-sets", day: 1, title: "Push", exercises: [exercise])
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let draft = ActiveSessionDraft(programId: "tour-sets", workout: workout,
            startedAt: "2026-10-23T08:00:00Z", startedAtEpochMillis: now,
            setsByExercise: [exercise.id: (1...8).map {
                ExerciseSetLog(id: "set-\($0)", setNumber: $0, weightKg: $0 < 3 ? 20 : nil,
                               completedReps: $0 < 3 ? 8 : nil, isCompleted: $0 < 3)
            }])
        store.activeSession = draft
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let previousRoots = scene.windows.filter { $0.windowLevel == .normal && $0.rootViewController != nil }
            .map { ($0, $0.rootViewController) }
        previousRoots.forEach { $0.0.rootViewController = nil }
        tour.update(frames: [:], bounds: .zero, origin: .zero, host: .workout)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        let host = UIHostingController(rootView: ActiveSessionView(store: store, draft: draft).dynamicTypeSize(textSize))
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer {
            tour.cancel(); window.isHidden = true; window.rootViewController = nil
            store.sessionStripCollapsed = collapsed
            AppStore.shared.updateTourProgress { _ in progress }; LanguageManager.setLanguage(language)
            ThemeManager.shared.setThemeId(selectedTheme)
            ProAccessManager.shared.updateSubscriptionStatus(active: subscribed)
            previousRoots.forEach { $0.0.rootViewController = $0.1 }; previous?.makeKeyAndVisible()
        }
        try await settle { tour.hasTarget("workout.sets") && tour.hasTarget("workout.finish") }
        tour.start(.workout)
        try await settle { tour.shownStepIndex == 0 }
        tour.next(); try await settle { tour.currentStepId == "workout.sets" && tour.shownStepIndex == 1 }
        try await Task.sleep(nanoseconds: 200_000_000)
        try capture(window, "ios-workout-sets-first-\(Int(width))-\(theme)")
        let viewport = try XCTUnwrap(tour.groupViewport, "The sample must fit within the table viewport")
        let scroll = tour.scrollViewport("workout.sets", host: .workout)
        XCTAssertLessThanOrEqual(viewport.maxY + 6, scroll.maxY + 1)
        let bubble = try XCTUnwrap(tour.bubbleBounds)
        XCTAssertLessThanOrEqual(bubble.maxY + 12, viewport.minY - 6 + 1)
        try assertSample("workout.sets", tour: tour, host: .workout, leadingRows: 2)
        let unchanged = try XCTUnwrap(store.activeSession)
        XCTAssertEqual(unchanged.setsByExercise, draft.setsByExercise, "The tour must not log or edit sets")
        tour.next(); try await settle { tour.currentStepId == "workout.finish" && tour.shownStepIndex == 2 }
        tour.back(); try await settle { tour.currentStepId == "workout.sets" && tour.shownStepIndex == 1 }
        try await settle {
            guard let area = tour.groupViewport, let first = tour.frame("workout.sets.row.2", host: .workout)?.rect else { return false }
            return first.minY >= area.minY - 1 && first.maxY <= area.maxY + 1
        }
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
        let previousRoots = scene.windows.filter { $0.windowLevel == .normal && $0.rootViewController != nil }
            .map { ($0, $0.rootViewController) }
        previousRoots.forEach { $0.0.rootViewController = nil }
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
            previousRoots.forEach { $0.0.rootViewController = $0.1 }; previous?.makeKeyAndVisible()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        try await settle { tour.hasTarget("home.hero") && tour.hasTarget("home.exercises.row.7") }
        tour.start(.home)
        try await settle { tour.shownStepIndex == 0 }
        try capture(window, "ios-home-days-\(Int(width))")
        tour.next(); try await settle { tour.shownStepIndex == 1 }
        if heroMustFit {
            try await settle(message: "The hero and explanation fit without overlap") {
                guard let hero = tour.frame("home.hero", host: .main)?.rect, let bubble = tour.bubbleBounds else { return false }
                return !hero.intersects(bubble)
            }
        }
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
        try assertSample("home.exercises", tour: tour, host: .main, leadingRows: 1)
    }

    @MainActor
    func testRepMaxHighlightsAllFiveCardsTogether() async throws {
        try await checkRepMax(width: 393, textSize: .large)
    }

    @MainActor
    func testRepMaxAllFiveCardsAt320PointsWithAccessibilityText() async throws {
        try await checkRepMax(width: 320, textSize: .accessibility3)
    }

    @MainActor
    private func checkRepMax(width: CGFloat, textSize: DynamicTypeSize) async throws {
        let store = AppStore.shared
        let tour = TourController.shared
        let saved = store.tourProgress
        tour.cancel(); store.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let previousRoots = scene.windows.filter { $0.windowLevel == .normal && $0.rootViewController != nil }
            .map { ($0, $0.rootViewController) }
        previousRoots.forEach { $0.0.rootViewController = nil }
        tour.update(frames: [:], bounds: .zero, origin: .zero, host: .main)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
        let host = UIHostingController(rootView: ScrollViewReader { proxy in
            ScrollView { FormLabView(store: store, isPreview: true).padding(20) }
                .tourScrollable(proxy).background(AppColors.background).tourOverlay(.main).dynamicTypeSize(textSize)
        })
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer {
            tour.cancel(); window.isHidden = true; window.rootViewController = nil
            store.updateTourProgress { _ in saved }
            previousRoots.forEach { $0.0.rootViewController = $0.1 }; previous?.makeKeyAndVisible()
        }
        try await settle { tour.hasTarget("lab.repmax.row.2") }
        tour.start(.repLab)
        try await settle { tour.shownStepIndex == 0 }
        try capture(window, "ios-repmax-first")
        try await settle(message: "All five Rep Max cards must fit: viewport=\(String(describing: tour.groupViewport)), highlight=\(String(describing: tour.groupHighlightBounds)), rows=\(tour.groupRows("lab.repmax", host: .main))") {
            guard let bounds = tour.groupHighlightBounds else { return false }
            return tour.groupRows("lab.repmax", host: .main).allSatisfy { bounds.insetBy(dx: -1, dy: -1).contains($0.1.rect) }
        }
        XCTAssertEqual(tour.groupRows("lab.repmax", host: .main).count, 3)
        try capture(window, "ios-repmax-all-five-\(Int(width))")
    }

    @MainActor
    private func assertSample(_ id: String, tour: TourController, host: TourHost, leadingRows: Int) throws {
        let bounds = try XCTUnwrap(tour.groupHighlightBounds)
        let rows = tour.groupRows(id, host: host)
        let items = rows.dropFirst(leadingRows)
        let visible = items.filter { bounds.insetBy(dx: -1, dy: -1).contains($0.1.rect) }
        XCTAssertTrue((1...3).contains(visible.count), "Show one to three complete items")
        for row in rows.prefix(leadingRows) { XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(row.1.rect)) }
        for row in items.dropFirst(3) { XCTAssertFalse(bounds.intersects(row.1.rect), "Further items stay dimmed") }
    }
}
