import XCTest
import SwiftUI
import ImageIO
@testable import FormApp

final class SocialCardsTests: XCTestCase {
    private struct Fixtures: Decodable {
        struct Case: Decodable { let name: String; let history: [WorkoutSessionRecord]; let target: WorkoutSessionRecord; let expected: [String] }
        struct WeekCase: Decodable { let name: String; let record: WorkoutSessionRecord; let zone: String; let expectedWeek: String }
        let weekCases: [WeekCase]
        let cases: [Case]
        let previewHistory: [WorkoutSessionRecord]
        let previewWorkout: WorkoutSessionRecord
    }
    func testSharedRecordFixtures() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("social-card-fixtures.json")
        let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        let labels: [RecordKind: String] = [.weight: "weight", .reps: "reps", .assistance: "assistance"]
        for item in fixtures.cases {
            let actual = RecordEngine.forSession(history: item.history, target: item.target, timeZone: TimeZone(secondsFromGMT: 0)!)
            XCTAssertEqual(actual.map { labels[$0.kind]! }, item.expected, item.name)
        }
    }
    func testWeekWithoutRecordCanStillSuggest() {
        let card = SocialCardContent(id: "week", kind: .week, title: "Week complete", result: "4 / 4", detail: "Workouts")
        XCTAssertEqual(SocialCards.suggested(cards: [], week: card, justCompletedWeek: true)?.cards.first?.kind, .week)
        XCTAssertNil(SocialCards.suggested(cards: [], week: card, justCompletedWeek: false))
    }
    func testExportAllowlistCannotCarryPrivateFields() {
        let card = SocialCardContent(id: "", kind: .summary, title: "", result: "", detail: "")
        let names = Set(Mirror(reflecting: card).children.compactMap(\.label))
        XCTAssertTrue(names.isDisjoint(with: ["effort", "jointStress", "bodyweight", "notes", "session", "programName"]))
    }

    private func fixtures() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("social-card-fixtures.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
    @MainActor func testNativeReferenceImagesAndAllLocalizedCanonicalTitlesFit() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let fixture = try fixtures()
        let program = Program(id: "social-fixture", name: "Private plan", workouts: (1...4).map { Workout(id: "w\($0)", day: $0, title: "Workout") })
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { c in
            UIColor(red: 228/255, green: 216/255, blue: 196/255, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            UIColor(red: 51/255, green: 74/255, blue: 69/255, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        }
        for lang in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(lang)
            let names = ContentLocalizer.shared.loadExercises(lang: lang).values.compactMap(\.name)
            XCTAssertEqual(names.count, 300)
            for name in names { XCTAssertTrue(SocialCardRenderer.titleFits(name), "Does not fit: \(lang) \(name)") }
            let cards = SocialCards.workout(history: fixture.previewHistory, record: fixture.previewWorkout, unit: .kg)
            XCTAssertEqual(cards.count, 2)
            let week = try XCTUnwrap(SocialCards.week(program: program, completed: (1...4).map { "social-fixture:w\($0)" }, history: fixture.previewHistory + fixture.previewHistory, weekKey: "2026-W43", unit: .kg, today: WorkoutCalendar.parseDate("2026-10-25")!))
            XCTAssertEqual(week.metrics.first { $0.key == "sets" }?.value, "62")
            XCTAssertEqual(week.metrics.first { $0.key == "records" }?.value, "3")
            for card in cards + [week] { for format in SocialCardFormat.allCases {
                let output = SocialCardRenderer.render(card, format: format, photo: photo)
                XCTAssertEqual(output.image.cgImage?.width, 1080)
                XCTAssertEqual(output.image.cgImage?.colorSpace?.name, CGColorSpace.sRGB)
                XCTAssertEqual(output.image.cgImage?.height, format == .post ? 1350 : 1920)
                if format == .photo { XCTAssertEqual(output.sticker?.cgImage?.width, 900) }
                let data = try SocialCardSharing.png(output.image)
                let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
                XCTAssertNil(props?[kCGImagePropertyGPSDictionary as String])
                if ["en", "de"].contains(lang) {
                    let name = "social-\(lang)-\(card.kind)-\(format.rawValue)"
                    let attachment = XCTAttachment(image: output.image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                    let directory = URL(fileURLWithPath: "/tmp/forcedrep-social-ios", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: directory.appendingPathComponent(name + ".png"))
                }
            } }
        }
    }
    @MainActor func testSharedFilesStayReadableAndComposerFitsNarrowLargeText() async throws {
        let fixture = try fixtures()
        let cards = SocialCards.workout(history: fixture.previewHistory, record: fixture.previewWorkout, unit: .kg)
        let image = SocialCardRenderer.render(cards[0], format: .story).image
        let first = try SocialCardSharing.shareURL(image), second = try SocialCardSharing.shareURL(image)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: second))
        XCTAssertFalse(SocialCardSharing.canShareStory)
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            let localized = SocialCards.workout(history: fixture.previewHistory, record: fixture.previewWorkout, unit: .kg)
            let host = UIHostingController(rootView: SocialCardComposer(request: SocialShareRequest(cards: localized)) {}.environment(\.sizeCategory, .extraExtraExtraLarge))
            let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
            window.windowScene = previousWindow?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 700_000_000)
            let capture = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: capture); attachment.name = "social-composer-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; previousWindow?.makeKeyAndVisible()
        }
    }
    @MainActor func testSaveSuggestionsRespectSettingsAndDoNotReplayCompletedRecords() throws {
        let fixture = try fixtures()
        let persistence = AppStatePersistence(inMemory: true)
        let previous = UserDefaults.standard.object(forKey: "suggest_sharing")
        defer { if let previous { UserDefaults.standard.set(previous, forKey: "suggest_sharing") } else { UserDefaults.standard.removeObject(forKey: "suggest_sharing") } }
        let store = AppStore(persistence: persistence)
        var record = fixture.previewWorkout
        let workout = Workout(id: record.workoutId, day: 1, title: record.workoutTitle,
            exercises: record.exerciseLogs.map { Exercise(name: $0.exerciseName, exerciseId: $0.exerciseId, sets: $0.targetSets) })
        record.workoutSnapshot = workout
        store.state.programs = [Program(id: record.programId, name: "Private plan", workouts: [workout, Workout(id: "unfinished", day: 2, title: "Unfinished")])]
        store.state.activeProgramId = record.programId
        store.state.history = [fixture.previewHistory[0]]
        store.state.completed = []
        store.suggestSharing = false
        store.completeActiveSession(record, suggestSharingAfterSave: true)
        XCTAssertNil(store.socialShareRequest)
        XCTAssertTrue(store.state.history.contains { $0.id == record.id && $0.isComplete == true })
        store.suggestSharing = true
        store.completeActiveSession(record, suggestSharingAfterSave: true)
        XCTAssertNil(store.socialShareRequest, "An already complete record must not suggest again")
        var next = record; next.id = "fresh-pr"; next.startedAt = "2026-10-20T10:00:00Z"
        for i in next.exerciseLogs.indices { for j in next.exerciseLogs[i].sets.indices { next.exerciseLogs[i].sets[j].weightKg! += 5 } }
        store.completeActiveSession(next, suggestSharingAfterSave: true)
        XCTAssertEqual(store.socialShareRequest?.cards.first?.kind, .record)
        store.socialShareRequest = nil
        next.id = "background-save"; next.startedAt = "2026-10-21T10:00:00Z"
        for i in next.exerciseLogs.indices { for j in next.exerciseLogs[i].sets.indices { next.exerciseLogs[i].sets[j].weightKg! += 5 } }
        store.completeActiveSession(next)
        XCTAssertNil(store.socialShareRequest, "Recovery and background saves must remain quiet")
    }
    @MainActor func testFailedDurableSaveCannotOfferSharing() throws {
        enum Failure: Error { case disk }
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw Failure.disk } })
        let store = AppStore(persistence: persistence)
        try persistence.flush()
        let fixture = try fixtures()
        store.state.history = [fixture.previewHistory[0]]
        fail = true
        store.completeActiveSession(fixture.previewWorkout, suggestSharingAfterSave: true)
        XCTAssertNil(store.socialShareRequest)
        XCTAssertFalse(store.state.history.contains { $0.id == fixture.previewWorkout.id })
    }

    func testSharedWeekBoundariesAndTimeZones() throws {
        for item in try fixtures().weekCases {
            XCTAssertTrue(PersonalRecordTracker.isRecordInWeek(item.record, targetWeekKey: item.expectedWeek, timeZone: try XCTUnwrap(TimeZone(identifier: item.zone))), item.name)
        }
    }

    @MainActor func testRootPresentsSavedSuggestionAfterWorkoutCoverDismisses() async throws {
        let store = AppStore.shared
        let previousState = store.state, previousDraft = store.activeSession
        let previousSetup = store.isOnboardingCompleted, previousPreference = store.suggestSharing
        let previousView = store.currentView
        let previousActiveData = UserDefaults.standard.object(forKey: "active_session_v1")
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let fixture = try fixtures()
        var record = fixture.previewWorkout
        let now = Date(), stamp = ISO8601DateFormatter().string(from: now)
        record.startedAt = stamp; record.completedAt = stamp
        let workout = Workout(id: record.workoutId, day: 1, title: record.workoutTitle,
            exercises: record.exerciseLogs.map { Exercise(name: $0.exerciseName, exerciseId: $0.exerciseId, sets: $0.targetSets) })
        record.workoutSnapshot = workout
        record.performedDate = WorkoutCalendar.formatDate(now)
        var state = previousState
        state.programs = [Program(id: record.programId, name: "Fixture", workouts: [workout, Workout(id: "unfinished", day: 2, title: "Unfinished")])]
        state.activeProgramId = record.programId; state.history = [fixture.previewHistory[0]]
        state.completed = []; state.currentWeekKey = PersonalRecordTracker.isoWeekKey(now); state.calendarHistory = nil
        store.state = state; store.isOnboardingCompleted = true; store.suggestSharing = true
        store.currentView = .today; store.isSessionPresented = false; store.socialShareRequest = nil
        TourController.shared.cancel()
        let host = UIHostingController(rootView: RootView())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.windowScene = previousWindow?.windowScene
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; previousWindow?.makeKeyAndVisible()
            store.isSessionPresented = false; store.socialShareRequest = nil
            store.activeSession = previousDraft; store.isOnboardingCompleted = previousSetup
            store.suggestSharing = previousPreference; store.currentView = previousView
            _ = store.saveState(previousState, durable: true)
            if let previousActiveData { UserDefaults.standard.set(previousActiveData, forKey: "active_session_v1") }
            else { UserDefaults.standard.removeObject(forKey: "active_session_v1") }
            TourController.shared.cancel()
        }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        store.activeSession = ActiveSessionDraft(id: record.id, programId: record.programId, workout: workout,
            startedAt: stamp, startedAtEpochMillis: Int64(now.timeIntervalSince1970 * 1000),
            setsByExercise: WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record), assignedCalendarDate: record.performedDate)
        store.isSessionPresented = true
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertNotNil(host.presentedViewController)
        store.completeActiveSession(record, suggestSharingAfterSave: true)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertFalse(store.isSessionPresented)
        XCTAssertEqual(store.socialShareRequest?.cards.first?.kind, .record)
        let sheet = try XCTUnwrap(host.presentedViewController, "The saved suggestion must appear after the workout cover closes")
        XCTAssertTrue([UIModalPresentationStyle.pageSheet, .formSheet].contains(sheet.modalPresentationStyle), "The suggestion uses the native adaptive sheet, never the workout full-screen cover")
        let image = UIGraphicsImageRenderer(bounds: sheet.view.bounds).image { sheet.view.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "social-after-save"; attachment.lifetime = .keepAlways; add(attachment)
        // UIKit programmatic dismissal does not represent the SwiftUI close action.
        sheet.dismiss(animated: false)
        try await Task.sleep(nanoseconds: 250_000_000)
    }

}
