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
    /// Keys and sorted arguments stand in for translations, so both engines compare exact naming choices.
    private static func text(_ key: String, _ args: [String: Any]) -> String {
        args.isEmpty ? key : key + "(" + args.keys.sorted().map { "\($0)=\(args[$0]!)" }.joined(separator: ",") + ")"
    }
    private func generate(_ p: TrainingProfile) throws -> GeneratedTrainingPlan {
        try TrainingPlanGenerator.generate(p, catalog: XCTUnwrap(TrainingCatalog.bundled), exercises: ExerciseCatalog.canonicalExercises,
            programID: "personal-plan", text: Self.text)
    }
    /// Key-and-argument names exceed the 100-character program limit, so storage checks use bare keys.
    private func storable(_ p: TrainingProfile) throws -> GeneratedTrainingPlan {
        try TrainingPlanGenerator.generate(p, catalog: XCTUnwrap(TrainingCatalog.bundled), exercises: ExerciseCatalog.canonicalExercises,
            programID: "personal-plan", text: { key, _ in key })
    }
    private func gym() throws -> TrainingProfile {
        var p = TrainingProfile(); p.equipment = try XCTUnwrap(TrainingCatalog.bundled?.presets["commercial_gym"])
        p.equipmentConfirmed = true; p.minutes = 60; return p
    }
    private func role(_ exercise: Exercise) throws -> String {
        try XCTUnwrap(TrainingCatalog.bundled?.candidates.first { $0.id == exercise.exerciseId }?.role)
    }
    func testVisualEquipmentChoicesHaveReviewedArtworkAndASmallHomeSelection() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        let home = catalog.equipment.filter { $0.home == true }
        XCTAssertEqual(home.count, 12)
        XCTAssertTrue(home.allSatisfy { $0.artwork != nil })
        let gym = try XCTUnwrap(catalog.presets["commercial_gym"])
        XCTAssertTrue(catalog.equipment.filter { gym.contains($0.id) }.allSatisfy { $0.artwork != nil })
        let dedicated = catalog.equipment.filter { $0.artwork?.hasPrefix("equipment:") == true }
        XCTAssertEqual(dedicated.count, 17)
        for item in dedicated {
            XCTAssertEqual(item.artwork, "equipment:\(item.id)")
            XCTAssertNotNil(UIImage(named: "setup_equipment_" + item.id.replacingOccurrences(of: "-", with: "_")), item.id)
        }
        XCTAssertFalse(catalog.equipment.contains { $0.artwork?.hasPrefix("exercise:") == true })
    }

    func testOldSettingsDraftKeepsItsPreviewAtTheNewReviewStep() throws {
        let p = profile(["dumbbells"]), program = try generate(p).program
        let legacy = TrainingSetupStore.Draft(profile: p, step: 6, programId: program.id, program: program, flowVersion: nil)
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: "training_setup_draft_v1")
        let recovered = try XCTUnwrap(TrainingSetupStore.draft())
        XCTAssertEqual(recovered.step, 8)
        XCTAssertEqual(recovered.profile, p)
        XCTAssertEqual(recovered.program, program)
    }
    func testSettingsDraftVersionsPreserveEveryQuestionAndEditedPreview() throws {
        var p = try gym()
        p.experience = "advanced"; p.advancedLifts = true; p.priority = "shoulders"; p.excludedExerciseIds = ["barbell-back-squat"]
        var program = try generate(p).program
        program.name = "Edited preview"
        for version in 1...3 { for step in 1...(version == 1 ? 6 : (version == 2 ? 7 : 8)) {
            let expected = version == 1 ? (step == 6 ? 8 : step + (step >= 3 ? 1 : 0)) : (version == 2 && step == 7 ? 8 : step)
            TrainingSetupStore.saveDraft(.init(profile: p, step: step, programId: program.id, program: program, flowVersion: version))
            let recovered = try XCTUnwrap(TrainingSetupStore.draft())
            XCTAssertEqual(recovered.step, expected, "Version \(version), step \(step)")
            XCTAssertEqual(recovered.flowVersion, 3)
            XCTAssertEqual(recovered.profile, p)
            XCTAssertEqual(recovered.program, program)
        } }
        for (version, step) in [(1, 7), (2, 8), (3, 9), (4, 1)] {
            TrainingSetupStore.saveDraft(.init(profile: p, step: step, programId: program.id, program: program, flowVersion: version))
            XCTAssertNil(TrainingSetupStore.draft())
        }
    }

    @MainActor func testGymSetupDefaultsToReadyAndPreservesEditedInventories() throws {
        var pending = try gym(); pending.equipmentConfirmed = false
        var edited = try gym(); edited.equipment.removeAll { $0 == "leg-press" || $0 == "dumbbells" }
        var home = profile(); home.equipmentConfirmed = false
        let cases: [(String, TrainingProfile?, [String], Bool)] = [
            ("fresh", nil, pending.equipment, true), ("pending", pending, pending.equipment, true),
            ("edited", edited, edited.equipment, true), ("home", home, [], false)
        ]
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        for (name, original, equipment, confirmed) in cases {
            TrainingSetupStore.clearDraft()
            if let original { TrainingSetupStore.saveDraft(.init(profile: original, step: 4, programId: name, program: nil)) }
            let host = UIHostingController(rootView: TrainingSetupView(store: store, completeSetup: false, onClose: {}))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
            defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let recovered = try XCTUnwrap(TrainingSetupStore.draft())
            XCTAssertEqual(Set(recovered.profile.equipment), Set(equipment), name)
            XCTAssertEqual(recovered.profile.equipmentConfirmed, confirmed, name)
            if confirmed { XCTAssertNoThrow(try TrainingSetupStore.generate(recovered.profile, id: recovered.programId), name) }
            if name == "pending" {
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/gym-default-review.png"))
                let attachment = XCTAttachment(image: image); attachment.name = "gym-default"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    @MainActor func testRestoredExperienceSetsEligibilityWithoutChangingAnEditedPreview() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        var edited = try generate(gym()).program
        edited.name = "Edited preview"
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        for experience in ["beginner", "intermediate", "advanced"] {
            var p = try gym(); p.experience = experience; p.advancedLifts = experience == "beginner"
            TrainingSetupStore.saveDraft(.init(profile: p, step: 2, programId: edited.id, program: edited))
            let host = UIHostingController(rootView: TrainingSetupView(store: store, completeSetup: false, onClose: {}))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
            defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let draft = try XCTUnwrap(TrainingSetupStore.draft())
            XCTAssertEqual(draft.profile.advancedLifts, experience != "beginner", experience)
            XCTAssertEqual(draft.program, edited, experience)
            let eligible = TrainingPlanGenerator.eligible(draft.profile, catalog: catalog).map(\.id)
            XCTAssertEqual(eligible.contains("barbell-back-squat"), experience != "beginner", experience)
            XCTAssertFalse(eligible.contains("pull-ups"), experience)
        }
    }

    @MainActor func testSetupClearsLegacyExclusionsWithoutLosingMusclePriority() throws {
        var p = profile(["dumbbells"])
        p.priority = "row"; p.excludedExerciseIds = try XCTUnwrap(TrainingCatalog.bundled).candidates.map(\.id)
        TrainingSetupStore.saveDraft(.init(profile: p, step: 7, programId: "legacy-exclusions", program: nil))
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: TrainingSetupView(store: store, completeSetup: false, onClose: {}))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        defer { window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        host.view.layoutIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let recovered = try XCTUnwrap(TrainingSetupStore.draft())
        XCTAssertTrue(recovered.profile.excludedExerciseIds.isEmpty)
        XCTAssertEqual(recovered.profile.priority, "row")
        XCTAssertEqual(recovered.step, 7)
        XCTAssertFalse(try TrainingSetupStore.generate(recovered.profile, id: recovered.programId).program.workouts.isEmpty)
    }

    func testSharedFixturesMatchBothNativeEngines() throws {
        struct Fixture: Decodable { let name: String; let profile: TrainingProfile; let expected: String; let identity: String }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("training-generation-fixtures.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: file))
        XCTAssertEqual(fixtures.count, 16)
        for fixture in fixtures {
            let result = try generate(fixture.profile)
            let signature = result.program.workouts.map { workout in
                String(workout.day) + ":" + workout.exercises.map { ex in
                    [ex.exerciseId ?? "", String(ex.sets ?? 0), String(ex.reps?.min ?? 0), String(ex.reps?.max ?? 0),
                     String(ex.restSeconds ?? 0), String(ex.reps?.perSide ?? false)].joined(separator: "/")
                }.joined(separator: ",")
            }.joined(separator: ";") + "|" + result.warningKeys.joined(separator: ",")
            XCTAssertEqual(signature, fixture.expected, fixture.name)
            let identity = result.program.name + "|" + result.program.workouts.map { "\($0.title)/\($0.focus)" }.joined(separator: ";")
                + "|" + (result.program.coverId ?? "")
            XCTAssertEqual(identity, fixture.identity, fixture.name)
        }
    }
    func testBackToBackDaysAlternateRegionsWhenEquipmentAllows() throws {
        func regions(_ workout: Workout) -> Set<String> {
            if workout.title.contains("kind=setup.day.full") { return ["push", "pull", "lower"] }
            if workout.title.contains("kind=setup.day.upper") { return ["push", "pull"] }
            if workout.title.contains("kind=setup.day.push") { return ["push"] }
            if workout.title.contains("kind=setup.day.pull") { return ["pull"] }
            return ["lower"]
        }
        for gear in [try gym().equipment, ["dumbbells"], ["bands", "high-anchor", "low-anchor"]] {
            for mask in 1..<128 {
                let chosen = (1...7).filter { mask & (1 << ($0 - 1)) != 0 }
                guard (2...6).contains(chosen.count) else { continue }
                var p = profile(gear); p.selectedDays = chosen; p.minutes = 45
                let result = try generate(p), workouts = result.program.workouts
                XCTAssertEqual(workouts.map(\.day), chosen)
                for (index, workout) in workouts.enumerated() {
                    let next = workouts[(index + 1) % workouts.count]
                    if workout.day % 7 + 1 == next.day { XCTAssertTrue(regions(workout).isDisjoint(with: regions(next)), "\(gear) \(chosen)") }
                }
                XCTAssertFalse(result.warningKeys.contains("setup.warning.adjacent"))
                XCTAssertEqual(Set(workouts.map(\.title)).count, workouts.count)
                let spread = !chosen.indices.contains { chosen[$0] % 7 + 1 == chosen[($0 + 1) % chosen.count] }
                XCTAssertEqual(result.warningKeys.contains("setup.warning.alternating"), !spread && chosen.count <= 3, "\(gear) \(chosen)")
            }
        }
    }
    func testNamesDescribeGoalStructureEquipmentAndEachDaysLead() throws {
        let floor = try generate(profile())
        XCTAssertEqual(floor.program.name, "setup.name.formatEquipment(days=3,equipment=setup.name.equipment.bodyweight,goal=setup.name.goal.bulk,structure=setup.name.structure.full)")
        var split = try gym(); split.goal = "strength"; split.experience = "intermediate"; split.selectedDays = [1, 2, 4, 5]
        let plan = try generate(split)
        XCTAssertEqual(plan.program.name, "setup.name.format(days=4,goal=setup.name.goal.strength,structure=setup.name.structure.upperLower)")
        XCTAssertEqual(plan.program.workouts.map(\.title), [
            "setup.day.titled(emphasis=setup.emphasis.pair(first=setup.emphasis.push,second=setup.emphasis.row),kind=setup.day.upper)",
            "setup.day.titled(emphasis=setup.emphasis.squat,kind=setup.day.lower)",
            "setup.day.titled(emphasis=setup.emphasis.pair(first=setup.emphasis.shoulders,second=setup.emphasis.pull),kind=setup.day.upper)",
            "setup.day.titled(emphasis=setup.emphasis.hinge,kind=setup.day.lower)"])
        var six = try gym(); six.selectedDays = [1, 2, 3, 4, 5, 6]
        XCTAssertTrue(try generate(six).program.workouts.contains { $0.title.contains("kind=setup.day.legs") })
        XCTAssertEqual(try generate(profile(["dumbbells"])).program.workouts.first?.focus,
                       "setup.area.quads · setup.area.chest · setup.area.back · setup.area.hamstrings")
    }
    func testCoversFollowPriorityEquipmentGoalAndStructure() throws {
        func cover(_ p: TrainingProfile) throws -> String? { try generate(p).program.coverId }
        var intermediate = try gym(); intermediate.experience = "intermediate"
        func variant(_ change: (inout TrainingProfile) -> Void) -> TrainingProfile { var p = intermediate; change(&p); return p }
        var biceps = profile(["dumbbells"]); biceps.priority = "biceps"
        XCTAssertEqual(try cover(profile()), "core_abs_pose")
        XCTAssertEqual(try cover(profile(["dumbbells"])), "home_dumbbells")
        XCTAssertEqual(try cover(profile(["kettlebell"])), "studio_kettlebell_swing")
        XCTAssertEqual(try cover(biceps), "biceps_peak_pose")
        XCTAssertEqual(try cover(try gym()), "machines")
        XCTAssertEqual(try cover(intermediate), "full_body")
        XCTAssertEqual(try cover(variant { $0.selectedDays = [1, 4] }), "studio_chest_clasp")
        XCTAssertEqual(try cover(variant { $0.selectedDays = [1, 2, 4, 5] }), "upper_lower")
        XCTAssertEqual(try cover(variant { $0.selectedDays = [1, 2, 3, 4, 5, 6] }), "push_pull_legs")
        XCTAssertEqual(try cover(variant { $0.selectedDays = [1, 2, 3, 5, 6] }), "hypertrophy")
        XCTAssertEqual(try cover(variant { $0.goal = "strength" }), "strength_power")
        XCTAssertEqual(try cover(variant { $0.goal = "strength"; $0.selectedDays = [1, 2, 4, 5] }), "powerbuilding")
        XCTAssertEqual(try cover(variant { $0.goal = "cut" }), "obliques_side_pose")
        for goal in ["bulk", "cut", "strength", "maintain"] {
            for priority in ["", "push", "row", "squat", "shoulders", "biceps", "core"] {
                let id = try cover(variant { $0.goal = goal; $0.priority = priority })
                XCTAssertNotNil(ProgramCover(rawValue: id ?? ""), "\(goal) \(priority)")
            }
        }
    }
    func testSessionsRunMainLiftsFirstAndPairSquatsWithSingleLegWork() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        var advanced = try gym(); advanced.experience = "advanced"; advanced.advancedLifts = true; advanced.selectedDays = [1, 2, 4, 5]
        for p in [try gym(), advanced, profile(["dumbbells", "adjustable-bench"])] {
            for workout in try generate(p).program.workouts {
                let ranks = try workout.exercises.map { try XCTUnwrap(catalog.roles[role($0)]?.rank) }
                XCTAssertEqual(ranks, ranks.sorted(), workout.title)
                XCTAssertLessThanOrEqual(try workout.exercises.filter { try role($0) == "squat" }.count, 1, workout.title)
                XCTAssertEqual(workout.exercises.map(\.id), workout.exercises.indices.map { "personal-plan-d\(workout.day)-\($0 + 1)" })
            }
        }
    }
    func testExperienceAndGoalChooseTheMainLifts() throws {
        func lead(_ change: (inout TrainingProfile) -> Void) throws -> String? {
            var p = try gym(); change(&p); return try generate(p).program.workouts.first?.exercises.first?.exerciseId
        }
        XCTAssertEqual(try lead { _ in }, "leg-press")
        XCTAssertEqual(try lead { $0.experience = "intermediate"; $0.advancedLifts = true }, "barbell-back-squat")
        XCTAssertEqual(try lead { $0.experience = "intermediate"; $0.selectedDays = [1, 2, 4, 5] }, "barbell-bench-press")
        XCTAssertEqual(try lead { $0.goal = "strength"; $0.selectedDays = [1, 2, 4, 5] }, "barbell-bench-press")
        XCTAssertEqual(try lead { $0.selectedDays = [1, 2, 4, 5] }, "lever-chest-press")
        // Loaded variations stay ahead of bodyweight ones when equipment allows.
        XCTAssertFalse(try generate(profile(["dumbbells"])).program.workouts.flatMap(\.exercises).contains { $0.exerciseId == "bodyweight-squat" })
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
        XCTAssertTrue(ids(profile(["dumbbells"])).contains("dumbbell-curtsey-lunge"))
        XCTAssertFalse(ids(single).contains("dumbbell-curtsey-lunge"))
        XCTAssertTrue(ids(profile(["pull-up-bar"])).contains("scapular-pull-up"))
    }
    func testLoadedSingleLegWorkAndBarOnlyPullingFillTheirGaps() throws {
        func ids(_ p: TrainingProfile) throws -> [String] { try generate(p).program.workouts.flatMap(\.exercises).compactMap(\.exerciseId) }
        let dumbbells = try ids(profile(["dumbbells"]))
        XCTAssertTrue(dumbbells.contains("dumbbell-curtsey-lunge"))
        XCTAssertFalse(dumbbells.contains("bodyweight-rear-lunge"))
        // Holding dumbbells keeps the Bulgarian split squat ahead of the curtsey lunge when a bench is available.
        XCTAssertEqual(try generate(profile(["dumbbells", "adjustable-bench"])).program.workouts.last?.exercises.first?.exerciseId, "bulgarian-split-squat")
        let bar = try generate(profile(["pull-up-bar"]))
        XCTAssertTrue(bar.program.workouts.allSatisfy { $0.exercises.contains { $0.exerciseId == "scapular-pull-up" } })
        // Scapular pull-ups are partial-range work: the limited-pulling note stays and no pull day is built from them.
        XCTAssertTrue(bar.warningKeys.contains("setup.warning.pulling"))
        var backToBack = profile(["pull-up-bar"]); backToBack.selectedDays = [1, 2, 3]
        let consecutive = try generate(backToBack)
        XCTAssertTrue(consecutive.program.workouts.allSatisfy { $0.title.contains("kind=setup.day.full") })
        XCTAssertTrue(consecutive.warningKeys.contains("setup.warning.adjacent"))
        XCTAssertFalse(try ids(try gym()).contains("scapular-pull-up"))
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
    func testSessionsStaySensiblySizedAndWeeklyVolumeStaysBounded() throws {
        let catalog = try XCTUnwrap(TrainingCatalog.bundled)
        let inventories = [[], ["dumbbells"], ["dumbbells", "adjustable-bench"], ["bands", "high-anchor", "low-anchor"],
            ["kettlebell"], ["pull-up-bar"], try XCTUnwrap(catalog.presets["commercial_gym"])]
        for gear in inventories {
            for frequency in OnboardingFrequency.allCases {
                for experience in ["beginner", "intermediate", "advanced"] {
                    for minutes in [20, 45, 90] {
                        for priority in ["", "push", "squat", "core"] {
                            var p = profile(gear); p.experience = experience; p.advancedLifts = experience != "beginner"
                            p.selectedDays = frequency.defaultWeekdays; p.minutes = minutes; p.priority = priority
                            let workouts = try generate(p).program.workouts
                            let limit = try XCTUnwrap(catalog.limits[experience])
                            let focus = catalog.roles[priority]?.area
                            let label = "\(gear) \(experience) \(frequency.rawValue)d \(minutes)min '\(priority)'"
                            var weekly: [String: Int] = [:]
                            for workout in workouts {
                                XCTAssertTrue((3...limit.exercises).contains(workout.exercises.count), label)
                                XCTAssertTrue(workout.exercises.allSatisfy { (2...4).contains($0.sets ?? 0) }, label)
                                XCTAssertTrue(try workout.exercises.contains { ex in
                                    try role(ex) != "core" && catalog.candidates.first { $0.id == ex.exerciseId }?.compound == true
                                }, label)
                                var perArea: [String: Int] = [:]
                                for exercise in workout.exercises {
                                    perArea[try XCTUnwrap(catalog.roles[try role(exercise)]?.area), default: 0] += exercise.sets ?? 0
                                }
                                for (area, sets) in perArea {
                                    XCTAssertLessThanOrEqual(sets, area == focus ? 12 : 10, "\(label) \(area)")
                                    weekly[area, default: 0] += sets
                                }
                            }
                            for (area, sets) in weekly {
                                XCTAssertLessThanOrEqual(sets, limit.weeklySets + (area == focus ? 4 : 0), "\(label) \(area)")
                            }
                            if priority != "core" {
                                XCTAssertLessThanOrEqual(try workouts.filter { w in try w.exercises.contains { try role($0) == "core" } }.count, 3, label)
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
        // Without any pulling exercise a push/pull split would leave a near-empty day, so full-body days stay.
        XCTAssertTrue(result.warningKeys.contains("setup.warning.adjacent"))
        XCTAssertTrue(result.program.workouts.allSatisfy { $0.title.contains("kind=setup.day.full") })
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
        XCTAssertNoThrow(try ProgramEditing.validate(storable(profile(["dumbbells"])).program))
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
        var program = try storable(p).program; program.id = UUID().uuidString
        XCTAssertTrue(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertTrue(store.saveGeneratedPlan(profile: p, program: program, completeSetup: true))
        XCTAssertEqual(store.state.programs.count, before.programs.count + 1)
        XCTAssertEqual(Array(store.state.programs.prefix(before.programs.count)), before.programs)
        XCTAssertEqual(store.state.history, before.history)
        XCTAssertEqual(store.state.activeProgramId, program.id)
        let reloaded = AppStore()
        XCTAssertTrue(reloaded.isOnboardingCompleted)
        XCTAssertTrue(reloaded.state.programs.contains { $0.id == program.id })
        XCTAssertEqual(TrainingSetupStore.profile(), p.normalized())
    }

    @MainActor func testUnfinishedFirstLaunchStaysRequiredAfterSavingStarterData() throws {
        let persistence = AppStatePersistence(inMemory: true)
        let initial = AppStore(persistence: persistence)
        XCTAssertFalse(initial.isOnboardingCompleted)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "is_onboarding_completed") as? Bool, false)
        XCTAssertTrue(initial.saveState(initial.state, durable: true))
        XCTAssertNotNil(try persistence.load())
        for _ in 0..<2 {
            XCTAssertFalse(AppStore(persistence: persistence).isOnboardingCompleted)
        }
    }

    @MainActor func testSkipStartsOnBalancedBuildAfterRelaunch() throws {
        let persistence = AppStatePersistence(inMemory: true)
        let initial = AppStore(persistence: persistence)
        let programs = initial.state.programs
        XCTAssertNotEqual(initial.state.activeProgramId, "upper-lower-balanced")
        initial.skipSetup()
        XCTAssertTrue(initial.isOnboardingCompleted)
        XCTAssertEqual(initial.state.activeProgramId, "upper-lower-balanced")
        XCTAssertEqual(initial.state.programs, programs)
        try persistence.flush()
        let reloaded = AppStore(persistence: persistence)
        XCTAssertTrue(reloaded.isOnboardingCompleted)
        XCTAssertEqual(reloaded.state.activeProgramId, "upper-lower-balanced")
    }

    @MainActor func testSkipStaysCompletedAfterRelaunchAndLegacyInstallsStillMigrate() {
        let persistence = AppStatePersistence(inMemory: true)
        let initial = AppStore(persistence: persistence)
        initial.setOnboardingCompleted(true)
        XCTAssertTrue(initial.saveState(initial.state, durable: true))
        XCTAssertTrue(AppStore(persistence: persistence).isOnboardingCompleted)
        UserDefaults.standard.removeObject(forKey: "is_onboarding_completed")
        XCTAssertTrue(AppStore(persistence: persistence).isOnboardingCompleted)
    }

    @MainActor func testFailedDurableSaveRetainsSetupAndRetryCompletesIt() throws {
        struct StorageFailure: Error {}
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw StorageFailure() } })
        let store = AppStore(persistence: persistence)
        try persistence.flush()
        store.setOnboardingCompleted(false)
        let p = profile(["dumbbells"]), program = try storable(profile(["dumbbells"])).program
        TrainingSetupStore.saveDraft(.init(profile: p, step: 8, programId: program.id, program: program))
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
            let sizes: [ContentSizeCategory] = language == "en" ? [.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] : [.extraExtraExtraLarge]
            for size in sizes {
            for width in (language == "en" && size == .large ? [320.0, 390.0, 600.0] : [320.0]) {
            for location in ["home", "commercial_gym"] { for step in [2, 3, 4, 5, 6, 7, 8] {
                var rendered = profile(["dumbbells", "ez-bar", "plates"])
                rendered.location = location; rendered.experience = "advanced"; rendered.advancedLifts = true
                if location != "home" { rendered.equipment = try XCTUnwrap(TrainingCatalog.bundled?.presets["commercial_gym"]).filter { $0 != "calf-machine" } }
                if step == 8 && location != "home" { rendered.goal = "cut"; rendered.experience = "intermediate"; rendered.advancedLifts = false; rendered.selectedDays = [1, 2, 4, 5] }
                TrainingSetupStore.saveDraft(.init(profile: rendered, step: step, programId: "render-plan", program: nil))
                let host = UIHostingController(rootView: TrainingSetupView(store: store, completeSetup: false, onClose: {}).environment(\.sizeCategory, size))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
                window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(step == 4 ? 0.6 : 0.15))
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                let name = "training-setup-\(location)-\(language)-\(step)" + (size == .large ? "-regular" : (size == .accessibilityExtraExtraExtraLarge ? "-accessibility" : "")) + (width > 390 ? "-tablet" : (width > 320 ? "-wide" : ""))
                try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                if step == 5 || step == 7 || step == 8 {
                    func scrollView(in view: UIView) -> UIScrollView? {
                        if let scroll = view as? UIScrollView { return scroll }
                        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
                    }
                    let scroll = try XCTUnwrap(scrollView(in: host.view))
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    let bottom = UIGraphicsImageRenderer(bounds: host.view.bounds).image { context in host.view.layer.render(in: context.cgContext) }
                    try bottom.pngData()?.write(to: URL(fileURLWithPath: "/tmp/\(name)-bottom.png"))
                    let attachment = XCTAttachment(image: bottom); attachment.name = name + "-bottom"; attachment.lifetime = .keepAlways; add(attachment)
                }
                window.isHidden = true; previousWindow?.makeKeyAndVisible()
            } }
            }
            }
        }
    }
}
