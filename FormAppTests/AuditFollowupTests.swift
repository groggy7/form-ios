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
}
