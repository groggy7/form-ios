import XCTest
@testable import FormApp

final class AuditFollowupTests: XCTestCase {
    func testLoggingFollowsTheLoadEachExerciseActuallyUses() {
        // Landmine work loads a barbell sleeve; rings, suspension trainers and the ab wheel are bodyweight.
        for id in ["landmine-press", "landmine-single-arm-press", "landmine-squat", "landmine-180"] {
            let exercise = Exercise(name: id, exerciseId: id)
            XCTAssertFalse(WorkoutSessionUtils.defaultsToZeroAddedWeight(exercise), id)
            XCTAssertFalse(WorkoutSessionUtils.allowsZeroWeight(exercise), id)
        }
        for id in ["suspension-trainer-row", "ring-inverted-row", "ring-incline-push-up", "ab-wheel-rollout"] {
            let exercise = Exercise(name: id, exerciseId: id)
            XCTAssertTrue(WorkoutSessionUtils.defaultsToZeroAddedWeight(exercise), id)
            XCTAssertTrue(WorkoutSessionUtils.allowsZeroWeight(exercise), id)
        }
    }

    func testLoadFreeSessionsReadAsBodyweightInsteadOfZeroVolume() {
        XCTAssertEqual(WorkoutSessionUtils.bodyweightVolumeLabel(0, completedSets: 6), LanguageManager.t("exercise.history.bodyweight"))
        XCTAssertNil(WorkoutSessionUtils.bodyweightVolumeLabel(0, completedSets: 0))
        XCTAssertNil(WorkoutSessionUtils.bodyweightVolumeLabel(1200, completedSets: 6))
    }

