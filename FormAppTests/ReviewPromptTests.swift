import XCTest
import SwiftUI
@testable import FormApp

final class ReviewPromptTests: XCTestCase {
    private let now: Int64 = 1_800_000_000_000
    private func record(_ id: String, warmup: Bool = false) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: id, programId: "review-plan", workoutId: "workout", workoutTitle: "Training",
            startedAt: "2026-10-25T08:00:00Z", completedAt: "2026-10-25T09:00:00Z", durationSeconds: 3600,
            totalCompletedSets: warmup ? 0 : 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Curl", sets: [SessionSetLog(setNumber: 1, weightKg: 20, reps: 8, isWarmup: warmup)], targetSets: 1)])
    }
    private func fifth() -> ReviewPromptState {
        (1...5).reduce(ReviewPromptState()) { $0.recording(record("review-\($1)"), now: now) }
    }
    func testOnlyTheFifthUniqueActualWorkoutBecomesEligible() {
        var state = ReviewPromptState()
        for index in 1...4 {
            state = state.recording(record("review-\(index)"), now: now)
            XCTAssertFalse(state.canAttempt(now: now))
        }
        state = state.recording(record("review-4"), now: now)
        XCTAssertEqual(state.countedSessionIds.count, 4)
        state = state.recording(record("review-5"), now: now)
        XCTAssertTrue(state.canAttempt(now: now))
    }
    func testImportsEmptyWarmupsAndInvalidLogsDoNotAdvanceTheCount() {
        var state = ReviewPromptState()
        state = state.recording(record("import-hevy"), now: now)
        var imported = record("old-export"); imported.programId = "imported"
        state = state.recording(imported, now: now)
        state = state.recording(record("warmup", warmup: true), now: now)
        var empty = record("empty"); empty.exerciseLogs = []
        state = state.recording(empty, now: now)
        var invalid = record("invalid"); invalid.exerciseLogs[0].sets[0].reps = 0
        state = state.recording(invalid, now: now)
        XCTAssertTrue(state.countedSessionIds.isEmpty)
        var bodyweight = record("bodyweight"); bodyweight.exerciseLogs[0].sets[0].weightKg = 0
        XCTAssertEqual(state.recording(bodyweight, now: now).countedSessionIds.count, 1)
    }
    func testAttemptIsRecordedWithoutClaimingARatingAndRequiresANewSaveAfterCooldown() throws {
        var state = fifth().attempting(now: now)
        XCTAssertEqual(state.lastAttemptEpochMillis, now); XCTAssertFalse(state.pending)
        state = state.recording(record("six"), now: now + 1)
        XCTAssertFalse(state.canAttempt(now: now + ReviewPromptState.cooldownMillis))
        state = state.recording(record("seven"), now: now + ReviewPromptState.cooldownMillis)
        XCTAssertTrue(state.canAttempt(now: now + ReviewPromptState.cooldownMillis))
        XCTAssertFalse(state.canAttempt(now: now - 1))
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertFalse(json.contains("rated")); XCTAssertFalse(json.contains("rating"))
    }
    func testAttemptAndUniqueIdsSurviveReload() {
        let name = "review-policy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = fifth().attempting(now: now)
        XCTAssertTrue(state.persist(to: defaults))
        XCTAssertEqual(ReviewPromptState.load(from: defaults), state)
        XCTAssertEqual(ReviewPromptState.load(from: defaults).recording(record("review-5"), now: now + ReviewPromptState.cooldownMillis), state)
    }
    @MainActor func testStoreCountsOnlyDeliberateSummarySavesAndDoesNotConsumeWhileBlocked() {
        let previousData = UserDefaults.standard.object(forKey: ReviewPromptState.storageKey)
        defer { if let previousData { UserDefaults.standard.set(previousData, forKey: ReviewPromptState.storageKey) }
                else { UserDefaults.standard.removeObject(forKey: ReviewPromptState.storageKey) } }
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        store.reviewPromptState = ReviewPromptState()
        store.completeActiveSession(record("background-save"), suggestSharingAfterSave: false)
        XCTAssertEqual(store.reviewPromptState.countedSessionIds.count, 0)
        for index in 1...5 { store.completeActiveSession(record("deliberate-\(index)"), suggestSharingAfterSave: true) }
        XCTAssertEqual(store.reviewPromptState.countedSessionIds.count, 5)
        XCTAssertFalse(store.consumeReviewPrompt(allowed: false, now: now))
        XCTAssertTrue(store.reviewPromptState.pending)
        XCTAssertTrue(store.consumeReviewPrompt(allowed: true, now: now))
        XCTAssertEqual(ReviewPromptState.load().lastAttemptEpochMillis, now)
        XCTAssertFalse(store.consumeReviewPrompt(allowed: true, now: now))
    }
    @MainActor func testRootDefersUntilSummaryAndAnUntrackedSheetHaveClosed() async throws {
        let store = AppStore.shared
        let oldPrompt = store.reviewPromptState, oldData = UserDefaults.standard.object(forKey: ReviewPromptState.storageKey)
        let oldSetup = store.isOnboardingCompleted, oldView = store.currentView, oldDraft = store.activeSession
        let oldTour = store.tourProgress, oldToast = store.currentToast
        let oldExercise = store.selectedExerciseId, oldHistory = store.selectedHistoryDetailDay
        let oldSocial = store.socialShareRequest
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        store.isOnboardingCompleted = true; store.currentView = .today; store.currentToast = nil
        store.selectedExerciseId = nil; store.selectedHistoryDetailDay = nil; store.socialShareRequest = nil
        store.updateTourProgress { _ in TourProgress(seen: Set(TourId.allCases)) }; TourController.shared.cancel()
        store.reviewPromptState = fifth()
        store.activeSession = ActiveSessionDraft(id: "review-cover", programId: "p", workout: Workout(id: "w", day: 1, title: "Training", exercises: [Exercise(id: "a", name: "Curl", sets: 1)]),
            startedAt: ISO8601DateFormatter().string(from: Date()), startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        store.isSessionPresented = true
        var attempts = 0
        ReviewPromptPresentation.testRequestHandler = { attempts += 1; XCTAssertNotNil(store.reviewPromptState.lastAttemptEpochMillis) }
        let host = UIHostingController(rootView: RootView())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)); window.windowScene = previousWindow?.windowScene
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852); window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            ReviewPromptPresentation.testRequestHandler = nil
            window.isHidden = true; previousWindow?.makeKeyAndVisible()
            store.isSessionPresented = false; store.activeSession = oldDraft; store.isOnboardingCompleted = oldSetup
            store.currentView = oldView; store.currentToast = oldToast; store.reviewPromptState = oldPrompt
            store.selectedExerciseId = oldExercise; store.selectedHistoryDetailDay = oldHistory; store.socialShareRequest = oldSocial
            store.updateTourProgress { _ in oldTour }; TourController.shared.cancel()
            if let oldData { UserDefaults.standard.set(oldData, forKey: ReviewPromptState.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: ReviewPromptState.storageKey) }
        }
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(attempts, 0)
        store.isSessionPresented = false
        try await Task.sleep(nanoseconds: 650_000_000)
        let sheet = UIViewController(); sheet.view.backgroundColor = .systemBackground
        host.present(sheet, animated: false)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(attempts, 0); XCTAssertTrue(store.reviewPromptState.pending)
        sheet.dismiss(animated: false)
        for _ in 0..<80 {
            if attempts == 1 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(attempts, 1)
        XCTAssertFalse(store.reviewPromptState.pending)
    }
}
