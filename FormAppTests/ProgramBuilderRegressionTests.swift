import XCTest
import SwiftUI
@testable import FormApp

final class ProgramBuilderRegressionTests: XCTestCase {
    private var savedDefaults: [(String, Any?)] = []

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        let keys = ["stored_app_state", "active_session_v1", "seeded_starters_v9", "seeded_starters_v10", "seeded_starters_v11"]
        savedDefaults = keys.map { ($0, defaults.object(forKey: $0)) }
        defaults.removeObject(forKey: "stored_app_state")
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        defaults.set(true, forKey: "seeded_starters_v11")
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func fixture() -> Program {
        let exercise = Exercise(id: "bench-instance", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", cues: "Controlled descent.\nKeep your feet planted.", avoid: "Do not bounce.", sets: 3, reps: RepTarget(min: 8, max: 12, perSide: false), restSeconds: 120, movementType: "press", movementAssetId: "barbell-bench-press")
        return Program(id: "builder-fixture", name: "Builder fixture", description: "Build a weekly plan.", guidelines: ["Keep the targets controlled."], workouts: [Workout(id: "upper", day: 1, title: "Upper A", exercises: [exercise], targetMuscles: ["chest"])], coverId: "machines")
    }

    func testFocusRanksPrimaryAreasBySetsAndCapsHighlights() {
        func exercise(_ id: String, _ sets: Int) -> Exercise { Exercise(name: id, exerciseId: id, sets: sets) }
        let workout = Workout(day: 1, title: "Full body", focus: "Old focus", exercises: [
            exercise("barbell-bench-press", 4), exercise("pec-deck-fly", 3), exercise("lat-pulldown", 6),
            exercise("dumbbell-lateral-raise", 5), exercise("leg-extension", 4), exercise("standing-machine-calf-raise", 3)
        ], targetMuscles: ["abs"])
        XCTAssertEqual(workout.resolvedMuscles, [.chest, .lats, .shoulders, .quadriceps])
        XCTAssertEqual(workout.exercises.count, 6)
        var changed = workout
        changed.exercises.reverse()
        XCTAssertEqual(changed.resolvedMuscles, workout.resolvedMuscles)
        changed.exercises[0].sets = 10
        XCTAssertEqual(changed.resolvedMuscles.first, .calves)
        changed.exercises = Array(workout.exercises.dropFirst(2))
        XCTAssertFalse(changed.resolvedMuscles.contains(.chest))
        changed.exercises = [exercise("barbell-row", 4), exercise("standing-barbell-overhead-press", 3)]
        XCTAssertEqual(changed.resolvedMuscles, [.trapezius, .lats, .shoulders])
    }

    func testFocusIgnoresSecondaryMusclesAndLegacyOverrides() {
        var workout = Workout(day: 1, title: "Custom", focus: "Chest", exercises: [
            Exercise(name: "Custom movement", exerciseId: "custom-unknown", movementType: "press")
        ], targetMuscles: ["chest"])
        XCTAssertTrue(workout.resolvedMuscles.isEmpty)
        workout.exercises = []
        XCTAssertTrue(workout.resolvedMuscles.isEmpty)
        workout.exercises = [Exercise(name: "Bench", exerciseId: "barbell-bench-press")]
        XCTAssertEqual(workout.resolvedMuscles, [.chest])
        workout.exercises = [Exercise(name: "Press", exerciseId: "standing-barbell-overhead-press")]
        XCTAssertEqual(workout.resolvedMuscles, [.shoulders])
    }

    @MainActor
    func testTrainingDayEditorAutomaticFocusAtNarrowWidthsInAllLanguages() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "es", "fr"] {
            LanguageManager.setLanguage(language)
            for empty in [true, false] {
                var workout = fixture().workouts[0]
                if empty { workout.exercises = []; workout.title = "" }
                let root = BuilderWorkoutEditor(workout: workout, isNew: empty, occupiedDays: [], onSave: { _ in }, onRemove: nil, onCopy: nil)
                    .environment(\.sizeCategory, .extraExtraExtraLarge)
                let host = UIHostingController(rootView: root)
                let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
                window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                let name = "training-day-\(language)-\(empty ? "empty" : "focus")"
                try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; previousWindow?.makeKeyAndVisible()
            }
        }
    }

    func testEveryBundledProgramMeetsPublicContract() throws {
        let names = ["01_aesthetic_hypertrophy", "02_powerbuilding_strength", "03_classic_ppl", "04_full_body_classic", "05_home_forge_dumbbells", "06_athletic_performance", "07_upper_lower", "08_machine_foundation"]
        for name in names {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json"))
            XCTAssertNoThrow(try ProgramFileCodec.decode(Data(contentsOf: url)), name)
        }
    }

    func testActualAndroidReexportPreservesIOSFieldsAndCover() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "android-builder-v5", withExtension: "json"))
        let incoming = try ProgramFileCodec.decode(Data(contentsOf: url))
        XCTAssertEqual(incoming, fixture())
        XCTAssertEqual(try ProgramFileCodec.decode(ProgramFileCodec.encode(incoming)), fixture())
    }

    func testPublicEncodingUsesNotesArraysAndCoverRoundTrips() throws {
        let program = fixture()
        let data = try ProgramFileCodec.encode(program)
        try data.write(to: URL(fileURLWithPath: "/tmp/program-builder-ios-v5.json"))
        let decoded = try ProgramFileCodec.decode(data)
        XCTAssertEqual(decoded, program)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, 5)
        let p = try XCTUnwrap(root["program"] as? [String: Any])
        let workouts = try XCTUnwrap(p["workouts"] as? [[String: Any]])
        let exercises = try XCTUnwrap(workouts[0]["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises[0]["cues"] as? [String], ["Controlled descent.", "Keep your feet planted."])
        XCTAssertEqual(exercises[0]["avoid"] as? [String], ["Do not bounce."])
        XCTAssertEqual(try ProgramFileCodec.decode(JSONEncoder().encode(AppStore.ProgramFileEnvelope(program: program))), program)
    }

    func testV4IOSNoteStringsRemainCompatibleButV5IsStrict() throws {
        let old = #"{"format":"form.program","schemaVersion":4,"program":{"id":"p","name":"Plan","workouts":[{"id":"w","day":1,"title":"Upper","exercises":[{"id":"e","name":"Custom","cues":"Line one\nLine two","avoid":"","prescription":"5 × 5"}]}]}}"#
        let decoded = try ProgramFileCodec.decode(Data(old.utf8), defaultRest: 180)
        XCTAssertEqual(decoded.workouts[0].exercises[0].sets, 5)
        XCTAssertEqual(decoded.workouts[0].exercises[0].restSeconds, 180)
        XCTAssertEqual(decoded.workouts[0].exercises[0].cues, "Line one\nLine two")
        XCTAssertThrowsError(try ProgramFileCodec.decode(Data(old.replacingOccurrences(of: "\"schemaVersion\":4", with: "\"schemaVersion\":5").utf8)))
    }

    func testStrictFileRejectsInvalidRangesTypesIDsAndUnknownFields() throws {
        let input = #"{"format":"form.program","schemaVersion":5,"program":{"id":"p","name":"Plan","workouts":[{"id":"w","day":1,"title":"Upper","exercises":[{"id":"e","name":"Custom","sets":3,"reps":{"min":8,"max":12},"restSeconds":120}]}]}}"#
        let mutations = [
            input.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":99"),
            input.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":true"),
            input.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":3.5"),
            input.replacingOccurrences(of: "\"min\":8", with: "\"min\":13"),
            input.replacingOccurrences(of: "\"restSeconds\":120", with: "\"restSeconds\":901"),
            input.replacingOccurrences(of: "\"name\":\"Plan\"", with: "\"name\":\" \""),
            input.replacingOccurrences(of: "\"id\":\"e\"", with: "\"id\":\"invalid id\""),
            input.replacingOccurrences(of: "\"id\":\"e\"", with: "\"id\":\"e\\n\""),
            input.replacingOccurrences(of: "\"sets\":3", with: "\"unknown\":true,\"sets\":3"),
            input.replacingOccurrences(of: "\"sets\":3", with: "\"sets\":3,\"s\\u0065ts\":4"),
            input.replacingOccurrences(of: "\"reps\":{", with: "\"prescription\":\"legacy\",\"reps\":{")
        ]
        for json in mutations { XCTAssertThrowsError(try ProgramFileCodec.decode(Data(json.utf8)), json) }
        XCTAssertNoThrow(try ProgramFileCodec.decode(Data(input.utf8)))
        var duplicate = fixture(); duplicate.workouts[0].exercises.append(duplicate.workouts[0].exercises[0])
        XCTAssertThrowsError(try ProgramFileCodec.encode(duplicate))
        var tooMany = fixture(); tooMany.workouts[0].exercises = (1...101).map { Exercise(id: "e-\($0)", name: "Custom") }
        XCTAssertThrowsError(try ProgramFileCodec.encode(tooMany))
    }

    func testIndependentCopiesAndScopedUndoPreserveLaterEdits() throws {
        let original = fixture()
        let copy = ProgramEditing.copyProgram(original)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertNotEqual(copy.workouts[0].id, original.workouts[0].id)
        XCTAssertNotEqual(copy.workouts[0].exercises[0].id, original.workouts[0].exercises[0].id)
        XCTAssertEqual(copy.workouts[0].exercises[0].exerciseId, original.workouts[0].exercises[0].exerciseId)
        XCTAssertEqual(copy.coverId, original.coverId)
        var edited = original; let removed = edited.workouts[0].exercises.removeFirst(); edited.name = "Later rename"
        let restored = try XCTUnwrap(ProgramRemovalUndo.exercise("upper", removed, 0).restoring(edited))
        XCTAssertEqual(restored.name, "Later rename")
        XCTAssertEqual(restored.workouts[0].exercises, original.workouts[0].exercises)
        var occupied = original; occupied.workouts = [Workout(day: 1, title: "New day")]
        XCTAssertNil(ProgramRemovalUndo.workout(original.workouts[0], 0).restoring(occupied))
    }

    @MainActor
    func testDeletingActiveAndFinalProgramsPreservesHistoryAndSupportsAnEmptyLibrary() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        XCTAssertTrue(store.addProgram(fixture()))
        var state = store.state
        state.history = [WorkoutSessionRecord(id: "preserved-history", programId: fixture().id, workoutId: "upper", workoutTitle: "Upper A",
            startedAt: "2026-10-14T00:00:00Z", completedAt: "2026-10-14T00:10:00Z", durationSeconds: 600,
            totalVolumeKg: 1200, totalCompletedSets: 3, exerciseLogs: [])]
        XCTAssertTrue(store.saveState(state, durable: true))
        let history = store.state.history
        XCTAssertTrue(store.deleteProgram(withId: fixture().id))
        XCTAssertFalse(store.state.activeProgramId.isEmpty)
        for id in store.state.programs.map(\.id) { XCTAssertTrue(store.deleteProgram(withId: id)) }
        XCTAssertEqual(store.state.programs, [])
        XCTAssertEqual(store.state.activeProgramId, "")
        XCTAssertEqual(store.state.history, history)
        let reloaded = AppStore(persistence: store.statePersistence)
        XCTAssertEqual(reloaded.state.programs, [])
        XCTAssertEqual(reloaded.state.history, history)
    }

    func testDraftStorageDoesNotChangeSavedProgramAndCanBeDiscarded() throws {
        let suite = "program-builder-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = fixture(); var edited = original; edited.name = "Unsaved"
        let draft = ProgramBuilderDraft(program: edited, original: original)
        ProgramBuilderDraftStore.save(draft, id: original.id, defaults: defaults)
        XCTAssertEqual(ProgramBuilderDraftStore.load(original.id, defaults: defaults), draft)
        XCTAssertEqual(original.name, "Builder fixture")
        ProgramBuilderDraftStore.clear(original.id, defaults: defaults)
        XCTAssertNil(ProgramBuilderDraftStore.load(original.id, defaults: defaults))
    }

    @MainActor
    func testUserProgramOverridesRemainVisibleAndUntouchedTemplatesTranslate() throws {
        let previous = LanguageManager.shared.languagePreference; defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("tr")
        let original = try XCTUnwrap(AppStore.loadBundledStarterPrograms().first)
        XCTAssertNotEqual(original.displayName, original.name)
        var renamed = original; renamed.name = "My program"; renamed.description = "My description"; renamed.guidelines = []
        XCTAssertEqual(renamed.displayName, "My program")
        XCTAssertEqual(renamed.displayDescription, "My description")
        XCTAssertEqual(renamed.displayGuidelines, [])
        let w = original.workouts[0]
        var changed = w; changed.title = "My workout"; changed.focus = "My focus"
        XCTAssertEqual(changed.displayTitle(programId: original.id), "My workout")
        XCTAssertEqual(changed.displayFocus(programId: original.id), w.displayFocus(programId: original.id))
        XCTAssertEqual(changed.focus, "My focus")
    }

    @MainActor
    func testCustomAndClearedExerciseGuidanceStayVisibleAfterReload() throws {
        let previous = LanguageManager.shared.languagePreference; defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("tr")
        let persistence = AppStatePersistence(inMemory: true)
        let store = AppStore(persistence: persistence)
        for reference in ["barbell-bench-press", nil] as [String?] {
            var program = fixture()
            program.id += reference == nil ? "-legacy" : "-canonical"
            program.workouts[0].exercises[0].exerciseId = reference
            program.workouts[0].exercises[0].cues = "My specific cue"
            program.workouts[0].exercises[0].avoid = ""
            XCTAssertTrue(store.addProgram(program, activate: false))
            let reloaded = AppStore(persistence: persistence)
            let exercise = try XCTUnwrap(reloaded.state.programs.first { $0.id == program.id }?.workouts.first?.exercises.first)
            XCTAssertEqual(exercise.cues, "My specific cue")
            XCTAssertEqual(exercise.displayCues, "My specific cue")
            XCTAssertEqual(exercise.avoid, "")
            XCTAssertEqual(exercise.displayAvoid, "")
        }
    }

    @MainActor
    func testImportPreviewBlocksLiveSessionAndStaleReplacement() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        var program = fixture(); program.workouts[0].day = store.weekCalendar.today + 1
        XCTAssertTrue(store.addProgram(program))
        var incoming = program; incoming.workouts = []
        let file = try ProgramFileCodec.encode(incoming)
        let preview = try store.previewProgramImport(jsonData: file)
        XCTAssertTrue(preview.changes.contains { $0.kind == "removed" })
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: program.workouts[0], allowPast: true))
        XCTAssertThrowsError(try store.previewProgramImport(jsonData: file))
        XCTAssertThrowsError(try store.applyProgramImport(preview))
        XCTAssertEqual(store.state.programs.first { $0.id == program.id }, program)
        store.abandonActiveSession()
        var newer = program; newer.name = "Newer edit"; XCTAssertTrue(store.updateProgram(newer))
        XCTAssertThrowsError(try store.applyProgramImport(preview))
        XCTAssertEqual(store.state.programs.first { $0.id == program.id }, newer)
    }

    @MainActor
    func testFailedProgramSaveDoesNotPublishSuccessOrReplaceData() throws {
        struct Failure: Error { }
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw Failure() } })
        let store = AppStore(persistence: persistence)
        try persistence.flush()
        let initial = fixture(); XCTAssertTrue(store.addProgram(initial, activate: false))
        let before = store.state
        fail = true
        var changed = initial; changed.name = "Failed edit"
        XCTAssertFalse(store.updateProgram(changed))
        XCTAssertEqual(store.state.programs, before.programs)
        XCTAssertEqual(store.state.activeProgramId, before.activeProgramId)
        XCTAssertEqual(try persistence.load()?.programs, before.programs)
        XCTAssertFalse(store.addProgram(Program(id: "new", name: "Failed create")))
        XCTAssertFalse(store.switchProgram(to: initial.id))
        XCTAssertFalse(store.deleteProgram(withId: initial.id))
        XCTAssertEqual(store.state.programs, before.programs)
        XCTAssertEqual(store.state.activeProgramId, before.activeProgramId)
    }

    @MainActor
    func testCoverPickerNarrowScreensInAllFiveLanguages() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "es", "fr"] {
            LanguageManager.setLanguage(language)
            let root = BuilderCoverPicker(programID: "custom", selection: .constant("machines")).environment(\.sizeCategory, .extraExtraExtraLarge)
            let host = UIHostingController(rootView: root)
            let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 850))
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
            let attachment = XCTAttachment(image: image); attachment.name = "program-covers-320-\(language)-large"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; previousWindow?.makeKeyAndVisible()
        }
    }

    @MainActor
    func testBuilderNarrowScreensInAllFiveLanguages() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr", "de", "es", "fr"] {
            LanguageManager.setLanguage(language)
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            var selected = fixture()
            selected.coverId = ProgramCover.allCases.max { LanguageManager.t("programs.cover." + $0.rawValue).count < LanguageManager.t("programs.cover." + $1.rawValue).count }?.rawValue
            _ = store.addProgram(selected, activate: false)
            for existing in [false, true] {
                let root = ProgramBuilderView(store: store, program: existing ? selected : nil) { }.environment(\.sizeCategory, .extraExtraExtraLarge)
                let host = UIHostingController(rootView: root)
                let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 850))
                window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                let attachment = XCTAttachment(image: image); attachment.name = "program-builder-\(existing ? "edit" : "new")-320-\(language)-large"; attachment.lifetime = .keepAlways; add(attachment)
                XCTAssertEqual(host.view.bounds.width, 320)
                window.isHidden = true; previousWindow?.makeKeyAndVisible()
            }
        }
    }
}