    func testWorkoutRecordedNoticeUsesBodyweightAndTheSelectedUnit() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")
        XCTAssertEqual(WorkoutSessionUtils.workoutRecordedNotice(0, completedSets: 6, unit: .kg), "Workout recorded: 6 sets at bodyweight.")
        XCTAssertEqual(WorkoutSessionUtils.workoutRecordedNotice(1200, completedSets: 6, unit: .kg), "Workout recorded: 6 sets, 1,200 kg volume.")
        XCTAssertEqual(WorkoutSessionUtils.workoutRecordedNotice(1200, completedSets: 6, unit: .lbs), "Workout recorded: 6 sets, 2,646 lbs volume.")
        XCTAssertEqual(WorkoutSessionUtils.workoutRecordedNotice(0, completedSets: 0, unit: .kg), "Workout recorded: 0 sets, 0 kg volume.")
        LanguageManager.setLanguage("es")
        XCTAssertEqual(WorkoutSessionUtils.workoutRecordedNotice(0, completedSets: 4, unit: .lbs), "Entrenamiento registrado: 4 series con peso corporal.")
    }

    // MARK: - Machine taken? (Pro exercise swaps)

    private func swapFixture(_ id: String, instance: String) -> Exercise {
        var exercise = ExerciseCatalog.canonicalExercises[id]!.toExercise()
        exercise.id = instance
        exercise.sets = 3
        exercise.reps = RepTarget(min: 8, max: 12)
        exercise.restSeconds = 90
        return exercise
    }

    func testCuratedSwapsComeFirstInTheirAuthoredOrder() {
        let suggestions = ExerciseSwaps.suggestions(for: "leg-press")
        XCTAssertEqual(suggestions.map(\.exerciseId),
            ["sled-hack-squat", "lever-belt-squat", "pendulum-squat", "lever-vertical-squat", "goblet-squat"])
        XCTAssertTrue(suggestions.allSatisfy(\.samePattern))
        XCTAssertFalse(ExerciseSwaps.suggestions(for: "leg-press", excluding: ["sled-hack-squat"])
            .contains { $0.exerciseId == "sled-hack-squat" })
    }

    func testUncuratedSwapsUseTheSameRankerAsAndroid() {
        // Android's ExerciseSwapsTest asserts the same list.
        XCTAssertEqual(ExerciseSwaps.suggestions(for: "barbell-curl").map(\.exerciseId),
            ["band-biceps-curl", "barbell-preacher-curl", "cable-curl", "cable-drag-curl",
             "cable-incline-biceps-curl", "cable-overhead-curl"])
        XCTAssertTrue(ExerciseSwaps.suggestions(for: "not-a-canonical-exercise").isEmpty)
        XCTAssertTrue(ExerciseSwaps.suggestions(for: nil).isEmpty)
    }

    func testReplacementKeepsThePrescriptionAndFollowsTheSubstitutesLaterality() {
        let row = swapFixture("cable-seated-row", instance: "w-row")
        let oneArm = ExerciseSwaps.replacement(for: row, substituteId: "one-arm-dumbbell-row", takenIds: ["w-row"])!
        XCTAssertEqual(oneArm.exerciseId, "one-arm-dumbbell-row")
        XCTAssertEqual(oneArm.sets, 3)
        XCTAssertEqual(oneArm.restSeconds, 90)
        XCTAssertEqual(oneArm.reps, RepTarget(min: 8, max: 12, perSide: true))
        XCTAssertNotEqual(oneArm.id, row.id)
        let back = ExerciseSwaps.replacement(for: oneArm, substituteId: "cable-seated-row", takenIds: [oneArm.id])!
        XCTAssertEqual(back.reps?.perSide, false)
        XCTAssertNil(ExerciseSwaps.replacement(for: row, substituteId: "not-a-canonical-exercise", takenIds: []))
    }

    func testReplacementIdsStayUniqueWhenSuffixedIdsAreTaken() {
        // A length-based suffix settled on base-99 forever once these were taken; Android asserts the same.
        let row = swapFixture("cable-seated-row", instance: "w-" + String(repeating: "x", count: 90))
        let base = String("\(row.id)-swap-one-arm-dumbbell-row".prefix(96))
        let taken: Set = [row.id, base, "\(base)-96", "\(base)-99", "\(base)-2"]
        XCTAssertEqual(ExerciseSwaps.replacement(for: row, substituteId: "one-arm-dumbbell-row", takenIds: taken)?.id, "\(base)-3")
    }

    func testReplacingSwapsTheExerciseInPlaceUntilAWorkingSetIsCompleted() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let press = swapFixture("lever-chest-press", instance: "w-press")
        let curl = swapFixture("cable-curl", instance: "w-curl")
        let workout = Workout(id: "w", day: 1, title: "W", exercises: [press, curl])
        store.activeSession = ActiveSessionDraft(programId: "p", workout: workout, startedAt: "2026-10-16T10:00:00.000Z",
            startedAtEpochMillis: 0, setsByExercise: WorkoutSessionUtils.initialSets(for: workout))
        defer { store.activeSession = nil }

        let replaced = store.replaceExercise(exerciseId: press.id, substituteId: "dumbbell-bench-press")
        let draft = store.activeSession!
        XCTAssertEqual(draft.workout.exercises.map(\.id), [replaced!.id, curl.id])
        XCTAssertEqual(draft.workout.id, "w")
        XCTAssertEqual(draft.setsByExercise[replaced!.id]?.count, 3)
        XCTAssertNil(draft.setsByExercise[press.id])

        var logged = draft
        logged.setsByExercise[replaced!.id]![0].isCompleted = true
        logged.setsByExercise[replaced!.id]![0].weightInput = "30"
        logged.setsByExercise[replaced!.id]![0].repsInput = "10"
        store.activeSession = logged
        XCTAssertNil(store.replaceExercise(exerciseId: replaced!.id, substituteId: "lever-chest-press"))
        XCTAssertEqual(store.activeSession?.workout.exercises.first?.exerciseId, "dumbbell-bench-press")
    }

    func testExerciseSwapsAreProAndUseTheGeneralPaywall() {
        let manager = ProAccessManager.shared
        manager.resetOverrides()
        defer { manager.resetOverrides() }
        XCTAssertFalse(manager.isFeatureUnlocked(.exerciseSwaps))
        manager.updateSubscriptionStatus(active: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.exerciseSwaps))
        XCTAssertNil(ProPaywallSheet(feature: .exerciseSwaps).feature)
        XCTAssertEqual(ProPaywallSheet(feature: .formLab).feature, .formLab)
        XCTAssertEqual(LanguageManager.t(ProFeature.exerciseSwaps.titleKey), "Machine Taken? Swaps")
    }

    // MARK: - Full-backup restore bounds

    private func preservingDefaults(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        try body()
    }

    func testRestoreBoundsCraftedNumbersAndIdentitiesBeforeSaving() throws {
        try preservingDefaults {
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            let exercise = Exercise(id: "e", name: "Bench", sets: 1_000, restSeconds: .max)
            let program = Program(id: "p", name: "Plan", workouts: [Workout(id: "w", day: 99, title: "Upper", exercises: [exercise, exercise])])
            let now = ISO8601DateFormatter().string(from: Date())
            let set = SessionSetLog(setNumber: .max, weightKg: 1e100, reps: .max)
            let record = WorkoutSessionRecord(id: "s", programId: "p", workoutId: "w", workoutTitle: "Upper", startedAt: now, completedAt: now,
                durationSeconds: .max, totalVolumeKg: 1e100, totalCompletedSets: .max,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: Array(repeating: set, count: 150), targetSets: .max)], isComplete: true)
            let crafted = StoredAppState(programs: [program, program], activeProgramId: "p", history: [record, record])
            XCTAssertTrue(store.restoreBackupJson(String(decoding: try JSONEncoder().encode(FullBackupDocument(state: crafted, weightUnit: .kg)), as: UTF8.self)))

            for state in [store.state, try XCTUnwrap(try store.statePersistence.load())] {
                XCTAssertEqual(state.programs.map(\.id).first, "p")
                XCTAssertEqual(Set(state.programs.map(\.id)).count, 2)
                let workout = try XCTUnwrap(state.programs.first?.workouts.first)
                XCTAssertEqual(workout.day, 7)
                XCTAssertEqual(workout.exercises.map(\.id).first, "e")
                XCTAssertEqual(Set(workout.exercises.map(\.id)).count, 2)
                XCTAssertEqual(workout.exercises.map(\.sets), [100, 100])
                XCTAssertEqual(workout.exercises.map(\.restSeconds), [900, 900])
                XCTAssertEqual(state.history.count, 1)
                let restored = try XCTUnwrap(state.history.first)
                XCTAssertEqual(restored.durationSeconds, 7 * 24 * 60 * 60)
                XCTAssertEqual(restored.totalVolumeKg, 100_000_000)
                XCTAssertEqual(restored.totalCompletedSets, 10_000)
                let log = try XCTUnwrap(restored.exerciseLogs.first)
                XCTAssertEqual(log.targetSets, 100)
                XCTAssertEqual(log.sets.count, 100)
                XCTAssertEqual(log.sets.first, SessionSetLog(setNumber: 100, weightKg: 9_999, reps: 999))
            }
            XCTAssertEqual(store.state.history.first.map { WeightUnit.lbs.formatVolume($0.totalVolumeKg) }, WeightUnit.lbs.formatVolume(100_000_000))
        }
    }

    func testRestoreRejectsBackupsFromANewerSchemaBeforeChangingAnything() throws {
        try preservingDefaults {
            let store = AppStore(persistence: AppStatePersistence(inMemory: true))
            let before = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(store.exportBackupJson().utf8)) as? [String: Any])
            var newer = before
            newer["schemaVersion"] = StoredAppState.currentSchemaVersion + 1
            XCTAssertFalse(store.restoreBackupJson(String(decoding: try JSONSerialization.data(withJSONObject: newer), as: UTF8.self)))
            let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(store.exportBackupJson().utf8)) as? [String: Any])
            XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: before))
            XCTAssertTrue(store.restoreBackupJson(String(decoding: try JSONSerialization.data(withJSONObject: before), as: UTF8.self)))
        }
    }

    func testRealBackupsPassTheRestoreBoundsUnchanged() throws {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for name in ["heavylifter_backup", "heavylifter_fresh_week_backup"] {
            let url = Bundle(for: AuditFollowupTests.self).url(forResource: name, withExtension: "json")
                ?? testDir.appendingPathComponent("../FormApp/Resources/Fixtures/\(name).json").standardized
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(StoredAppState.self, from: data)
            let restored = try JSONDecoder().decode(FullBackupDocument.self, from: data).state
            XCTAssertEqual(try encoder.encode(restored), try encoder.encode(raw), name)
        }
    }

    func testDisplayFormattersSaturateInsteadOfTrapping() {
        XCTAssertEqual(WeightUnit.displayInt(102), 102)
        XCTAssertEqual(WeightUnit.displayInt(1e100), 1_000_000_000_000_000)
        XCTAssertEqual(WeightUnit.displayInt(-1e100), -1_000_000_000_000_000)
        XCTAssertEqual(WeightUnit.displayInt(.infinity), 0)
        XCTAssertEqual(WeightUnit.displayInt(.nan), 0)
        XCTAssertEqual(WeightUnit.kg.formatWeight(100), "100")
        XCTAssertEqual(WeightUnit.lbs.formatWeight(100), "220")
        XCTAssertEqual(WeightUnit.kg.formatWeight(1e100), "1000000000000000")
        XCTAssertEqual(WeightUnit.lbs.formatWeight(-1e100), "-1000000000000000")
        for unit in WeightUnit.allCases {
            XCTAssertFalse(unit.formatVolume(1e100).isEmpty)
            let metrics = WeeklyGoalProgressMetrics(completedWorkouts: 1, totalWorkouts: 1, totalVolumeKg: 1e100, activeDurationSeconds: 0, prsHitCount: 0)
            XCTAssertEqual(metrics.formattedVolume(unit: unit), unit.formatVolume(1e100))
        }
    }

    // 2026-10-18 audit follow-up

    private func rampLoads(working: Double, bar: Double, plates: [Double]?, unit: WeightUnit = .kg) -> [Double] {
        let ramp = WarmupPlateEngine.generateWarmupRamp(workingWeightKg: unit.toCanonicalKg(working),
                                                        barWeightKg: unit.toCanonicalKg(bar), availablePlates: plates, unit: unit)
        XCTAssertTrue(ramp.steps.allSatisfy { $0.platesResult?.isExactMatch == true }, "Every step loads exactly")
        return ramp.steps.map { (unit.toDisplay($0.weightKg) * 100).rounded() / 100 }
    }

    func testWarmupStepsCountFromTheBarSoEveryStepLoads() {
        XCTAssertEqual(rampLoads(working: 100, bar: 15, plates: [5]), [15, 55, 75, 85])
        // Only the 60 kg step fits below the working load; 40 kg cannot be made with 20 kg plates.
        XCTAssertEqual(rampLoads(working: 100, bar: 20, plates: [20]), [20, 60])
        XCTAssertEqual(rampLoads(working: 225, bar: 45, plates: [45, 25, 10, 5], unit: .lbs), [45, 115, 155, 195])
    }

    func testStandardPlatesKeepTheirWarmupSteps() {
        XCTAssertEqual(rampLoads(working: 100, bar: 20, plates: nil), [20, 50, 70, 85])
        XCTAssertEqual(rampLoads(working: 225, bar: 45, plates: nil, unit: .lbs), [45, 115, 160, 190])
    }

    private func benchRecord(_ id: String, _ startedAt: String, working: [Double], warmups: [Double] = []) -> WorkoutSessionRecord {
        let sets = warmups.enumerated().map { SessionSetLog(setNumber: $0.offset + 1, weightKg: $0.element, reps: 5, isWarmup: true) }
            + working.enumerated().map { SessionSetLog(setNumber: $0.offset + 1, weightKg: $0.element, reps: 5) }
        return WorkoutSessionRecord(id: id, programId: "p", workoutId: "w", workoutTitle: "Workout", startedAt: startedAt,
                                    completedAt: startedAt, durationSeconds: 1800,
                                    exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: sets)])
    }

    func testAHeavierWarmupIsNotAPersonalRecord() {
        let baseline = benchRecord("a", "2026-10-01T10:00:00Z", working: [100])
        let session = benchRecord("b", "2026-10-15T10:00:00Z", working: [100], warmups: [120])
        let history = [baseline, session]
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(PersonalRecordTracker.countPrsForWeek(history: history, currentWeekKey: "2026-W42", timeZone: utc), 0)
        XCTAssertTrue(PersonalRecordTracker.findSessionPrExercises(history: history, targetRecord: session).isEmpty)
        XCTAssertEqual(PersonalRecordTracker.computeExerciseHistoryStats(history: history, exerciseName: "Barbell Bench Press").prWeightKg, 100)
    }

    func testAWarmupOnlySessionIsNotABaseline() {
        let warmupsOnly = benchRecord("a", "2026-10-01T10:00:00Z", working: [], warmups: [60])
        let first = benchRecord("b", "2026-10-15T10:00:00Z", working: [100])
        XCTAssertEqual(PersonalRecordTracker.countPrsForWeek(history: [warmupsOnly, first], currentWeekKey: "2026-W42",
                                                             timeZone: TimeZone(identifier: "UTC")!), 0)
    }
}
