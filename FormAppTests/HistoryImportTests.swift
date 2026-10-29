import XCTest
import SwiftUI
import ActivityKit
import CryptoKit
@testable import FormApp

final class WorkoutNotePersistenceTests: XCTestCase {
    private let note = "Different gym today.\nUse the quieter rack."

    @MainActor
    private func withSession(_ body: (AppStore, Workout) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        let access = ProAccessManager.shared
        let cloudAccess = access.isFeatureUnlocked(.cloudBackup)
        access.setFeatureOverride(.cloudBackup, unlocked: false)
        defer { access.setFeatureOverride(.cloudBackup, unlocked: cloudAccess == access.isProSubscribed ? nil : cloudAccess) }
        defaults.removeObject(forKey: "active_session_v1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workout = Workout(id: "note-day", day: 1, title: "Notes regression", exercises: [
            Exercise(id: "bench", name: "Bench Press", exerciseId: "barbell-bench-press", sets: 1)
        ])
        let program = Program(id: "note-plan", name: "Notes plan", workouts: [workout])
        let store = AppStore(persistence: AppStatePersistence(databaseURL: directory.appendingPathComponent("state.sqlite")))
        XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: program.id,
            currentWeekKey: store.state.currentWeekKey), durable: true))
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: workout, allowPast: true))
        try body(store, workout)
    }

    private func writeNote(_ store: AppStore, _ text: String?) {
        store.updateActiveSession { current in
            var copy = current
            copy.note = text
            return copy
        }
    }

    private func save(_ store: AppStore) throws {
        let draft = try XCTUnwrap(store.activeSession)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        store.completeActiveSession(SessionProgress.from(draft: draft, nowEpochMillis: now)
            .record(draft: draft, completedAtEpochMillis: now))
    }

    @MainActor func testNoteOnlyExitSurvivesRelaunchAndResume() throws {
        try withSession { store, workout in
            let id = try XCTUnwrap(store.activeSession?.id)
            writeNote(store, note)
            store.abandonActiveSession()
            XCTAssertNil(store.activeSession)
            let relaunched = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(relaunched.state.history.first?.note, note)
            XCTAssertTrue(relaunched.startActiveSession(programId: "note-plan", workout: workout, allowPast: true))
            XCTAssertEqual(relaunched.activeSession?.id, id)
            XCTAssertEqual(relaunched.activeSession?.note, note)
            XCTAssertEqual(relaunched.state.history.count, 1)
        }
    }

    @MainActor func testNoteOnlySummarySaveStaysUnfinishedAndResumesWithoutDuplicateHistory() throws {
        try withSession { store, workout in
            writeNote(store, note)
            try save(store)
            let saved = try XCTUnwrap(store.state.history.first)
            XCTAssertEqual(saved.note, note)
            XCTAssertEqual(saved.isComplete, false)
            XCTAssertEqual(saved.totalCompletedSets, 0)
            XCTAssertEqual(saved.totalVolumeKg, 0)
            XCTAssertTrue(store.state.completed.isEmpty)
            XCTAssertEqual(store.state.calendarHistory?.entries.first { $0.id == "session:\(saved.id)" }?.status, .unfinished)
            let persisted = try XCTUnwrap(store.statePersistence.load()?.history.first)
            XCTAssertEqual(persisted.id, saved.id)
            XCTAssertEqual(persisted.note, note)
            XCTAssertEqual(persisted.exerciseLogs, saved.exerciseLogs)
            let relaunched = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(relaunched.state.history.count, 1)
            XCTAssertEqual(relaunched.state.history.first?.id, saved.id)
            XCTAssertEqual(relaunched.state.history.first?.note, note)
            XCTAssertTrue(relaunched.startActiveSession(programId: "note-plan", workout: workout, allowPast: true))
            XCTAssertEqual(relaunched.activeSession?.note, note)
            writeNote(relaunched, "Updated during review")
            try save(relaunched)
            XCTAssertEqual(relaunched.state.history.count, 1)
            XCTAssertEqual(relaunched.state.history.first?.id, saved.id)
            XCTAssertEqual(relaunched.state.history.first?.note, "Updated during review")
        }
    }

    @MainActor func testNoteSurvivesLiveDraftRelaunchBeforeAnySetIsLogged() throws {
        try withSession { store, _ in
            writeNote(store, note)
            let relaunched = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(relaunched.activeSession?.note, note)
            XCTAssertEqual(relaunched.activeSession?.id, store.activeSession?.id)
            relaunched.resumeActiveSession()
            XCTAssertEqual(relaunched.activeSession?.note, note)
        }
    }

    @MainActor func testCompletedWorkoutRetainsLatestNoteAndFreshSessionStartsWithoutIt() throws {
        try withSession { store, workout in
            writeNote(store, note)
            store.updateActiveSession { current in
                var copy = current
                copy.setsByExercise["bench"] = [ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "8",
                    weightKg: 50, completedReps: 8, isCompleted: true)]
                return copy
            }
            writeNote(store, "Changed on the summary")
            try save(store)
            let relaunched = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(relaunched.state.history.first?.note, "Changed on the summary")
            XCTAssertEqual(relaunched.state.history.first?.isComplete, true)
            XCTAssertTrue(relaunched.startActiveSession(programId: "note-plan", workout: workout,
                allowPast: true, startNewSession: true))
            XCTAssertNil(relaunched.activeSession?.note)
        }
    }

    @MainActor func testEmptyOrClearedNoteDoesNotCreateWorkoutHistory() throws {
        for text in [nil, "", " \n\t "] as [String?] {
            try withSession { store, _ in
                writeNote(store, note)
                writeNote(store, text)
                store.abandonActiveSession()
                XCTAssertNil(store.activeSession)
                XCTAssertTrue(store.state.history.isEmpty)
                XCTAssertTrue(AppStore(persistence: store.statePersistence).state.history.isEmpty)
            }
        }
    }

    @MainActor func testClearingTheOnlySavedNoteRemovesTheEmptySession() throws {
        try withSession { store, workout in
            writeNote(store, note)
            try save(store)
            let id = try XCTUnwrap(store.state.history.first?.id)
            XCTAssertTrue(store.startActiveSession(programId: "note-plan", workout: workout, allowPast: true))
            writeNote(store, nil)
            store.abandonActiveSession()
            XCTAssertTrue(store.state.history.isEmpty)
            XCTAssertFalse(store.state.calendarHistory?.entries.contains { $0.id == "session:\(id)" } == true)
            XCTAssertTrue(AppStore(persistence: store.statePersistence).state.history.isEmpty)
        }
    }

    @MainActor func testNoteOnlySummaryKeepsTheNoteAndSaveLayoutAtNarrowLargeText() async throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        for language in ["en", "de"] {
            LanguageManager.setLanguage(language)
            let view = SessionSummaryView(workoutTitle: "Notes regression", durationSeconds: 60,
                totalCompletedSets: 0, totalVolumeKg: 0,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Bench Press", sets: [], targetSets: 1)],
                onBack: {}, onSaveAndClose: {}, workoutNote: .constant(note))
                .environment(\.sizeCategory, .extraExtraExtraLarge)
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
            window.windowScene = previousWindow?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            func scrollViews(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let scroll = try XCTUnwrap(scrollViews(host.view).first,
                "A note-only workout must show the scrollable summary with its note and Save action.")
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "workout-note-summary-\(language)-320-large"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}

/// Executes the shared import contract (gym/docs/history-import-fixtures.json) against the captured and derived
/// Strong/Hevy exports, plus behaviour beyond the fixtures. Android HistoryImportFixturesTest and HistoryImportTest
/// run the same cases.
final class HistoryImportTests: XCTestCase {
    private let gym = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardized
    private lazy var fixtures: [String: Any] = {
        let data = try! Data(contentsOf: gym.appendingPathComponent("docs/history-import-fixtures.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()
    private lazy var zone = TimeZone(identifier: fixtures["timeZone"] as! String)!
    private lazy var today = fixtures["today"] as! String
    private let catalog = HistoryImportCatalog.bundled()
    private lazy var current: [String: Any] = {
        let data = try! Data(contentsOf: gym.appendingPathComponent("scripts/history-import-audit/fixtures/current/manifest.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()
    private var cases: [[String: Any]] { (fixtures["cases"] as! [[String: Any]]) + (current["cases"] as! [[String: Any]]) }

    private func expectOf(_ testCase: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]
        if let base = testCase["base"] as? String, let baseCase = cases.first(where: { $0["id"] as? String == base }) {
            merged = expectOf(baseCase)
        }
        for (key, value) in testCase["expect"] as? [String: Any] ?? [:] { merged[key] = value }
        return merged
    }

    private func plan(_ data: Data, existing: [WorkoutSessionRecord] = [], unit: WeightUnit? = nil,
                      includeOverlaps: Bool = false, zone: TimeZone? = nil, today: String? = nil) throws -> HistoryImportPlan {
        let file = try HistoryImport.read(data, zone: zone ?? self.zone, today: today ?? self.today, untitled: "Workout")
        return HistoryImport.plan(file, unit: unit, existing: existing, includeOverlaps: includeOverlaps, catalog: catalog)
    }

    private func kg(_ value: Double?) -> String {
        let rounded = ((value ?? 0) * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", rounded)
    }

    private func describe(_ set: SessionSetLog) -> String {
        (set.isWarmup ? "W " : "") + "\(kg(set.weightKg))x\(set.reps ?? 0)" +
            set.setExtensions.map { " > \(kg($0.weightKg))x\($0.reps ?? 0)" }.joined()
    }

    private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @MainActor func testNoteLayoutAt320PointsWithLargeText() async throws {
        let oldLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(oldLanguage) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let host = UIHostingController(rootView: VStack(spacing: 12) {
                NoteField(titleKey: "notes.setup", text: .constant("Seat 4, chest pad 2, neutral grip.\nKeep this setup for next time."))
                NoteField(titleKey: "notes.workout", text: .constant(""))
                Spacer()
            }.padding(16).background(AppColors.background).environment(\.sizeCategory, .extraExtraExtraLarge))
            let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
            window.windowScene = previous?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 300_000_000)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "notes-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(host.view.bounds.width, 320)
            window.isHidden = true; previous?.makeKeyAndVisible()
        }
    }

    @MainActor func testConflictingImportPreviewAt320PointsWithLargeText() async throws {
        let oldLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(oldLanguage) }
        let first = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"))
        let conflict = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;85;5;;;;;"), existing: first.records)
        XCTAssertFalse(conflict.canImport)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            let host = UIHostingController(rootView: HistoryImportPreviewSheet(plan: conflict, fileName: "Strong.csv", importing: false,
                onChooseUnit: { _ in }, onIncludeOverlaps: { _ in }, onImport: {}, onDismiss: {})
                .environment(\.sizeCategory, .extraExtraExtraLarge))
            let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
            window.windowScene = previous?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 800)
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 300_000_000)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "import-conflict-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(host.view.bounds.width, 320)
            window.isHidden = true; previous?.makeKeyAndVisible()
        }
    }

    func testNotesRemainInDraftHistoryBackupAndSharedProgram() throws {
        let exercise = Exercise(id: "bench", name: "Bench", setupNote: "Seat 4\nNeutral grip")
        let workout = Workout(id: "w", day: 1, title: "Push", exercises: [exercise])
        var draft = ActiveSessionDraft(id: "s", programId: "p", workout: workout, startedAt: "2026-10-01T10:00:00Z",
            startedAtEpochMillis: 1, setsByExercise: ["bench": [ExerciseSetLog(setNumber: 1, weightKg: 50, completedReps: 8, isCompleted: true)]], note: "Another gym")
        let record = SessionProgress.from(draft: draft, nowEpochMillis: 1000).record(draft: draft, completedAtEpochMillis: 1000)
        draft.workout.exercises[0].setupNote = "Seat 2"
        XCTAssertEqual(record.exerciseLogs[0].setupNote, "Seat 4\nNeutral grip")
        XCTAssertEqual(record.workoutSnapshot?.exercises[0].setupNote, "Seat 4\nNeutral grip")
        XCTAssertEqual(record.note, "Another gym")
        let decoded = try JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
        let program = Program(id: "p", name: "Plan", workouts: [workout])
        let shared = try ProgramFileCodec.decode(ProgramFileCodec.encode(program, defaultRest: 90), defaultRest: 90)
        XCTAssertEqual(shared.workouts[0].exercises[0].setupNote, exercise.setupNote)
        let restored = try JSONDecoder().decode(WorkoutSessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored, record)
    }

    func testNotesFromStrongAndHevyArePreserved() throws {
        let strong = "Workout #;Date;Workout Name;Duration (sec);Exercise Name;Set Order;Weight (kg);Reps;RPE;Distance (meters);Seconds;Notes;Workout Notes\n1;2026-10-01 18:00:00;Push;3600;Bench Press (Barbell);1;100;5;;;;Seat 4;Other gym\n1;2026-10-01 18:00:00;Push;3600;Bench Press (Barbell);Note;;;;;;Neutral grip;Other gym"
        let saved = try plan(Data(strong.utf8)).records[0]
        XCTAssertEqual(saved.note, "Other gym")
        XCTAssertEqual(saved.exerciseLogs[0].setupNote, "Seat 4\nNeutral grip")
        let hevy = "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe\nPush,\"1 Oct 2026, 10:00\",\"1 Oct 2026, 11:00\",Other gym,Bench Press (Barbell),,Seat 4,0,normal,100,5,,,"
        let imported = try plan(Data(hevy.utf8)).records[0]
        XCTAssertEqual(imported.note, "Other gym")
        XCTAssertEqual(imported.exerciseLogs[0].setupNote, "Seat 4")
    }

    func testEverySharedCaseMatchesItsExpectedResult() throws {
        var checked = 0
        for testCase in cases {
            let id = testCase["id"] as! String
            let expect = expectOf(testCase)
            let data = try Data(contentsOf: gym.appendingPathComponent(testCase["file"] as! String))
            if let expected = testCase["sha256"] as? String {
                XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), expected, "\(id) untouched bytes")
            }
            checked += 1
            if let error = expect["error"] as? String {
                do {
                    _ = try plan(data, today: testCase["today"] as? String)
                    XCTFail("\(id) should be refused")
                } catch let failure as HistoryImportError {
                    XCTAssertEqual(failure.problems.first?.code, error, "\(id) error")
                    XCTAssertEqual(failure.problems.first?.line, expect["line"] as? Int, "\(id) line")
                }
                continue
            }
            let plan = try plan(data, today: testCase["today"] as? String)
            XCTAssertTrue(plan.problems.isEmpty, "\(id) plan problems: \(plan.problems)")
            let file = plan.file
            XCTAssertEqual(file.source.rawValue, expect["source"] as? String, "\(id) source")
            XCTAssertEqual(file.fileUnit?.rawValue, expect["fileUnit"] as? String, "\(id) unit")
            XCTAssertEqual(file.workoutsInFile, expect["workoutsInFile"] as? Int, "\(id) workoutsInFile")
            XCTAssertEqual(file.repeatedInFile, expect["repeatedInFile"] as? Int, "\(id) repeatedInFile")
            XCTAssertEqual(plan.records.count, expect["newWorkouts"] as? Int, "\(id) newWorkouts")
            XCTAssertEqual(file.nothingToImport, expect["nothingToImport"] as? Int, "\(id) nothingToImport")
            XCTAssertEqual(plan.workingSets, expect["workingSets"] as? Int, "\(id) workingSets")
            XCTAssertEqual(plan.warmupSets, expect["warmupSets"] as? Int, "\(id) warmupSets")
            XCTAssertEqual(plan.dropsAttached, expect["dropsAttached"] as? Int, "\(id) dropsAttached")
            XCTAssertEqual(plan.dropsSeparate, expect["dropsSeparate"] as? Int, "\(id) dropsSeparate")
            XCTAssertEqual(file.timedSets, expect["timedSets"] as? Int, "\(id) timedSets")
            XCTAssertEqual(file.distanceSets, expect["distanceSets"] as? Int, "\(id) distanceSets")
            XCTAssertEqual(file.setsWithoutReps, expect["setsWithoutReps"] as? Int, "\(id) setsWithoutReps")
            XCTAssertEqual(file.rpeValues, expect["rpeValues"] as? Int, "\(id) rpeValues")
            XCTAssertEqual(file.exerciseNotes, expect["exerciseNotes"] as? Int, "\(id) exerciseNotes")
            XCTAssertEqual(file.workoutDescriptions, expect["workoutDescriptions"] as? Int, "\(id) workoutDescriptions")
            XCTAssertEqual(file.supersetLinks, expect["supersetLinks"] as? Int, "\(id) supersetLinks")
            XCTAssertEqual(plan.libraryExercises, expect["libraryExercises"] as? Int, "\(id) libraryExercises")
            XCTAssertEqual(plan.customExercises, expect["customExercises"] as? Int, "\(id) customExercises")
            XCTAssertEqual(plan.records.reduce(0) { $0 + $1.totalVolumeKg }, (expect["volumeKg"] as! NSNumber).doubleValue, accuracy: 0.01, "\(id) volume")
            XCTAssertEqual(plan.records.reduce(0) { $0 + $1.durationSeconds }, expect["durationSeconds"] as? Int, "\(id) duration")
            let dates = expect["dates"] as! [String: Any]
            XCTAssertEqual(Set(plan.records.compactMap(\.performedDate)).count, dates["count"] as? Int, "\(id) date count")
            if let first = dates["first"] as? String { XCTAssertEqual(plan.firstDate, first, "\(id) first date") }
            if let last = dates["last"] as? String { XCTAssertEqual(plan.lastDate, last, "\(id) last date") }
            if let workouts = expect["workouts"] as? [[String: Any]] {
                let records = plan.records.sorted { instant($0.startedAt) < instant($1.startedAt) }
                XCTAssertEqual(records.count, workouts.count, "\(id) workouts")
                for (want, got) in zip(workouts, records) {
                    XCTAssertEqual(got.id, want["id"] as? String, "\(id) record id")
                    XCTAssertEqual(got.workoutTitle, want["title"] as? String, "\(id) title")
                    if let note = want["note"] as? String { XCTAssertEqual(got.note, note, "\(id) workout note") }
                    XCTAssertEqual(got.performedDate, want["performedDate"] as? String, "\(id) performedDate")
                    XCTAssertEqual(instant(got.startedAt), instant(want["startedAt"] as! String), "\(id) startedAt")
                    XCTAssertEqual(instant(got.completedAt), instant(want["completedAt"] as! String), "\(id) completedAt")
                    XCTAssertEqual(got.durationSeconds, want["durationSeconds"] as? Int, "\(id) durationSeconds")
                    XCTAssertEqual(got.totalCompletedSets, want["totalCompletedSets"] as? Int, "\(id) totalCompletedSets")
                    XCTAssertEqual(got.totalVolumeKg, (want["totalVolumeKg"] as! NSNumber).doubleValue, accuracy: 0.01, "\(id) totalVolumeKg")
                    XCTAssertEqual(got.isComplete, true, "\(id) complete")
                    let exercises = want["exercises"] as! [[String: Any]]
                    XCTAssertEqual(got.exerciseLogs.map(\.exerciseName), exercises.map { $0["name"] as! String }, "\(id) exercises")
                    for (e, log) in zip(exercises, got.exerciseLogs) {
                        XCTAssertEqual(log.exerciseId, e["id"] as? String, "\(id) \(log.exerciseName) id")
                        XCTAssertEqual(log.sets.map(describe), e["sets"] as? [String], "\(id) \(log.exerciseName) sets")
                        if let note = e["note"] as? String { XCTAssertEqual(log.setupNote, note, "\(id) \(log.exerciseName) note") }
                    }
                }
            }
            // Imported sets must restore from a backup like logged ones.
            for log in plan.records.flatMap(\.exerciseLogs) {
                let assisted = WorkoutSessionUtils.isAssisted(exerciseId: log.exerciseId, name: log.exerciseName)
                for set in log.sets { XCTAssertNil(IntensitySets.restoreError(set, assisted: assisted), "\(id) \(log.exerciseName) restores") }
                XCTAssertEqual(log.sets.map(\.setNumber), Array(1..<(log.sets.count + 1)), "\(id) set numbers")
            }
        }
        XCTAssertEqual(checked, 62 + (current["cases"] as! [[String: Any]]).count, "all captured and derived exports")
    }

    // MARK: Behaviour

    private let strongHeader = "Workout #;Date;Workout Name;Duration (sec);Exercise Name;Set Order;Weight (kg);Reps;RPE;Distance (meters);Seconds;Notes;Workout Notes"
    private let hevyHeader = "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe"
    private func strong(_ rows: String...) -> Data { Data(([strongHeader] + rows).joined(separator: "\n").utf8) }
    private func hevy(_ rows: [String]) -> Data { Data(([hevyHeader] + rows).joined(separator: "\n").utf8) }
    private func hevyRow(_ title: String, _ start: String, _ end: String, _ exercise: String, _ index: Int, _ type: String, _ weight: String, _ reps: String) -> String {
        "\(title),\"\(start)\",\"\(end)\",,\(exercise),,,\(index),\(type),\(weight),\(reps),,,"
    }
    private func refusal(_ data: Data) -> HistoryImportError {
        do { _ = try plan(data); XCTFail("expected a refusal") } catch let error as HistoryImportError { return error } catch { XCTFail("\(error)") }
        return HistoryImportError("none", line: 0)
    }
    private func native(_ start: String, _ end: String, _ date: String, id: String? = nil) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: id ?? "native-\(start)", programId: "p", workoutId: "w", workoutTitle: "Push", startedAt: start,
                             completedAt: end, durationSeconds: 3600, isComplete: true, performedDate: date)
    }

    func testOverflowingTextDurationsRefuseTheFile() throws {
        let header = "Date;Workout Name;Duration;Exercise Name;Set Order;Weight (kg);Reps"
        for duration in ["2147483647h", "9223372036854775807h", "999999999999999999999h", "2147483647m", "169h", "168h 1s"] {
            let error = refusal(Data("\(header)\n2026-10-01 18:00:00;Push;\(duration);Bench Press (Barbell);1;80;5".utf8))
            XCTAssertEqual(error.problems.first?.code, "duration", duration)
            XCTAssertEqual(error.problems.first?.line, 2, duration)
        }
        for duration in ["168h", "10080m", "604800s", "167h 59m 60s"] {
            let accepted = try plan(Data("\(header)\n2026-10-01 18:00:00;Push;\(duration);Bench Press (Barbell);1;80;5".utf8))
            XCTAssertEqual(accepted.records[0].durationSeconds, 604800, duration)
        }
    }

    func testAdjacentCopiesOfOneExportDoNotDoubleItsSets() {
        let rows = [
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);W;20;10;;;;;",
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;",
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);2;80;5;;;;;"
        ]
        let header = "Workout #;Date;Workout Name;Duration (sec);Exercise Name;Set Order;Weight (kg);Reps;RPE;Distance (meters);Seconds;Notes;Workout Notes"
        XCTAssertEqual(refusal(Data(([header] + rows + rows).joined(separator: "\n").utf8)).problems.first?.code, "repeatedSetRow")
        let hevyRows = [
            hevyRow("Push", "1 Oct 2026, 10:00", "1 Oct 2026, 11:00", "Bench Press (Barbell)", 0, "normal", "80", "5"),
            hevyRow("Push", "1 Oct 2026, 10:00", "1 Oct 2026, 11:00", "Bench Press (Barbell)", 1, "normal", "80", "5")
        ]
        let hevyHeader = "title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe"
        XCTAssertEqual(refusal(Data(([hevyHeader] + hevyRows + hevyRows).joined(separator: "\n").utf8)).problems.first?.code, "repeatedSetRow")
    }

    func testCollidingMinuteIdentitiesAreReportedInsteadOfSilentlySkipped() throws {
        let firstRow = "1;2026-10-01 18:00:05;Push;600;Bench Press (Barbell);1;80;5;;;;;"
        let secondRow = "2;2026-10-01 18:00:50;Push;600;Bench Press (Barbell);1;80;5;;;;;"
        XCTAssertEqual(refusal(strong(firstRow, secondRow)).problems.first?.code, "identityConflict")
        let first = try plan(strong(firstRow)).records
        let later = try plan(strong(secondRow), existing: first)
        XCTAssertEqual(later.problems.first?.code, "identityConflict")
        XCTAssertEqual(later.alreadyImported, 0)
        XCTAssertFalse(later.canImport)
        let changed = try plan(strong(firstRow.replacingOccurrences(of: ";80;5;", with: ";85;5;")), existing: first)
        XCTAssertEqual(changed.problems.first?.code, "identityConflict")
        XCTAssertFalse(changed.canImport)
    }

    func testReplayAllowsSourceMinutePrecisionAndAChangedDeviceZone() throws {
        let csv = strong("1;2026-10-01 18:00:45;Push;353;Bench Press (Barbell);1;80;5;;;;;")
        let first = try plan(csv).records
        XCTAssertEqual(try plan(csv, existing: first, zone: TimeZone(identifier: "America/New_York")!).alreadyImported, 1)
        let rounded = hevy([hevyRow("Push", "1 Oct 2026, 18:00", "1 Oct 2026, 18:06", "Bench Press (Barbell)", 0, "normal", "80", "5")])
        let replay = try plan(rounded, existing: first)
        XCTAssertEqual(replay.alreadyImported, 1)
        XCTAssertTrue(replay.problems.isEmpty)
    }

    func testTitleTruncationDoesNotChangeWorkoutIdentity() throws {
        let prefix = String(repeating: "A", count: 100)
        let imported = try plan(strong(
            "1;2026-10-01 18:00:00;\(prefix)x;600;Bench Press (Barbell);1;80;5;;;;;",
            "2;2026-10-01 18:00:00;\(prefix)y;600;Bench Press (Barbell);1;80;5;;;;;"
        ))
        XCTAssertEqual(Set(imported.records.map(\.id)).count, 2)
        XCTAssertEqual(imported.records.map(\.workoutTitle), [prefix, prefix])
        var legacy = imported.records[0]
        legacy.id = HistoryImport.recordId(start: ImportedDateTime(year: 2026, month: 10, day: 1, hour: 18, minute: 0, second: 0), title: prefix)
        let replay = try plan(strong("1;2026-10-01 18:00:00;\(prefix)x;600;Bench Press (Barbell);1;80;5;;;;;"), existing: [legacy])
        XCTAssertEqual(replay.problems.first?.code, "identityConflict")
        XCTAssertFalse(replay.canImport)
    }

    func testDisplayLimitsNeverSplitUnicodeSurrogates() throws {
        let source = String(repeating: "A", count: 99) + "🎉tail"
        let record = try plan(strong("1;2026-10-01 18:00:00;\(source);600;\(source);1;80;5;;;;;")).records[0]
        XCTAssertEqual(record.workoutTitle, String(repeating: "A", count: 99))
        XCTAssertEqual(record.exerciseLogs[0].exerciseName, String(repeating: "A", count: 99))
    }

    func testIdenticalReplayImportsNothing() throws {
        let csv = strong("1;2026-10-01 18:00:00;Push;3600;Bench Press (Barbell);1;100;5;;;;;")
        let first = try plan(csv)
        XCTAssertEqual(first.records.count, 1)
        let replay = try plan(csv, existing: first.records)
        XCTAssertEqual(replay.alreadyImported, 1)
        XCTAssertTrue(replay.records.isEmpty)
        XCTAssertFalse(replay.canImport)
    }

    func testSameDayWorkoutsWithOneTitleStayDistinct() throws {
        let strongPlan = try plan(strong(
            "1;2026-10-01 18:00:00;Push;3600;Bench Press (Barbell);1;100;5;;;;;",
            "2;2026-10-01 10:00:00;Push;1800;Bench Press (Barbell);1;100;5;;;;;",
            "3;2026-10-01 12:00:00;Legs;1800;Squat (Barbell);1;100;5;;;;;"
        ))
        XCTAssertEqual(strongPlan.records.count, 3)
        XCTAssertEqual(Set(strongPlan.records.map(\.id)).count, 3)
        let hevyPlan = try plan(hevy([
            hevyRow("Push", "1 Oct 2026, 10:00", "1 Oct 2026, 11:00", "Bench Press (Barbell)", 0, "normal", "100", "5"),
            hevyRow("Push", "1 Oct 2026, 18:00", "1 Oct 2026, 19:00", "Bench Press (Barbell)", 0, "normal", "100", "5")
        ]))
        XCTAssertEqual(hevyPlan.records.count, 2)
    }

    func testALaterExportOnlyAddsTheNewWorkout() throws {
        let older = try plan(strong("1;2026-10-01 10:00:00;Push;1800;Bench Press (Barbell);1;100;5;;;;;"))
        let later = try plan(strong(
            "1;2026-10-01 10:00:00;Push;1800;Bench Press (Barbell);1;100;5;;;;;",
            "2;2026-10-03 10:00:00;Pull;1800;Pull Up;1;0;8;;;;;"
        ), existing: older.records)
        XCTAssertEqual(later.alreadyImported, 1)
        XCTAssertEqual(later.records.map(\.performedDate), ["2026-10-03"])
    }

    func testWorkoutsLoggedHereAreHeldBackUnlessChosen() throws {
        let csv = strong("1;2026-10-01 18:30:00;Push;3600;Bench Press (Barbell);1;100;5;;;;;")
        let existing = [native("2026-10-01T15:00:00Z", "2026-10-01T16:00:00Z", "2026-10-01")]
        let held = try plan(csv, existing: existing)
        XCTAssertEqual(held.overlapping, 1)
        XCTAssertTrue(held.records.isEmpty)
        XCTAssertEqual(try plan(csv, existing: existing, includeOverlaps: true).records.count, 1)
        let apart = try plan(csv, existing: [native("2026-10-01T06:00:00Z", "2026-10-01T07:00:00Z", "2026-10-01")])
        XCTAssertEqual(apart.overlapping, 0)
        XCTAssertEqual(apart.records.count, 1)
    }

    func testImportedWorkoutsNeverHoldEachOtherBackByTime() throws {
        let first = try plan(strong("1;2026-10-01 18:00:00;Push;3600;Bench Press (Barbell);1;100;5;;;;;"))
        let second = try plan(strong("1;2026-10-01 18:30:00;Arms;1800;Bicep Curl (Barbell);1;30;10;;;;;"), existing: first.records)
        XCTAssertEqual(second.overlapping, 0)
        XCTAssertEqual(second.records.count, 1)
    }

    func testAnExportWithoutAWeightUnitWaitsForTheUsersChoice() throws {
        let csv = Data([
            "Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;Notes;Workout Notes;RPE",
            "2026-10-01 18:00:00;Push;1h 5m;Bench Press (Barbell);1;225;5;;;;;"
        ].joined(separator: "\n").utf8)
        let unchosen = try plan(csv)
        XCTAssertNil(unchosen.file.fileUnit)
        XCTAssertTrue(unchosen.needsUnit)
        XCTAssertFalse(unchosen.canImport)
        XCTAssertTrue(unchosen.records.isEmpty)
        let pounds = try plan(csv, unit: .lbs)
        XCTAssertEqual(pounds.records.first!.exerciseLogs.first!.sets.first!.weightKg!, 225 * WeightUnit.lbsToKg, accuracy: 1e-9)
        XCTAssertEqual(pounds.records.first!.durationSeconds, 3900)
        XCTAssertEqual(try plan(csv, unit: .kg).records.first!.exerciseLogs.first!.sets.first!.weightKg!, 225, accuracy: 1e-9)
        let large = Data(String(decoding: csv, as: UTF8.self).replacingOccurrences(of: ";225;5;", with: ";10000;5;").utf8)
        XCTAssertTrue(try plan(large, unit: .lbs).canImport)
        let kilograms = try plan(large, unit: .kg)
        XCTAssertFalse(kilograms.canImport)
        XCTAssertEqual(kilograms.problems.first?.code, "weight")
    }

    func testTheDeviceTimeZoneNeverMovesTheExportedDate() throws {
        let csv = strong("1;2026-10-01 23:56:57;Late;600;Bench Press (Barbell);1;100;5;;;;;")
        let record = try plan(csv, zone: TimeZone(identifier: "America/New_York")!).records.first!
        XCTAssertEqual(record.performedDate, "2026-10-01")
        XCTAssertEqual(instant(record.startedAt), instant("2026-10-02T03:56:57Z"))
    }

    func testDropRowsAttachOnlyWhenTheLoadGoesDown() throws {
        func sets(_ rows: [(String, String)], exercise: String = "Bench Press (Barbell)") throws -> [String] {
            let lines = rows.enumerated().map { i, row -> String in
                let parts = row.1.split(separator: "x").map(String.init)
                return hevyRow("T", "1 Oct 2026, 10:00", "1 Oct 2026, 11:00", exercise, i, row.0, parts[0], parts[1])
            }
            return try plan(hevy(lines)).records.first!.exerciseLogs.first!.sets.map(describe)
        }
        XCTAssertEqual(try sets([("warmup", "20x10"), ("dropset", "15x8")]), ["W 20x10", "15x8"])
        XCTAssertEqual(try sets([("normal", "80x8"), ("dropset", "90x5")]), ["80x8", "90x5"])
        let seven = try sets([("normal", "100x5")] + (1...7).map { ("dropset", "\(100 - $0 * 10)x5") })
        XCTAssertEqual(seven, ["100x5 > 90x5 > 80x5 > 70x5 > 60x5 > 50x5 > 40x5", "30x5"])
        XCTAssertEqual(try sets([("normal", "20x8"), ("dropset", "30x6")], exercise: "Pull Up (Assisted)"), ["20x8 > 30x6"])
        XCTAssertEqual(try sets([("normal", "20x8"), ("dropset", "0x6")]), ["20x8", "0x6"])
        XCTAssertEqual(try sets([("normal", "20x6"), ("dropset", "0x4")], exercise: "Pull Up (Weighted)"), ["20x6 > 0x4"])
    }

    func testUnknownNamesStayCustomAndBlankTitlesGetTheFallback() throws {
        let record = try plan(strong("1;2026-10-01 18:00:00;;600;Zercher Carry (Sandbag);1;60;10;;;;;")).records.first!
        XCTAssertEqual(record.workoutTitle, "Workout")
        XCTAssertNil(record.exerciseLogs.first!.exerciseId)
        XCTAssertEqual(record.exerciseLogs.first!.exerciseName, "Zercher Carry (Sandbag)")
    }

    func testReviewedAliasesKeepMovementIdentity() {
        XCTAssertEqual(catalog.match("Overhead Press (Barbell)")?.id, "standing-barbell-overhead-press")
        XCTAssertEqual(catalog.match("Standing Calf Raise (Machine)")?.id, "standing-machine-calf-raise")
        XCTAssertEqual(catalog.match("Pull-Up")?.id, "pull-ups")
        XCTAssertEqual(catalog.match("  BENCH  PRESS (Barbell) ")?.id, "barbell-bench-press")
        XCTAssertEqual(catalog.match("Barbell Bench Press")?.id, "barbell-bench-press")
        XCTAssertNil(catalog.match("Shoulder Press (Dumbbell)"))
    }

    func testValuesThatCannotBeReadRefuseTheWholeFile() throws {
        func firstProblem(_ row: String) -> String {
            let problem = refusal(strong(row)).problems.first!
            return "\(problem.code)@\(problem.line)"
        }
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80,5;5;;;;;"), "weight@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5.5;;;;;"), "reps@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;1000;;;;;"), "reps@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;11;;;;"), "rpe@2")
        XCTAssertEqual(firstProblem("1;2026-10-26 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"), "futureDate@2")
        XCTAssertEqual(firstProblem("1;1969-12-31 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"), "date@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);X;80;5;;;;;"), "setType@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;600; ;1;80;5;;;;;"), "exerciseName@2")
        XCTAssertEqual(firstProblem("1;2026-10-01 18:00:00;Push;999999;Bench Press (Barbell);1;80;5;;;;;"), "duration@2")
        XCTAssertEqual(try plan(strong("1;2026-10-25 08:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;")).records.count, 1)
    }

    func testUpToFiveProblemsAreReportedWithTheirLines() {
        let rows = (1...7).map { "\($0);2026-10-0\($0) 18:00:00;Push;600;Bench Press (Barbell);1;heavy;5;;;;;" }
        let problems = refusal(Data(([strongHeader] + rows).joined(separator: "\n").utf8)).problems
        XCTAssertEqual(problems.map(\.line), [2, 3, 4, 5, 6])
    }

    func testLineNumbersCountQuotedLineBreaks() {
        let csv = strong(
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;\"two\r\nlines\";",
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);2;bad;5;;;;;"
        )
        XCTAssertEqual(refusal(csv).problems.first?.line, 4)
    }

    func testStructuralProblemsRefuseTheFile() {
        func code(_ data: Data) -> String? {
            do { _ = try HistoryImport.read(data, zone: zone, today: today, untitled: "W"); return nil }
            catch let error as HistoryImportError { return error.problems.first?.code } catch { return nil }
        }
        XCTAssertEqual(code(Data([0xC3, 0x28])), "encoding")
        XCTAssertEqual(code(Data("\n\r\n".utf8)), "empty")
        XCTAssertEqual(code(Data("name,weight\nBench,100".utf8)), "unknownFormat")
        XCTAssertEqual(code(Data(count: 25 * 1024 * 1024 + 1)), "tooLarge")
        let conflicting = refusal(strong(
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;",
            "2;2026-10-02 18:00:00;Pull;600;Pull Up;1;0;5;;;;;",
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;85;5;;;;;"
        )).problems.first!
        XCTAssertEqual("\(conflicting.code)@\(conflicting.line)", "conflictingRepeat@4")
        let inconsistent = refusal(strong(
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;",
            "1;2026-10-02 18:00:00;Push;600;Bench Press (Barbell);2;80;5;;;;;"
        )).problems.first!
        XCTAssertEqual("\(inconsistent.code)@\(inconsistent.line)", "inconsistentWorkout@3")
    }

    func testHistoryKeepsAtMostTenThousandWorkouts() throws {
        let existing = (1...9_999).map { native("2020-01-01T00:00:00Z", "2020-01-01T01:00:00Z", "2020-01-01", id: "n\($0)") }
        let plan = try plan(strong(
            "1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;",
            "2;2026-10-02 18:00:00;Pull;600;Pull Up;1;0;5;;;;;"
        ), existing: existing)
        XCTAssertEqual(plan.roomLeft, 1)
        XCTAssertFalse(plan.canImport)
    }

    // MARK: Store

    @MainActor func testDiskImportFailurePreservesHistoryAndRetrySurvivesReopen() throws {
        struct InjectedFailure: Error {}
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        var fail = false
        let persistence = AppStatePersistence(databaseURL: url, beforeCommit: { if fail { throw InjectedFailure() } })
        var store = AppStore(persistence: persistence)
        let first = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"))
        XCTAssertEqual(try store.importHistory(first), 1)
        let before = store.state.history
        let later = try plan(strong("2;2026-10-03 18:00:00;Pull;600;Pull Up;1;0;12;;;;;"))
        fail = true
        XCTAssertThrowsError(try store.importHistory(later)) { error in
            XCTAssertEqual((error as? HistoryImportError)?.problems.first?.code, "saveFailed")
        }
        XCTAssertEqual(store.state.history, before)
        XCTAssertEqual(try persistence.load()?.history, before)
        fail = false
        store = AppStore(persistence: AppStatePersistence(databaseURL: url))
        XCTAssertEqual(store.state.history, before)
        XCTAssertEqual(try store.importHistory(later), 1)
        let reopened = AppStore(persistence: AppStatePersistence(databaseURL: url))
        XCTAssertEqual(reopened.state.history.count, before.count + 1)
        XCTAssertEqual(reopened.planHistoryImport(later.file, unit: nil, includeOverlaps: false).alreadyImported, 1)
    }

    @MainActor func testCurrentSourceExportsSurviveDiskReopenBackupRestoreAndReplay() throws {
        let captures = (current["cases"] as! [[String: Any]]).filter {
            $0["capture"] != nil || ($0["id"] as? String)?.hasSuffix("1000-sessions") == true
        }
        XCTAssertFalse(captures.isEmpty)
        for testCase in captures {
            let id = testCase["id"] as! String
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("history.sqlite")
            var store = AppStore(persistence: AppStatePersistence(databaseURL: url))
            let data = try Data(contentsOf: gym.appendingPathComponent(testCase["file"] as! String))
            let incoming = try plan(data, today: testCase["today"] as? String)
            XCTAssertTrue(incoming.canImport, id)
            XCTAssertEqual(try store.importHistory(incoming), incoming.records.count, id)
            let wanted = incoming.records.sorted { $0.id < $1.id }
            store = AppStore(persistence: AppStatePersistence(databaseURL: url))
            XCTAssertEqual(store.state.history.sorted { $0.id < $1.id }, wanted, "\(id) reopened")
            let replay = store.planHistoryImport(incoming.file, unit: nil, includeOverlaps: false)
            XCTAssertEqual(replay.alreadyImported, wanted.count, "\(id) replay")
            XCTAssertFalse(replay.canImport, id)
            XCTAssertTrue(store.restoreBackupJson(store.exportBackupJson()), "\(id) restore")
            store = AppStore(persistence: AppStatePersistence(databaseURL: url))
            XCTAssertEqual(store.state.history.sorted { $0.id < $1.id }, wanted, "\(id) restored")
        }
    }

    @MainActor func testBackupWriteFailurePreservesHistoryAndCanBeRetried() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: directory) }
        let persistence = AppStatePersistence(databaseURL: directory.appendingPathComponent("history.sqlite"))
        let store = AppStore(persistence: persistence)
        let first = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"))
        XCTAssertEqual(try store.importHistory(first), 1)
        let before = store.state.history
        let later = try plan(strong("2;2026-10-03 18:00:00;Pull;600;Pull Up;1;0;12;;;;;"))
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let backups = support.appendingPathComponent("import-backups")
        let saved = directory.appendingPathComponent("saved-backups")
        try manager.moveItem(at: backups, to: saved)
        defer {
            if manager.fileExists(atPath: saved.path) {
                try? manager.removeItem(at: backups)
                try? manager.moveItem(at: saved, to: backups)
            }
        }
        try Data("A file blocks the backup directory".utf8).write(to: backups)
        XCTAssertThrowsError(try store.importHistory(later))
        XCTAssertEqual(store.state.history, before)
        XCTAssertEqual(try persistence.load()?.history, before)
        try manager.removeItem(at: backups)
        try manager.moveItem(at: saved, to: backups)
        XCTAssertEqual(try store.importHistory(later), 1)
    }

    @MainActor func testStalePreviewRefusesConflictingHistoryBeforeSaving() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let pending = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;80;5;;;;;"))
        let changed = try plan(strong("1;2026-10-01 18:00:00;Push;600;Bench Press (Barbell);1;85;5;;;;;"))
        XCTAssertEqual(try store.importHistory(changed), 1)
        let before = store.state.history
        XCTAssertThrowsError(try store.importHistory(pending)) { error in
            XCTAssertEqual((error as? HistoryImportError)?.problems.first?.code, "identityConflict")
        }
        XCTAssertEqual(store.state.history, before)
    }

    @MainActor func testImportPersistsAndAReplayAddsNothing() throws {
        let persistence = AppStatePersistence(inMemory: true)
        var store = AppStore(persistence: persistence)
        let before = store.state.history
        let file = try AppStore.readHistoryImport(strong(
            "1;2026-10-01 23:56:57;IMPORT TEST;353;Bench Press (Barbell);W;20;10;;;;;",
            "1;2026-10-01 23:56:57;IMPORT TEST;353;Bench Press (Barbell);1;80.5;8;;;;;",
            "1;2026-10-01 23:56:57;IMPORT TEST;353;Bench Press (Barbell);D;60.25;10;;;;;"
        ))
        XCTAssertEqual(try store.importHistory(store.planHistoryImport(file, unit: nil, includeOverlaps: false)), 1)
        store = AppStore(persistence: persistence)  // reopen from the stored state
        let imported = store.state.history.first { $0.id.hasPrefix(HistoryImport.idPrefix) }
        XCTAssertEqual(imported?.performedDate, "2026-10-01")
        XCTAssertEqual(imported?.exerciseLogs.first?.sets.last?.technique, "drop")
        XCTAssertTrue(store.state.calendarHistory?.entries.contains { $0.id == "session:\(imported!.id)" && $0.status == .completed } == true)
        let replay = store.planHistoryImport(file, unit: nil, includeOverlaps: false)
        XCTAssertEqual(replay.alreadyImported, 1)
        XCTAssertThrowsError(try store.importHistory(replay)) { error in
            XCTAssertEqual((error as? HistoryImportError)?.problems.first?.code, "nothingNew")
        }
        XCTAssertEqual(store.state.history.count, before.count + 1)
    }
}

