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
}
