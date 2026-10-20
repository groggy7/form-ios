import XCTest
import SwiftUI
@testable import FormApp

final class TrainingPlanGeneratorTests: XCTestCase {
    private var defaultsBefore: [(String, Any?)] = []
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        let keys = ["stored_app_state", "active_session_v1", "seeded_starters_v9", "seeded_starters_v10", "seeded_starters_v11", "training_profile_v1", "training_setup_draft_v1", "is_onboarding_completed"]
        defaultsBefore = keys.map { ($0, defaults.object(forKey: $0)) }
        keys.forEach { defaults.removeObject(forKey: $0) }
    }
    override func tearDown() {
        for (key, value) in defaultsBefore {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    private func profile(_ equipment: [String] = []) -> TrainingProfile {
        var p = TrainingProfile(); p.location = "home"; p.equipment = equipment; p.equipmentConfirmed = true; return p
    }
    private func generate(_ p: TrainingProfile) throws -> GeneratedTrainingPlan {
        try TrainingPlanGenerator.generate(p, catalog: XCTUnwrap(TrainingCatalog.bundled), exercises: ExerciseCatalog.canonicalExercises,
            programID: "personal-plan", text: { key, _ in key })
    }
    func testSharedFixturesMatchBothNativeEngines() throws {
        struct Fixture: Decodable { let name: String; let profile: TrainingProfile; let expected: String }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("training-generation-fixtures.json")
        for fixture in try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: file)) {
            let result = try generate(fixture.profile)
            let signature = result.program.workouts.map { workout in
                String(workout.day) + ":" + workout.exercises.map { ex in
                    [ex.exerciseId ?? "", String(ex.sets ?? 0), String(ex.reps?.min ?? 0), String(ex.reps?.max ?? 0),
                     String(ex.restSeconds ?? 0), String(ex.reps?.perSide ?? false)].joined(separator: "/")
                }.joined(separator: ",")
            }.joined(separator: ";") + "|" + result.warningKeys.joined(separator: ",")
            XCTAssertEqual(signature, fixture.expected, fixture.name)
        }
    }
    func testRequirementsNeverInventEquipmentOrPullingAbility() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        func ids(_ p: TrainingProfile) -> Set<String> { Set(TrainingPlanGenerator.eligible(p, catalog: catalog).map(\.id)) }
        XCTAssertFalse(ids(profile(["barbell"])).contains("barbell-row"))
        XCTAssertTrue(ids(profile(["barbell", "plates"])).contains("barbell-row"))
        XCTAssertFalse(ids(profile(["dumbbells"])).contains("dumbbell-bench-press"))
        XCTAssertTrue(ids(profile(["dumbbells"])).contains("dumbbell-floor-press"))
        XCTAssertTrue(ids(profile(["dumbbells", "adjustable-bench"])).contains("dumbbell-bench-press"))
        var single = profile(["dumbbells"]); single.dumbbellPair = false
        XCTAssertFalse(ids(single).contains("dumbbell-floor-press")); XCTAssertTrue(ids(single).contains("one-arm-dumbbell-row"))
        XCTAssertFalse(ids(profile(["bands"])).contains("resistance-band-lat-pulldown"))
        XCTAssertTrue(ids(profile(["bands", "high-anchor"])).contains("resistance-band-lat-pulldown"))
        XCTAssertFalse(ids(profile(["ez-bar", "plates"])).contains("barbell-row"))
        var bar = profile(["pull-up-bar"])
        XCTAssertFalse(ids(bar).contains("pull-ups")); bar.pullUpReps = 3; XCTAssertTrue(ids(bar).contains("pull-ups"))
        XCTAssertFalse(ids(profile(["rings"])).contains("ring-inverted-row"))
        XCTAssertTrue(ids(profile(["rings", "suspension-anchor"])).contains("ring-inverted-row"))
    }
    func testEquipmentDaysTimeAndExactMediaAcrossProfiles() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        let inventories = [[], ["dumbbells"], ["bands"], ["bands", "high-anchor", "low-anchor"], ["barbell", "plates"],
            ["pull-up-bar"], ["dumbbells", "adjustable-bench"], catalog.presets["commercial_gym"]!]
        for inventory in inventories {
            for frequency in OnboardingFrequency.allCases {
                for goal in ["bulk", "cut", "strength", "maintain"] {
                    for experience in ["beginner", "intermediate", "advanced"] {
                        for minutes in [20, 30, 45, 60, 75, 90] {
                            var p = profile(inventory); p.selectedDays = frequency.defaultWeekdays; p.goal = goal
                            p.experience = experience; p.minutes = minutes; p.pullUpReps = 3
                            let result = try generate(p)
                            XCTAssertEqual(result.program.workouts.map(\.day), p.selectedDays)
                            XCTAssertTrue(result.estimatedMinutes.allSatisfy { $0 <= minutes })
                            let allowed = Set(TrainingPlanGenerator.eligible(p, catalog: catalog).map(\.id))
                            for workout in result.program.workouts {
                                XCTAssertFalse(workout.exercises.isEmpty)
                                XCTAssertEqual(Set(workout.exercises.compactMap(\.exerciseId)).count, workout.exercises.count)
                                for exercise in workout.exercises {
                                    XCTAssertTrue(allowed.contains(exercise.exerciseId ?? ""))
                                    XCTAssertEqual(exercise.movementAssetId, ExerciseCatalog.canonicalExercises[exercise.exerciseId ?? ""]?.movementAssetId)
                                    XCTAssertNotNil(exercise.reps); XCTAssertNotNil(exercise.restSeconds)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    func testLimitationsAndExclusionsAreHonest() throws {
        var p = profile(); p.selectedDays = [7, 1, 2]
        let result = try generate(p)
        XCTAssertEqual(result.program.workouts.map(\.day), [1, 2, 7])
        XCTAssertTrue(result.warningKeys.contains("setup.warning.pulling"))
        XCTAssertTrue(result.warningKeys.contains("setup.warning.hamstrings"))
        XCTAssertTrue(result.warningKeys.contains("setup.warning.adjacent"))
        p = profile(["dumbbells"]); p.excludedExerciseIds = ["dumbbell-floor-press"]
        XCTAssertFalse(try generate(p).program.workouts.flatMap(\.exercises).contains { $0.exerciseId == "dumbbell-floor-press" })
        XCTAssertEqual(try generate(p).program, try generate(p).program)
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        func pushSets(_ result: GeneratedTrainingPlan) -> Int {
            result.program.workouts.flatMap(\.exercises).filter { ex in catalog.candidates.first { $0.id == ex.exerciseId }?.role == "push" }.reduce(0) { $0 + ($1.sets ?? 0) }
        }
        p = profile(["dumbbells", "adjustable-bench"]); p.minutes = 60
        let balanced = try generate(p); p.priority = "push"
        XCTAssertGreaterThan(pushSets(try generate(p)), pushSets(balanced))
    }
    func testIncompleteProfilesFailAndGeneratedProgramsValidate() throws {
        var p = profile(); p.equipmentConfirmed = false
        XCTAssertThrowsError(try generate(p))
        p = profile(); p.selectedDays = [1]; XCTAssertThrowsError(try generate(p))
        p = profile(["unknown-item"]); XCTAssertThrowsError(try generate(p))
        p = profile(); p.excludedExerciseIds = try XCTUnwrap(TrainingCatalog.bundled).candidates.map(\.id)
        XCTAssertThrowsError(try generate(p))
        XCTAssertNoThrow(try ProgramEditing.validate(generate(profile(["dumbbells"])).program))
    }
    @MainActor func testSavingAddsOneIndependentProgramAndRetryDoesNotDuplicateIt() throws {
        let store = AppStore(), before = store.state
        let previousComplete = UserDefaults.standard.object(forKey: "is_onboarding_completed")
        defer {
            _ = store.saveState(before, durable: true)
            if let previousComplete { UserDefaults.standard.set(previousComplete, forKey: "is_onboarding_completed") }
            else { UserDefaults.standard.removeObject(forKey: "is_onboarding_completed") }
        }
        let p = profile(["dumbbells"])
        var program = try generate(p).program; program.id = UUID().uuidString
        XCTAssertTrue(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertTrue(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertEqual(store.state.programs.count, before.programs.count + 1)
        XCTAssertEqual(Array(store.state.programs.prefix(before.programs.count)), before.programs)
        XCTAssertEqual(store.state.history, before.history)
        XCTAssertEqual(store.state.activeProgramId, program.id)
        let reloaded = AppStore()
        XCTAssertTrue(reloaded.state.programs.contains { $0.id == program.id })
        XCTAssertEqual(TrainingSetupStore.profile(), p.normalized())
    }

    @MainActor func testFailedDurableSaveRetainsSetupAndRetryCompletesIt() throws {
        struct StorageFailure: Error {}
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw StorageFailure() } })
        let store = AppStore(persistence: persistence)
        try persistence.flush()
        store.setOnboardingCompleted(false)
        let p = profile(["dumbbells"]), program = try generate(profile(["dumbbells"])).program
        TrainingSetupStore.saveDraft(.init(profile: p, step: 6, programId: program.id, program: program))
        let before = store.state
        fail = true
        XCTAssertFalse(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertEqual(store.state.programs, before.programs)
        XCTAssertEqual(store.state.activeProgramId, before.activeProgramId)
        XCTAssertEqual(store.state.history, before.history)
        XCTAssertFalse(store.isOnboardingCompleted)
        XCTAssertEqual(TrainingSetupStore.draft()?.program, program)
        XCTAssertNil(TrainingSetupStore.profile())
        fail = false
        XCTAssertTrue(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertTrue(store.isOnboardingCompleted)
        XCTAssertNil(TrainingSetupStore.draft())
    }

    @MainActor func testNarrowLargeTextEquipmentAndPreviewInAllLanguages() throws {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        let store = AppStore()
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            for step in [3, 6] {
                TrainingSetupStore.saveDraft(.init(profile: profile(["dumbbells", "ez-bar", "plates"]), step: step, programId: "render-plan", program: nil))
                let host = UIHostingController(rootView: TrainingSetupView(store: store, onClose: {}).environment(\.sizeCategory, .extraExtraExtraLarge))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
                window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                let name = "training-setup-\(language)-\(step)"
                try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; previousWindow?.makeKeyAndVisible()
            }
        }
    }
}