final class SupersetTests: XCTestCase {
    private func draft(_ a: Int = 2, _ b: Int = 2) -> ActiveSessionDraft {
        let exercises = [Exercise(id: "a", name: "Curl", sets: a, restSeconds: 60, supersetId: "pair"),
                         Exercise(id: "b", name: "Extension", sets: b, restSeconds: 90, supersetId: "pair"),
                         Exercise(id: "c", name: "Row", sets: 1, restSeconds: 60)]
        var sets: [String: [ExerciseSetLog]] = [:]
        for exercise in exercises {
            sets[exercise.id] = (1...exercise.sets!).map { number in
                ExerciseSetLog(id: "\(exercise.id)\(number)", setNumber: number, weightInput: "20", repsInput: "8", weightKg: 20, completedReps: 8)
            }
        }
        return ActiveSessionDraft(id: "s", programId: "p", workout: Workout(id: "w", day: 1, title: "Arms", exercises: exercises),
            startedAt: "2026-10-24T10:00:00Z", startedAtEpochMillis: 1, setsByExercise: sets)
    }
    private func tick(_ d: ActiveSessionDraft, _ id: String, _ index: Int = 0, now: Int64 = 10_000) -> ActiveSessionDraft {
        WorkoutSessionUtils.toggledSet(d, exerciseId: id, index: index, now: now)
    }
    @MainActor func testPairLabelsAt320PointsInEnglishAndTurkish() async throws {
        let oldLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(oldLanguage) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let host = UIHostingController(rootView: ScrollView {
                BuilderWorkoutCard(workout: draft().workout, expanded: true, onToggle: {}, onEdit: {}, onAdd: {},
                    onEditExercise: { _ in }, onMove: { _, _ in }, onRemove: { _ in }).padding(16)
            }.background(AppColors.background).environment(\.sizeCategory, .extraExtraExtraLarge))
            let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800)); window.windowScene = previous?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 800); window.rootViewController = host
            window.makeKeyAndVisible(); host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "supersets-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; previous?.makeKeyAndVisible()
        }
    }

    func testPairsToggleAndNeverBecomeCircuits() {
        let w = draft().workout
        XCTAssertEqual(Supersets.label(w, "a"), "A1"); XCTAssertEqual(Supersets.label(w, "b"), "A2")
        XCTAssertFalse(Supersets.canPair(w, "b")); XCTAssertFalse(Supersets.canPair(w, "c"))
        let unpaired = Supersets.toggled(w, "b")
        XCTAssertTrue(unpaired.exercises.allSatisfy { $0.supersetId == nil })
        XCTAssertEqual(Supersets.pair(Supersets.toggled(unpaired, "b", groupId: "new"), "b")?.map(\.id), ["b", "c"])
        var invalid = w.exercises
        for index in invalid.indices { invalid[index].supersetId = "three" }
        XCTAssertTrue(Supersets.normalized(invalid).allSatisfy { $0.supersetId == nil })
        let copy = ProgramEditing.copyWorkout(w, day: 2)
        XCTAssertEqual(copy.exercises.map { Supersets.label(copy, $0.id) }, ["A1", "A2", nil])
    }
    func testPairAlternatesAndOnlySecondMemberStartsRoundRest() {
        let a = tick(draft(), "a")
        XCTAssertNil(a.restTimer); XCTAssertEqual(Supersets.nextIndex(a), 1)
        var b = tick(a, "b"); b.currentExerciseIndex = 1
        XCTAssertEqual(b.restTimer?.setId, "b1"); XCTAssertEqual(b.restTimer?.totalSeconds, 90)
        XCTAssertEqual(Supersets.nextIndex(b), 0)
        let next = tick(b, "a", 1)
        XCTAssertNil(next.restTimer); XCTAssertTrue(next.setsByExercise["a"]![1].isCompleted)
    }
    func testUnequalCountsAndSkippedPartnerHaveSoloRest() {
        let round = tick(tick(draft(3, 1), "a"), "b")
        XCTAssertEqual(tick(round, "a", 1).restTimer?.setId, "a2")
        XCTAssertEqual(tick(tick(draft(3, 2), "a"), "a", 1).restTimer?.setId, "a2")
        var doneA = tick(tick(draft(), "a"), "a", 1); doneA.currentExerciseIndex = 1
        XCTAssertEqual(Supersets.nextIndex(doneA), 2)
    }
    func testWarmupsNeverJoinPairRounds() {
        var d = draft()
        let warm = ExerciseSetLog(id: "warm", setNumber: 1, weightInput: "10", repsInput: "8", weightKg: 10, completedReps: 8, isWarmup: true)
        d.setsByExercise["a"]!.insert(warm, at: 0)
        XCTAssertEqual(tick(d, "a").restTimer?.setId, "warm")
    }
    func testUndoCancelsOnlyItsOwnRest() {
        let both = tick(tick(draft(), "a"), "b")
        let undoA = tick(both, "a")
        XCTAssertEqual(undoA.restTimer, both.restTimer)
        XCTAssertTrue(undoA.setsByExercise["b"]![0].isCompleted)
        XCTAssertNil(tick(both, "b").restTimer)
    }
    func testIntensityKeepsItsOwnRestAndCountsTheSetOnce() {
        var d = tick(tick(draft(), "a"), "b")
        let exercise = d.workout.exercises[1]
        var set = IntensitySets.addingExtension(.restPause, to: d.setsByExercise["b"]![0], unit: .kg, barbell: false)
        set = IntensitySets.editingExtension(set, at: 0, weight: "", reps: "3", exercise: exercise, unit: .kg)
        set = IntensitySets.togglingExtension(set, at: 0, exercise: exercise, unit: .kg)
        d.setsByExercise["b"]![0] = set
        d.restTimer = IntensitySets.restAfterTickingExtension(in: d, setId: set.id, exercise: exercise, nowEpochMillis: 12_000)
        XCTAssertEqual(d.restTimer?.endsAtEpochMillis, 102_000)
        let progress = SessionProgress.from(draft: d, nowEpochMillis: 20_000)
        XCTAssertEqual(progress.completedSets, 2)
        XCTAssertEqual(progress.exerciseLogs[1].sets[0].setExtensions.first?.reps, 3)
        XCTAssertNil(tick(d, "b").restTimer)
    }
    func testInterruptedDraftAndSharedProgramRetainPairs() throws {
        var d = tick(tick(draft(), "a"), "b"); d.currentExerciseIndex = 1
        let resumed = try JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(Supersets.nextIndex(resumed), 0); XCTAssertEqual(resumed.restTimer, d.restTimer)
        let program = Program(id: "p", name: "Pair", workouts: [d.workout])
        let shared = try ProgramFileCodec.decode(ProgramFileCodec.encode(program))
        XCTAssertEqual(shared.workouts[0].exercises.map(\.supersetId), ["pair", "pair", nil])
        let record = SessionProgress.from(draft: d, nowEpochMillis: 20_000).record(draft: d, completedAtEpochMillis: 20_000)
        let restored = try JSONDecoder().decode(WorkoutSessionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.workoutSnapshot?.exercises[0].supersetId, "pair")
        XCTAssertEqual(restored.exerciseLogs.map(\.exerciseName), ["Curl", "Extension", "Row"])
    }
    func testReorderingAPairDoesNotSkipOrLoopOtherExercises() {
        var d = draft(); d.workout.exercises.swapAt(1, 2)
        var complete = tick(tick(tick(tick(d, "a"), "b"), "a", 1), "b", 1)
        complete.currentExerciseIndex = 2; XCTAssertEqual(Supersets.nextIndex(complete), 1)
        complete.currentExerciseIndex = 1; XCTAssertNil(Supersets.nextIndex(complete))
    }
}

final class RestCountdownTests: XCTestCase {
    private func draft(now: Int64 = 10_000) -> ActiveSessionDraft {
        ActiveSessionDraft(id: "countdown-fixture", programId: "p", workout: Workout(id: "w", day: 1, title: "Arms", exercises: [Exercise(id: "a", name: "Curl")]),
            startedAt: "2026-10-25T00:00:00Z", startedAtEpochMillis: now,
            restTimer: RestTimerState(exerciseName: "Curl", totalSeconds: 90, isRunning: true,
                endsAtEpochMillis: now + 90_000, pausedSecondsRemaining: 90, setId: "a1"))
    }
    @MainActor func testLockScreenContentAt320PointsWithLargeEnglishAndTurkishText() async throws {
        let oldLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(oldLanguage) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            var running = RestLiveActivitySnapshot.from(draft(now: Int64(Date().timeIntervalSince1970 * 1000)), now: Int64(Date().timeIntervalSince1970 * 1000))!.content
            running.exerciseName = language == "tr" ? "Göğüs destekli dambıl row" : "Chest-supported dumbbell row"
            var paused = running; paused.isRunning = false; paused.deadline = nil; paused.remainingSeconds = 35
            let host = UIHostingController(rootView: VStack(spacing: 16) {
                RestActivityContent(state: running).padding(16).background(Color(uiColor: .secondarySystemBackground))
                RestActivityContent(state: paused).padding(16).background(Color(uiColor: .secondarySystemBackground))
                Spacer()
            }.preferredColorScheme(.dark).environment(\.sizeCategory, .extraExtraExtraLarge))
            let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500)); window.windowScene = previous?.windowScene
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 500); window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded(); try await Task.sleep(nanoseconds: 300_000_000)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "rest-activity-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; previous?.makeKeyAndVisible()
        }
    }

    func testProjectionUsesTheSameDeadlineAndPausesWithoutAdvancing() {
        var d = draft()
        let running = RestLiveActivitySnapshot.from(d, now: 20_000)!
        XCTAssertEqual(running.content.deadline, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(running.content.isRunning)
        d.restTimer!.isRunning = false; d.restTimer!.endsAtEpochMillis = nil; d.restTimer!.pausedSecondsRemaining = 35
        let paused = RestLiveActivitySnapshot.from(d, now: 999_999)!
        XCTAssertFalse(paused.content.isRunning); XCTAssertNil(paused.content.deadline)
        XCTAssertEqual(paused.content.remainingSeconds, 35)
    }
    func testResumedAndAdjustedRestUsesItsNewDeadline() {
        var d = draft()
        d.restTimer!.endsAtEpochMillis = 200_000; d.restTimer!.totalSeconds = 120
        let adjusted = RestLiveActivitySnapshot.from(d, now: 20_000)!
        XCTAssertEqual(adjusted.content.deadline, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(adjusted.content.remainingSeconds, 120)
    }
    func testCanceledExpiredAndEndedWorkoutsHaveNoDisplay() {
        var d = draft()
        XCTAssertNil(RestLiveActivitySnapshot.from(d, now: 100_000))
        d.restTimer = nil
        XCTAssertNil(RestLiveActivitySnapshot.from(d, now: 20_000))
        XCTAssertNil(RestLiveActivitySnapshot.from(nil, now: 20_000))
    }
    func testActivityContentRoundTripsWithoutWorkoutNotes() throws {
        var d = draft(); d.note = "Private session note"; d.workout.exercises[0].setupNote = "Private setup"
        let state = RestLiveActivitySnapshot.from(d, now: 20_000)!.content
        let data = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private"))
        XCTAssertEqual(try JSONDecoder().decode(RestActivityAttributes.ContentState.self, from: data), state)
    }
    @MainActor func testNativeActivityUpdatesAndEndsWhenAvailable() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities unavailable on this simulator.") }
        guard UIApplication.shared.applicationState == .active else { throw XCTSkip("Native ActivityKit requests require a foreground app.") }
        let coordinator = RestLiveActivityCoordinator(enabled: true)
        defer { coordinator.sync(nil) }
        var d = draft(now: Int64(Date().timeIntervalSince1970 * 1000))
        d.id = "countdown-native"
        coordinator.sync(d); try await settle(coordinator)
        if let error = coordinator.lastError, error.localizedCaseInsensitiveContains("unsupportedTarget") {
            throw XCTSkip("ActivityKit does not support the current test target: \(error)")
        }
        XCTAssertNil(coordinator.lastError)
        let activity = try XCTUnwrap(Activity<RestActivityAttributes>.activities.first { $0.attributes.sessionId == d.id })
        XCTAssertTrue(activity.content.state.isRunning)
        d.restTimer!.isRunning = false; d.restTimer!.endsAtEpochMillis = nil; d.restTimer!.pausedSecondsRemaining = 35
        coordinator.sync(d); try await settle(coordinator)
        XCTAssertFalse(activity.content.state.isRunning); XCTAssertEqual(activity.content.state.remainingSeconds, 35)
        d.restTimer!.isRunning = true; d.restTimer!.endsAtEpochMillis = Int64(Date().timeIntervalSince1970 * 1000) + 120_000
        coordinator.sync(d); try await settle(coordinator)
        XCTAssertTrue(activity.content.state.isRunning)
        coordinator.sync(nil); try await settle(coordinator)
        XCTAssertFalse(Activity<RestActivityAttributes>.activities.contains { $0.activityState == .active || $0.activityState == .stale })
    }
    @MainActor private func settle(_ coordinator: RestLiveActivityCoordinator) async throws {
        for _ in 0..<200 {
            if !coordinator.processing { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("ActivityKit updates did not settle")
    }
}
